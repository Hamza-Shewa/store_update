import 'dart:async';

import 'package:store_update/store_update.dart';

/// The store answers the example can simulate.
enum DemoScenario {
  optional('Google Play: optional update'),
  required('Google Play: required update'),
  appStore('App Store: newer version');

  const DemoScenario(this.title);

  final String title;
}

/// A pretend store, so the update UI can be tried without publishing builds.
/// An optional update "downloads" over a few seconds.
class DemoStore extends StoreUpdatePlatform {
  DemoStore(this.scenario);

  final DemoScenario scenario;
  final _progress = StreamController<DownloadProgress>.broadcast();
  Timer? _timer;
  bool _closedOnce = false;

  @override
  bool get checkUsesNetwork => false;

  @override
  Future<StoreCheck?> check({String appStoreCountry = 'us'}) async =>
      switch (scenario) {
        DemoScenario.optional => const PlayCheck(
          PlayUpdateInfo(
            available: true,
            versionCode: 2,
            immediateAllowed: true,
            flexibleAllowed: true,
          ),
        ),
        DemoScenario.required => const PlayCheck(
          PlayUpdateInfo(
            available: true,
            versionCode: 2,
            priority: 5,
            immediateAllowed: true,
            flexibleAllowed: true,
          ),
        ),
        DemoScenario.appStore => const AppStoreCheck(
          storeVersion: '2.0.0',
          currentVersion: '1.0.0',
        ),
      };

  /// The first time, acts as if the user closed Play's update screen; then
  /// "installs".
  @override
  Future<UpdateFlowResult> startImmediate() async {
    if (_closedOnce) return UpdateFlowResult.accepted;
    _closedOnce = true;
    return UpdateFlowResult.cancelled;
  }

  @override
  Future<UpdateFlowResult> startFlexible() async {
    const total = 20 * 1024 * 1024; // 1 MiB a step
    var bytes = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      bytes += total ~/ 20;
      if (bytes >= total) {
        t.cancel();
        _progress.add(
          const DownloadProgress(
            InstallState.downloaded,
            bytes: total,
            total: total,
          ),
        );
      } else {
        _progress.add(
          DownloadProgress(
            InstallState.downloading,
            bytes: bytes,
            total: total,
          ),
        );
      }
    });
    return UpdateFlowResult.accepted;
  }

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  @override
  Future<void> completeFlexible() async =>
      _progress.add(const DownloadProgress(InstallState.installed));

  @override
  Future<bool> openStorePage() async => true;

  void dispose() {
    _timer?.cancel();
    _progress.close();
  }
}
