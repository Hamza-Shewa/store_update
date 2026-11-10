import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'platform_interface.dart';
import 'policy.dart';

/// What the update UI shows.
enum UpdatePhase {
  /// Nothing.
  idle,

  /// "A new version is ready": the background download offer.
  offerFlexible,

  /// The background download is running ([StoreUpdateController.progress]).
  downloading,

  /// Downloaded: "Restart to update".
  readyToInstall,

  /// A required update was not installed: the app waits behind an explanation.
  required,

  /// iOS: a newer App Store version.
  offerStore,
}

/// Checks the store on start and on every resume, and drives the update UI
/// (see `StoreUpdateGate`). It never throws: a failed check, no network or a
/// build not installed from the store simply shows nothing.
class StoreUpdateController extends ChangeNotifier with WidgetsBindingObserver {
  StoreUpdateController({
    StoreUpdatePlatform? platform,
    this.policy = const UpdatePolicy(),
    this.appStoreCountry = 'us',
    DateTime Function()? clock,
    this.checkTimeout = const Duration(seconds: 10),
  }) : _platform = platform ?? StoreUpdatePlatform.instance,
       _clock = clock ?? DateTime.now;

  /// Shared preferences key: when an optional update was last offered.
  static const kLastPrompt = 'store_update.last_prompt';

  /// Shared preferences key: when a network check (iOS) last ran.
  static const kLastCheck = 'store_update.last_check';

  final StoreUpdatePlatform _platform;
  final DateTime Function() _clock;

  final UpdatePolicy policy;

  /// The App Store storefront to look in, as a two-letter country code.
  final String appStoreCountry;

  /// How long to wait for the store before showing nothing.
  final Duration checkTimeout;

  UpdatePhase _phase = UpdatePhase.idle;

  /// What the UI shows now.
  UpdatePhase get phase => _phase;

  bool _offerRequired = false;

  /// On [UpdatePhase.offerFlexible]: the offer has no "Later" (a required
  /// release Play allows only as a background download).
  bool get offerRequired => _offerRequired;

  double? _progress;

  /// Download progress 0..1; null while the size is unknown.
  double? get progress => _progress;

  bool _immediateFailed = false;

  /// On [UpdatePhase.required]: Play's update failed rather than being closed.
  bool get immediateFailed => _immediateFailed;

  String? _storeVersion;

  /// On [UpdatePhase.offerStore]: the App Store's version.
  String? get storeVersion => _storeVersion;

  bool _started = false;
  bool _checking = false;
  bool _immediateRunning = false;
  bool _disposed = false;
  StreamSubscription<DownloadProgress>? _progressSub;

