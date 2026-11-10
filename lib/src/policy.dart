import 'models.dart';

/// What the app should do after a store check.
sealed class UpdateDecision {
  const UpdateDecision();
}

/// Nothing to show.
final class NoUpdate extends UpdateDecision {
  const NoUpdate();
}

/// Offer the background (FLEXIBLE) download. A [required] offer has no
/// "Later" and is not limited by [UpdatePolicy.promptGap].
final class OfferFlexible extends UpdateDecision {
  const OfferFlexible({required this.required});

  final bool required;
}

/// Start Play's full-screen (IMMEDIATE) update for a required release.
final class StartImmediate extends UpdateDecision {
  const StartImmediate();
}

/// Bring back an IMMEDIATE update the user left (Play asks apps to resume it).
final class ResumeImmediate extends UpdateDecision {
  const ResumeImmediate();
}

/// A background download is running: show its progress.
final class ShowDownloading extends UpdateDecision {
  const ShowDownloading();
}

/// The background download finished: offer "Restart to update".
final class ShowReadyToInstall extends UpdateDecision {
  const ShowReadyToInstall();
}

/// iOS: a newer [version] is on the App Store.
final class OfferStoreVersion extends UpdateDecision {
  const OfferStoreVersion(this.version);

  final String version;
}

/// When an update is required and how often an optional one is offered.
///
/// On Google Play a release published with an in-app update priority of
/// [requiredPriority] or more is required: Play's full-screen IMMEDIATE flow
/// runs, and if the user closes it the app waits behind an explanation. Any
/// other newer release is offered at most once per [promptGap] as a
/// background (FLEXIBLE) download.
///
/// Play's staleness days are never used to force an update, so a phone that
/// was offline for weeks is not locked out.
class UpdatePolicy {
  /// [requiredPriority] is 0-6; 6 means no release is ever required (Play's
  /// highest priority is 5).
  const UpdatePolicy({
    this.requiredPriority = 4,
    this.promptGap = const Duration(hours: 24),
  }) : assert(requiredPriority >= 0 && requiredPriority <= 6);

  /// Play's in-app update priority (0-5) at which an update is required.
  final int requiredPriority;

  /// How long "Later" on an optional update keeps the offer away.
  final Duration promptGap;

  /// Whether Play's [info] describes a required update.
  bool isRequired(PlayUpdateInfo info) => info.priority >= requiredPriority;

  /// Whether to offer again: never offered, or the last offer is at least
  /// [promptGap] old. A clock moved backwards counts as old.
  bool promptDue(DateTime? lastPrompt, DateTime now) {
    if (lastPrompt == null) return true;
    final since = now.difference(lastPrompt);
    return since.isNegative || since >= promptGap;
  }

  /// What to do with Google Play's answer [info].
  UpdateDecision decideAndroid(
    PlayUpdateInfo info, {
    DateTime? lastPrompt,
    required DateTime now,
  }) {
    switch (info.installState) {
      case InstallState.downloaded:
        return const ShowReadyToInstall();
      case InstallState.pending || InstallState.downloading:
        return const ShowDownloading();
      default:
    }
    // Play may report IMMEDIATE as not allowed while one runs; its docs
    // resume it regardless.
    if (info.inProgress) return const ResumeImmediate();
    if (!info.available) return const NoUpdate();
    if (isRequired(info)) {
      if (info.immediateAllowed) return const StartImmediate();
      if (info.flexibleAllowed) return const OfferFlexible(required: true);
      return const NoUpdate();
    }
    if (!info.flexibleAllowed || !promptDue(lastPrompt, now)) {
      return const NoUpdate();
    }
    return const OfferFlexible(required: false);
  }
}

/// iOS: offer [storeVersion] when it is newer than [currentVersion] and this
/// device's iOS ([deviceOs]) can run it ([minimumOs]). Unknown OS versions do
/// not block the offer.
UpdateDecision decideIos({
  required String storeVersion,
  required String currentVersion,
  String? minimumOs,
  String? deviceOs,
}) {
  if (!isNewerVersion(storeVersion, currentVersion)) return const NoUpdate();
  if (minimumOs != null &&
      deviceOs != null &&
      isNewerVersion(minimumOs, deviceOs)) {
    return const NoUpdate();
  }
  return OfferStoreVersion(storeVersion);
}

/// Whether dotted version [candidate] is newer than [current]: numeric per
/// part, so 1.10.0 > 1.9.0 and 1.0 == 1.0.0. A build suffix (+12, -beta) is
/// ignored. Anything unparseable is never newer.
bool isNewerVersion(String candidate, String current) {
  final a = _parse(candidate), b = _parse(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

List<int>? _parse(String version) {
  final core = version.trim().split(RegExp(r'[+\-\s]')).first;
  if (core.isEmpty) return null;
  final parts = <int>[];
  for (final p in core.split('.')) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    parts.add(n);
  }
  return parts;
}

/// The iOS version in Dart's `Platform.operatingSystemVersion`, e.g.
/// "Version 17.4.1 (Build 21E236)" gives "17.4.1"; null when there is none.
String? iosVersionFrom(String operatingSystemVersion) =>
    RegExp(r'\d+(\.\d+)+').firstMatch(operatingSystemVersion)?.group(0);
