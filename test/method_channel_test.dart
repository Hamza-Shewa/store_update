import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:store_update/src/method_channel_store_update.dart';
import 'package:store_update/store_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(MethodChannelStoreUpdate.channelName);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  MethodChannelStoreUpdate android() =>
      MethodChannelStoreUpdate(platform: () => TargetPlatform.android);

  test('is the default platform', () {
    expect(StoreUpdatePlatform.instance, isA<MethodChannelStoreUpdate>());
  });

  group('Android', () {
    test('reads what Play reports', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'check');
        return {
          'availability': 'available',
          'versionCode': 12,
          'priority': 5,
          'stalenessDays': 3,
          'immediateAllowed': true,
          'flexibleAllowed': false,
          'installStatus': 'unknown',
        };
      });
      final info = ((await android().check()) as PlayCheck).info;
      expect(info.available, isTrue);
      expect(info.inProgress, isFalse);
      expect(info.versionCode, 12);
      expect(info.priority, 5);
      expect(info.stalenessDays, 3);
      expect(info.immediateAllowed, isTrue);
      expect(info.flexibleAllowed, isFalse);
      expect(android().checkUsesNetwork, isFalse);
    });

    test('an update this app started is still in progress', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'availability': 'in_progress',
          'installStatus': 'downloading',
        },
      );
      final info = ((await android().check()) as PlayCheck).info;
      expect(info.available, isFalse);
      expect(info.inProgress, isTrue);
      expect(info.installState, InstallState.downloading);
      expect(info.priority, 0);
    });

    test('a Play error (e.g. not installed from Play) is no answer', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(
          code: 'play',
          message: 'Install Error(-10): ERROR_APP_NOT_OWNED',
        ),
      );
      expect(await android().check(), isNull);
      expect(await android().startImmediate(), UpdateFlowResult.failed);
      expect(await android().openStorePage(), isFalse);
    });

    test('no native side is no answer', () async {
      expect(await android().check(), isNull);
      expect(await android().startFlexible(), UpdateFlowResult.failed);
    });

    test('maps flow result names, and unknown ones to failed', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'startImmediate' => 'cancelled',
          'startFlexible' => 'accepted',
          _ => 'something-else',
        },
      );
      expect(await android().startImmediate(), UpdateFlowResult.cancelled);
      expect(await android().startFlexible(), UpdateFlowResult.accepted);
    });

    test('opens the store and installs a download natively', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'openStore' ? true : null;
      });
      expect(await android().openStorePage(), isTrue);
      await android().completeFlexible();
      expect(calls.map((c) => c.method), ['openStore', 'completeFlexible']);
      expect(calls.first.arguments, isNull);
    });
  });

  group('iOS', () {
    final package = PackageInfo(
      appName: 'Example',
      packageName: 'com.example.app',
      version: '1.0.0',
      buildNumber: '10',
    );

    MethodChannelStoreUpdate ios(MockClient client) => MethodChannelStoreUpdate(
      client: client,
      packageInfo: () async => package,
      deviceOs: () => '17.4',
      platform: () => TargetPlatform.iOS,
    );

    String lookup(Map<String, Object?> app) => jsonEncode({
      'resultCount': 1,
      'results': [app],
    });

    test(
      'asks Apple for this bundle id in the given storefront and reads the version',
      () async {
        late Uri asked;
        final client = MockClient((req) async {
          asked = req.url;
          return http.Response(
            lookup({
              'version': '1.2.0',
              'trackId': 6400000001,
              'trackViewUrl':
                  'https://apps.apple.com/ly/app/example/id6400000001',
              'minimumOsVersion': '15.0',
            }),
            200,
          );
        });
        final store = ios(client);
        expect(store.checkUsesNetwork, isTrue);
        final check =
            (await store.check(appStoreCountry: 'ly')) as AppStoreCheck;
        expect(asked.host, 'itunes.apple.com');
        expect(asked.path, '/lookup');
        expect(asked.queryParameters, {
          'bundleId': 'com.example.app',
          'country': 'ly',
        });
        expect(check.storeVersion, '1.2.0');
        expect(check.currentVersion, '1.0.0');
        expect(check.minimumOs, '15.0');
        expect(check.deviceOs, '17.4');
      },
    );

    test('not on the App Store yet: no answer', () async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200),
      );
      expect(await ios(client).check(), isNull);
    });

    test('offline, a server error or an odd reply: no answer', () async {
      expect(
        await ios(
          MockClient((_) async => throw http.ClientException('offline')),
        ).check(),
        isNull,
      );
      expect(
        await ios(MockClient((_) async => http.Response('oops', 503))).check(),
        isNull,
      );
      expect(
        await ios(
          MockClient((_) async => http.Response('<html>', 200)),
        ).check(),
        isNull,
      );
    });

    test(
      'opens the store page with the id and link the lookup found',
      () async {
        final store = ios(
          MockClient(
            (_) async => http.Response(
              lookup({
                'version': '1.2.0',
                'trackId': 42,
                'trackViewUrl': 'https://apps.apple.com/ly/app/id42',
              }),
              200,
            ),
          ),
        );
        Object? args;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'openStore');
          args = call.arguments;
          return true;
        });
        expect(
          await store.openStorePage(),
          isFalse,
          reason: 'nothing found yet',
        );
        await store.check();
        expect(await store.openStorePage(), isTrue);
        expect(args, {
          'trackId': 42,
          'url': 'https://apps.apple.com/ly/app/id42',
        });
      },
    );

    test('has no Play flows', () async {
      final store = ios(MockClient((_) async => http.Response('{}', 200)));
      expect(await store.startImmediate(), UpdateFlowResult.failed);
      expect(await store.startFlexible(), UpdateFlowResult.failed);
      expect(await store.progress.isEmpty, isTrue);
    });
  });

  test('other platforms never report an update', () async {
    final desktop = MethodChannelStoreUpdate(
      platform: () => TargetPlatform.windows,
    );
    expect(await desktop.check(), isNull);
    expect(await desktop.openStorePage(), isFalse);
    expect(desktop.checkUsesNetwork, isFalse);
  });
}
