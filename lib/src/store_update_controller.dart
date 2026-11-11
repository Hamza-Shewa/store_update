import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/services.dart';
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

  /// The app asked for an update with [StoreUpdateController.forceUpdate]:
  /// the app waits behind a prompt with "Update now" and "Exit" (which runs
  /// the controller's `onUpdateCancel`, by default closing the app).
  forced,
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
    FutureOr<void> Function()? onUpdateCancel,
  }) : _platform = platform ?? StoreUpdatePlatform.instance,
       _clock = clock ?? DateTime.now,
       _onUpdateCancel = onUpdateCancel ?? exitApp;

  /// Shared preferences key: when an optional update was last offered.
  static const kLastPrompt = 'store_update.last_prompt';

  /// Shared preferences key: when a network check (iOS) last ran.
  static const kLastCheck = 'store_update.last_check';

  final StoreUpdatePlatform _platform;
  final DateTime Function() _clock;
  final FutureOr<void> Function() _onUpdateCancel;

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

  bool _forced = false;

  /// Whether [forceUpdate] was called. It lasts until the app restarts.
  bool get forced => _forced;

  bool _forcedFailed = false;

  /// On [UpdatePhase.forced]: the last attempt to update failed.
  bool get forcedFailed => _forcedFailed;

  /// A forced pass is running: a Play check, Play's update screen, or the
  /// store page opening.
  bool _forcing = false;

  /// "Update now" was tapped while a forced pass ran: run another after it.
  bool _updateTapped = false;

  /// While forced, a background download is followed to install it.
  bool _forcedDownload = false;

  /// On [UpdatePhase.forced]: an update step is under way (Play's check or
  /// update screen, the store page opening, or a background download that
  /// installs when it finishes), so "Update now" has nothing to do yet.
  bool get forcedBusy => _forcing || _forcedDownload;

  /// On [UpdatePhase.forced]: a background download is running and installs
  /// when it finishes ([progress]).
  bool get forcedDownloading => _forcedDownload;

  /// Play's full-screen update while it is open, shared by everything that
  /// would start it, so it never opens twice.
  Future<UpdateFlowResult>? _immediateFlow;

  bool _started = false;
  bool _checking = false;
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
    if (_checking || _immediateFlow != null || _forced || _disposed) return;
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
    // A check that was running when the update was forced has no say.
    if (_disposed || _forced) return;
    switch (decision) {
      case NoUpdate():
        // While an accepted download is followed, its progress stream decides
        // (Play may still report the update as merely available right after
        // the user accepted it).
        final followingDownload =
            _phase == UpdatePhase.downloading && _progressSub != null;
        if (_phase == UpdatePhase.required ||
            _phase == UpdatePhase.readyToInstall ||
            (_phase == UpdatePhase.downloading && !followingDownload)) {
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
    if (_disposed) return;
    if (_phase == UpdatePhase.offerStore) {
      _set(UpdatePhase.idle);
      if (!await openStore()) await _forgetOffer();
      return;
    }
    if (_phase != UpdatePhase.offerFlexible) return;
    _progress = null;
    _listen();
    _set(UpdatePhase.downloading);
    final result = await _safe(_platform.startFlexible);
    if (result == UpdateFlowResult.accepted) return;
    if (_forcedDownload) {
      // Forced while Play asked about the download, then declined: there is
      // no download to wait for, so "Update now" works again.
      _forcedDownload = false;
      _stopListening();
      _setForced();
    } else if (_phase == UpdatePhase.downloading) {
      _stopListening();
      _set(UpdatePhase.idle);
    }
  }

  /// The store page could not open: offer again on the next check instead of
  /// waiting a day.
  Future<void> _forgetOffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kLastPrompt);
      await prefs.remove(kLastCheck);
    } catch (_) {
      // Then it is offered again after the usual gap.
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

  /// "Update now" on the required-update page; once forced, the same as
  /// [startForcedUpdate].
  Future<void> retryImmediate() =>
      _forced ? startForcedUpdate() : _runImmediate();

  /// Requires the user to update now, whatever the store's own priority says;
  /// for when the app's backend decides this version may no longer run.
  /// Safe to call more than once.
  ///
  /// The app waits behind [UpdatePhase.forced] from then until it restarts.
  /// On Google Play, when Play has the update for this install, Play's
  /// full-screen update starts at once, and closing it calls
  /// [cancelForcedUpdate]. A background download already running is followed
  /// and installed when it finishes. Otherwise (iOS, or a build Play doesn't
  /// know about) the prompt waits for [startForcedUpdate] or
  /// [cancelForcedUpdate].
  Future<void> forceUpdate() async {
    if (_forced || _disposed) return;
    // A download the user already accepted keeps going and installs.
    final following = _progressSub != null && _phase == UpdatePhase.downloading;
    if (!following) _stopListening();
    // Set before listeners hear of it, so they see a consistent state.
    _forced = true;
    _forcedDownload = following;
    _set(UpdatePhase.forced);
    await _forcedPass(userAsked: false);
  }

  /// "Update now" on the forced prompt: Play's full-screen update when Play
  /// can run it (closing it calls [cancelForcedUpdate]), otherwise the store
  /// page. A tap while [forcedBusy] runs once the current step ends.
  ///
  /// It keeps working after [dispose], so a forced prompt that outlives its
  /// controller still updates (the prompt itself no longer changes).
  Future<void> startForcedUpdate() async {
    if (!_forced || _forcedDownload) return;
    if (_forcing) {
      _updateTapped = true;
      return;
    }
    await _forcedPass(userAsked: true);
  }

  /// The user declined a forced update: "Exit" on the forced prompt, or
  /// closing Play's full-screen update. Runs the controller's
  /// `onUpdateCancel`, which is [exitApp] unless the app gave its own.
  /// An error it throws is reported to [FlutterError.onError], not thrown.
  Future<void> cancelForcedUpdate() async {
    try {
      await _onUpdateCancel();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'store_update',
          context: ErrorDescription('while running onUpdateCancel'),
        ),
      );
    }
  }

  /// Leaves the app, the default `onUpdateCancel`: Android finishes the
  /// activity first so it closes like back does, then the process ends with
  /// `exit(0)` on both platforms.
  static Future<void> exitApp() => exitAppWith(
    android: Platform.isAndroid,
    finishActivity: SystemNavigator.pop,
    endProcess: exit,
  );

  /// [exitApp] with its platform calls passed in, for tests.
  @visibleForTesting
  static Future<void> exitAppWith({
    required bool android,
    required Future<void> Function() finishActivity,
    required void Function(int code) endProcess,
  }) async {
    if (android) await finishActivity();
    endProcess(0);
  }

  Future<void> _forcedPass({required bool userAsked}) async {
    _forcing = true;
    _setForced();
    try {
      await _forcedStep(userAsked: userAsked);
      while (_updateTapped) {
        _updateTapped = false;
        await _forcedStep(userAsked: true);
      }
    } finally {
      _forcing = false;
      _updateTapped = false;
      _setForced();
    }
  }

  Future<void> _forcedStep({required bool userAsked}) async {
    if (_forcedDownload) return;
    // Play's update screen is already open (a required release): its answer
    // counts, rather than opening a second one.
    final open = _immediateFlow;
    if (open != null) return _afterForcedImmediate(await open, userAsked);

    // Only Play's answer is used, and it is a local call; the App Store's
    // would only delay the store page.
    PlayUpdateInfo? play;
    if (!_platform.checkUsesNetwork) {
      try {
        final result = await _platform
            .check(appStoreCountry: appStoreCountry)
            .timeout(checkTimeout);
        if (result is PlayCheck) play = result.info;
      } catch (_) {
        // As if Play knew nothing: the store page.
      }
    }
    if (play != null) {
      switch (play.installState) {
        case InstallState.downloaded:
          if (await _installDownload()) return;
          _setForcedFailed(true);
        case InstallState.pending || InstallState.downloading when !_disposed:
          _forcedDownload = true;
          _listen();
          return;
        default:
          if (play.inProgress || (play.available && play.immediateAllowed)) {
            return _afterForcedImmediate(await _immediate(), userAsked);
          }
      }
    }
    if (userAsked) await _openStoreForced();
  }

  Future<void> _afterForcedImmediate(
    UpdateFlowResult result,
    bool userAsked,
  ) async {
    switch (result) {
      case UpdateFlowResult.accepted:
        _setForcedFailed(false); // Play restarts the app when it is done.
      case UpdateFlowResult.cancelled:
        await cancelForcedUpdate();
      case UpdateFlowResult.failed:
        if (userAsked) {
          await _openStoreForced();
        } else {
          _setForcedFailed(true);
        }
    }
  }

  Future<void> _openStoreForced() async {
    final opened = await openStore();
    _setForcedFailed(!opened);
  }

  /// Installs a finished background download; Play restarts the app. False
  /// when it could not.
  Future<bool> _installDownload() async {
    try {
      await _platform.completeFlexible();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setForcedFailed(bool failed) {
    _forcedFailed = failed;
    _setForced();
  }

  /// Tells the forced prompt something changed.
  void _setForced() {
    if (_forced) _set(UpdatePhase.forced);
  }

  /// Opens the app's store page; false when nothing could be opened.
  Future<bool> openStore() async {
    try {
      return await _platform.openStorePage();
    } catch (_) {
      return false;
    }
  }

  Future<UpdateFlowResult> _immediate() => _immediateFlow ??= _safe(
    _platform.startImmediate,
  ).whenComplete(() => _immediateFlow = null);

  Future<void> _runImmediate() async {
    if (_immediateFlow != null || _disposed) return;
    final result = await _immediate();
    // Once forced, the forced pass waits on the same screen and decides.
    if (_disposed || _forced) return;
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
    if (_disposed) return;
    _progressSub ??= _platform.progress.listen(
      _onProgress,
      onError: (Object _) {
        _stopListening();
        if (_forcedDownload) {
          _forcedDownload = false;
          _setForced();
        }
        if (_phase == UpdatePhase.downloading) _set(UpdatePhase.idle);
      },
    );
  }

  void _stopListening() {
    _progressSub?.cancel();
    _progressSub = null;
  }

  void _onProgress(DownloadProgress p) {
    if (_forced) return _onForcedProgress(p);
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

  /// While forced: install the download once it finishes; let "Update now"
  /// try again if it stops.
  void _onForcedProgress(DownloadProgress p) {
    switch (p.state) {
      case InstallState.pending || InstallState.downloading:
        _progress = p.fraction;
        _setForced();
      case InstallState.downloaded:
        _progress = 1;
        _forcedDownload = false;
        _stopListening();
        _setForced();
        unawaited(
          _installDownload().then((ok) {
            if (!ok && !_disposed) _setForcedFailed(true);
          }),
        );
      case InstallState.failed ||
          InstallState.canceled ||
          InstallState.installed:
        _forcedDownload = false;
        _stopListening();
        _setForced();
      case InstallState.installing || InstallState.unknown:
        break;
    }
  }

  void _set(UpdatePhase next) {
    // Nothing leaves a forced update; it lasts until the app restarts.
    if (_disposed || (_forced && next != UpdatePhase.forced)) return;
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
