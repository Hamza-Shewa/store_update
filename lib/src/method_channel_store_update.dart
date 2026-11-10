import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'models.dart';
import 'platform_interface.dart';
import 'policy.dart' show iosVersionFrom;

/// [StoreUpdatePlatform] for Android (Google Play In-App Updates, native) and
/// iOS (Apple's public lookup in Dart, the App Store page natively). Other
/// platforms never report an update.
///
/// The iOS lookup sends only the bundle id and storefront to Apple.
class MethodChannelStoreUpdate extends StoreUpdatePlatform {
  MethodChannelStoreUpdate({
    http.Client? client,
    Future<PackageInfo> Function()? packageInfo,
    String? Function()? deviceOs,
    TargetPlatform Function()? platform,
  }) : _client = client,
       _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       _deviceOs =
           deviceOs ?? (() => iosVersionFrom(Platform.operatingSystemVersion)),
       _platform = platform ?? (() => defaultTargetPlatform);

  @visibleForTesting
  static const channelName = 'store_update';

  @visibleForTesting
  static const progressChannelName = 'store_update/progress';

  @visibleForTesting
  final methodChannel = const MethodChannel(channelName);

  @visibleForTesting
  final progressChannel = const EventChannel(progressChannelName);

  static const _timeout = Duration(seconds: 10);

  final http.Client? _client;
  final Future<PackageInfo> Function() _packageInfo;
  final String? Function() _deviceOs;
  final TargetPlatform Function() _platform;

  int? _trackId;
  String? _trackUrl;

  bool get _android => !kIsWeb && _platform() == TargetPlatform.android;
  bool get _ios => !kIsWeb && _platform() == TargetPlatform.iOS;

  @override
  bool get checkUsesNetwork => _ios;

  @override
  Future<StoreCheck?> check({String appStoreCountry = 'us'}) async {
    if (_android) return _checkPlay();
    if (_ios) return _checkAppStore(appStoreCountry);
    return null;
  }

  Future<StoreCheck?> _checkPlay() async {
    try {
      final m = await methodChannel.invokeMapMethod<String, Object?>('check');
      if (m == null) return null;
      return PlayCheck(
        PlayUpdateInfo(
          available: m['availability'] == 'available',
          inProgress: m['availability'] == 'in_progress',
          versionCode: (m['versionCode'] as num?)?.toInt(),
          priority: (m['priority'] as num?)?.toInt() ?? 0,
          stalenessDays: (m['stalenessDays'] as num?)?.toInt(),
          immediateAllowed: m['immediateAllowed'] == true,
          flexibleAllowed: m['flexibleAllowed'] == true,
          installState: InstallState.parse(m['installStatus']),
        ),
      );
    } on PlatformException {
      return null; // e.g. not installed from Play, no Play Store
    } on MissingPluginException {
      return null;
    }
  }

  Future<StoreCheck?> _checkAppStore(String country) async {
    final client = _client ?? http.Client();
    try {
      final info = await _packageInfo();
      final uri = Uri.https('itunes.apple.com', '/lookup', {
        'bundleId': info.packageName,
        'country': country,
      });
      final res = await client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final results = body is Map ? body['results'] : null;
      if (results is! List || results.isEmpty) return null; // not listed
      final app = results.first;
      if (app is! Map || app['version'] is! String) return null;
      _trackId = (app['trackId'] as num?)?.toInt();
      _trackUrl = app['trackViewUrl'] as String?;
      return AppStoreCheck(
        storeVersion: app['version'] as String,
        currentVersion: info.version,
        minimumOs: app['minimumOsVersion'] as String?,
        deviceOs: _deviceOs(),
      );
    } catch (_) {
      return null; // offline, timeout, unexpected reply: say nothing
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<UpdateFlowResult> _start(String method) async {
    if (!_android) return UpdateFlowResult.failed;
    try {
      final r = await methodChannel.invokeMethod<String>(method);
      return UpdateFlowResult.values.firstWhere(
        (v) => v.name == r,
        orElse: () => UpdateFlowResult.failed,
      );
    } on PlatformException {
      return UpdateFlowResult.failed;
    } on MissingPluginException {
      return UpdateFlowResult.failed;
    }
  }

  @override
  Future<UpdateFlowResult> startImmediate() => _start('startImmediate');

  @override
  Future<UpdateFlowResult> startFlexible() => _start('startFlexible');

  @override
  Stream<DownloadProgress> get progress {
    if (!_android) return const Stream.empty();
    return progressChannel.receiveBroadcastStream().map((e) {
      final m = (e as Map).cast<Object?, Object?>();
      return DownloadProgress(
        InstallState.parse(m['status']),
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
      );
    });
  }

  @override
  Future<void> completeFlexible() async {
    if (_android) await methodChannel.invokeMethod<void>('completeFlexible');
  }

  @override
  Future<bool> openStorePage() async {
    final Map<String, Object?>? args;
    if (_android) {
      args = null;
    } else if (_ios && (_trackId != null || _trackUrl != null)) {
      args = {'trackId': _trackId, 'url': _trackUrl};
    } else {
      return false;
    }
    try {
      return await methodChannel.invokeMethod<bool>('openStore', args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
