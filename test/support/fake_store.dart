import 'dart:async';

import 'package:store_update/store_update.dart';

/// Stands in for Google Play or the App Store in tests.
class FakeStore extends StoreUpdatePlatform {
  FakeStore({this.result, this.checkUsesNetwork = false});

  /// What [check] returns; [checkError] is thrown instead when set.
  StoreCheck? result;
  Object? checkError;

  /// Never answers [check] (for the timeout path).
  bool hang = false;

  @override
  bool checkUsesNetwork;

  UpdateFlowResult immediateResult = UpdateFlowResult.cancelled;
  UpdateFlowResult flexibleResult = UpdateFlowResult.accepted;
  bool storeOpens = true;

  int checks = 0;
  String? lastCountry;
  int immediateStarts = 0;
  int flexibleStarts = 0;
  int completes = 0;
  int storeOpened = 0;

  final progressEvents = StreamController<DownloadProgress>.broadcast();

  @override
  Future<StoreCheck?> check({String appStoreCountry = 'us'}) async {
    checks++;
    lastCountry = appStoreCountry;
    if (hang) return Completer<StoreCheck?>().future;
    if (checkError != null) throw checkError!;
    return result;
  }

  @override
  Future<UpdateFlowResult> startImmediate() async {
    immediateStarts++;
    return immediateResult;
  }

  @override
  Future<UpdateFlowResult> startFlexible() async {
    flexibleStarts++;
    return flexibleResult;
  }

  @override
  Stream<DownloadProgress> get progress => progressEvents.stream;

  @override
  Future<void> completeFlexible() async => completes++;

  @override
  Future<bool> openStorePage() async {
    storeOpened++;
    return storeOpens;
  }
}

/// Google Play's answer for an available update.
PlayCheck playUpdate({
  int priority = 0,
  bool immediate = true,
  bool flexible = true,
  InstallState state = InstallState.unknown,
  bool available = true,
}) => PlayCheck(
  PlayUpdateInfo(
    available: available,
    versionCode: 11,
    priority: priority,
    immediateAllowed: immediate,
    flexibleAllowed: flexible,
    installState: state,
  ),
);
