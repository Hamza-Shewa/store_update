import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_store_update.dart';
import 'models.dart';

/// The store side of in-app updates. Replace [instance] with a subclass to
/// fake the store in tests.
abstract class StoreUpdatePlatform extends PlatformInterface {
  StoreUpdatePlatform() : super(token: _token);

  static final Object _token = Object();
  static StoreUpdatePlatform _instance = MethodChannelStoreUpdate();

  /// The store used by default: Google Play on Android, the App Store on iOS,
  /// none elsewhere.
  static StoreUpdatePlatform get instance => _instance;

  static set instance(StoreUpdatePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether [check] goes over the network. Such checks run at most once per
  /// `UpdatePolicy.promptGap`.
  bool get checkUsesNetwork;

  /// What the store says about a newer release; null when it can't tell (no
  /// store, offline, a build not installed from the store).
  /// [appStoreCountry] is the App Store storefront to look in (iOS).
  Future<StoreCheck?> check({String appStoreCountry = 'us'});

  /// Google Play's full-screen update. It ends only if the user leaves it or
  /// it fails; on success Play restarts the app.
  Future<UpdateFlowResult> startImmediate();

  /// Asks the user to download the update in the background.
  Future<UpdateFlowResult> startFlexible();

  /// Download steps of a background update.
  Stream<DownloadProgress> get progress;

  /// Installs a downloaded background update; the app restarts.
  Future<void> completeFlexible();

  /// Shows the app in its store. False when nothing could be opened.
  Future<bool> openStorePage();
}