  /// Starts watching app resumes and runs the first check. Safe to call twice.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// Asks the store and updates [phase]. Network checks (iOS) run at most once
  /// per [UpdatePolicy.promptGap]; Play's is a local call, needed on every
  /// resume to pick up a finished download or an interrupted required update.
  Future<void> check() async {
    if (_checking || _immediateRunning || _disposed) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = _clock();
      if (_platform.checkUsesNetwork &&
          !policy.promptDue(_time(prefs, kLastCheck), now)) {
        return;
      }

      StoreCheck? result;
      try {
        result = await _platform
            .check(appStoreCountry: appStoreCountry)
            .timeout(checkTimeout);
      } catch (_) {
        result = null;
      }
      if (_disposed) return;
      if (result == null) {
        // Never keep the app blocked on a check that could not run.
        if (_phase == UpdatePhase.required) _set(UpdatePhase.idle);
        return;
      }
      if (_platform.checkUsesNetwork) {
        await prefs.setInt(kLastCheck, now.millisecondsSinceEpoch);
      }
      final decision = switch (result) {
        PlayCheck(:final info) => policy.decideAndroid(
          info,
          lastPrompt: _time(prefs, kLastPrompt),
          now: now,
        ),
        AppStoreCheck c => decideIos(
          storeVersion: c.storeVersion,
          currentVersion: c.currentVersion,
          minimumOs: c.minimumOs,
          deviceOs: c.deviceOs,
        ),
      };
      await _apply(decision, prefs, now);
    } catch (_) {
      // Preferences unavailable or similar: show nothing.
    } finally {
      _checking = false;
    }
  }

  Future<void> _apply(
    UpdateDecision decision,
    SharedPreferences prefs,
    DateTime now,
  ) async {
    switch (decision) {
      case NoUpdate():
        if (_phase == UpdatePhase.required ||
            _phase == UpdatePhase.downloading ||
            _phase == UpdatePhase.readyToInstall) {
          _stopListening();
          _set(UpdatePhase.idle);
        }
      case OfferFlexible(:final required):
        if (_phase != UpdatePhase.idle && _phase != UpdatePhase.required) {
          return;
        }
        if (!required) {
          await prefs.setInt(kLastPrompt, now.millisecondsSinceEpoch);
        }
        _offerRequired = required;
        _set(UpdatePhase.offerFlexible);
      case StartImmediate() || ResumeImmediate():
        // Once the user closed Play's screen, wait for "Update now" instead of
        // reopening it on every resume.
        if (_phase != UpdatePhase.required) await _runImmediate();
      case ShowDownloading():
        _listen();
        _set(UpdatePhase.downloading);
      case ShowReadyToInstall():
        _set(UpdatePhase.readyToInstall);
      case OfferStoreVersion(:final version):
        if (_phase != UpdatePhase.idle) return;
        await prefs.setInt(kLastPrompt, now.millisecondsSinceEpoch);
        _storeVersion = version;
        _set(UpdatePhase.offerStore);
    }
  }

  /// "Update" on an offer: starts the background download (Android) or shows
  /// the App Store page (iOS).
  Future<void> accept() async {
    if (_phase == UpdatePhase.offerStore) {
      _set(UpdatePhase.idle);
      await openStore();
      return;
    }
    if (_phase != UpdatePhase.offerFlexible) return;
    _progress = null;
    _listen();
    _set(UpdatePhase.downloading);
    final result = await _safe(_platform.startFlexible);
    if (result != UpdateFlowResult.accepted &&
        _phase == UpdatePhase.downloading) {
      _stopListening();
      _set(UpdatePhase.idle);
    }
  }

  /// "Later" on an offer.
  void dismiss() {
    if (_phase == UpdatePhase.offerFlexible ||
        _phase == UpdatePhase.offerStore) {
      _set(UpdatePhase.idle);
    }
  }

  /// "Restart to update": Play installs the download and restarts the app.
  Future<void> restartToInstall() async {
    try {
      await _platform.completeFlexible();
    } catch (_) {
      // Leave "Restart to update" up so the user can try again.
    }
  }

  /// "Update now" on the required-update page.
  Future<void> retryImmediate() => _runImmediate();

  /// Opens the app's store page; false when nothing could be opened.
  Future<bool> openStore() async {
    try {
      return await _platform.openStorePage();
    } catch (_) {
      return false;
    }
  }

  Future<void> _runImmediate() async {
    if (_immediateRunning) return;
    _immediateRunning = true;
    try {
      final result = await _safe(_platform.startImmediate);
      if (_disposed) return;
      switch (result) {
        case UpdateFlowResult.accepted:
          _set(UpdatePhase.idle); // Play restarts the app when it is done.
        case UpdateFlowResult.cancelled:
          _immediateFailed = false;
          _set(UpdatePhase.required);
        case UpdateFlowResult.failed:
          _immediateFailed = true;
          _set(UpdatePhase.required);
      }
    } finally {
      _immediateRunning = false;
    }
  }

  Future<UpdateFlowResult> _safe(
    Future<UpdateFlowResult> Function() flow,
  ) async {
    try {
      return await flow();
    } catch (_) {
      return UpdateFlowResult.failed;
    }
  }

  void _listen() {
    _progressSub ??= _platform.progress.listen(
      _onProgress,
      onError: (Object _) {
        _stopListening();
        if (_phase == UpdatePhase.downloading) _set(UpdatePhase.idle);
      },
    );
  }

  void _stopListening() {
    _progressSub?.cancel();
    _progressSub = null;
  }

  void _onProgress(DownloadProgress p) {
    switch (p.state) {
      case InstallState.pending || InstallState.downloading:
        _progress = p.fraction;
        _set(UpdatePhase.downloading);
      case InstallState.downloaded:
        _progress = 1;
        _set(UpdatePhase.readyToInstall);
      case InstallState.failed ||
          InstallState.canceled ||
          InstallState.installed:
        _stopListening();
        _set(UpdatePhase.idle);
      case InstallState.installing || InstallState.unknown:
        break;
    }
  }

  void _set(UpdatePhase next) {
    if (_disposed) return;
    _phase = next;
    notifyListeners();
  }

  static DateTime? _time(SharedPreferences prefs, String key) {
    final ms = prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _stopListening();
    super.dispose();
  }
}
