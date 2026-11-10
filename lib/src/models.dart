/// Where Google Play's install of an update stands. The native side sends
/// these names.
enum InstallState {
  unknown,
  pending,
  downloading,
  downloaded,
  installing,
  installed,
  failed,
  canceled;

  /// The state named [name]; [unknown] for anything else.
  static InstallState parse(Object? name) => InstallState.values.firstWhere(
    (s) => s.name == name,
    orElse: () => InstallState.unknown,
  );
}

/// What Google Play reports for this install.
class PlayUpdateInfo {
  const PlayUpdateInfo({
    this.available = false,
    this.inProgress = false,
    this.versionCode,
    this.priority = 0,
    this.stalenessDays,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.installState = InstallState.unknown,
  });

  /// A newer release is available to this install.
  final bool available;

  /// An update this app started is still running (Play's
  /// DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS).
  final bool inProgress;

  /// The version code of the newer release, when there is one.
  final int? versionCode;

  /// The in-app update priority (0-5) the release was published with.
  final int priority;

  /// Days since Play learned of the update; null when there is none.
  final int? stalenessDays;

  /// Whether Play allows the full-screen (IMMEDIATE) flow for this update.
  final bool immediateAllowed;

  /// Whether Play allows the background (FLEXIBLE) flow for this update.
  final bool flexibleAllowed;

  /// Where a background download of the update stands.
  final InstallState installState;
}

/// What a store check found.
sealed class StoreCheck {
  const StoreCheck();
}

/// Google Play's answer for this install.
final class PlayCheck extends StoreCheck {
  const PlayCheck(this.info);

  final PlayUpdateInfo info;
}

/// The App Store's current version, and what this device runs.
final class AppStoreCheck extends StoreCheck {
  const AppStoreCheck({
    required this.storeVersion,
    required this.currentVersion,
    this.minimumOs,
    this.deviceOs,
  });

  /// The version on the App Store.
  final String storeVersion;

  /// The installed version.
  final String currentVersion;

  /// The lowest iOS version the App Store version runs on.
  final String? minimumOs;

  /// This device's iOS version.
  final String? deviceOs;
}

/// How an update flow shown to the user ended.
enum UpdateFlowResult {
  /// The user accepted: a background download started, or Play's full-screen
  /// update is installing.
  accepted,

  /// The user closed Play's update screen or dialog.
  cancelled,

  /// The flow could not run.
  failed,
}

/// One step of a background download.
class DownloadProgress {
  const DownloadProgress(this.state, {this.bytes = 0, this.total = 0});

  final InstallState state;

  /// Bytes downloaded so far.
  final int bytes;

  /// Total bytes to download; 0 while unknown.
  final int total;

  /// 0..1, or null while the size is unknown.
  double? get fraction => total > 0 ? (bytes / total).clamp(0.0, 1.0) : null;
}
