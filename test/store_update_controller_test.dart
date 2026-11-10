import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import 'support/fake_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 10, 12);
  late DateTime clock;

  setUp(() {
    clock = now;
    SharedPreferences.setMockInitialValues({});
  });

  StoreUpdateController controller(
    FakeStore fake, {
    UpdatePolicy policy = const UpdatePolicy(),
  }) {
    final c = StoreUpdateController(
      platform: fake,
      policy: policy,
      appStoreCountry: 'ly',
      clock: () => clock,
      checkTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<int?> savedPrompt() async => (await SharedPreferences.getInstance())
      .getInt(StoreUpdateController.kLastPrompt);

  test('uses StoreUpdatePlatform.instance by default', () async {
    final fake = FakeStore(result: playUpdate());
    final previous = StoreUpdatePlatform.instance;
    StoreUpdatePlatform.instance = fake;
    addTearDown(() => StoreUpdatePlatform.instance = previous);
    final c = StoreUpdateController();
    addTearDown(c.dispose);
    await c.check();
    expect(fake.checks, 1);
    expect(fake.lastCountry, 'us');
    expect(c.phase, UpdatePhase.offerFlexible);
  });

  group('failures never block or offer', () {
    test('a check that throws shows nothing and records no offer', () async {
      final fake = FakeStore()..checkError = Exception('ERROR_APP_NOT_OWNED');
      final c = controller(fake);
      await c.check();
      expect(c.phase, UpdatePhase.idle);
      expect(await savedPrompt(), isNull);
    });

    test('a check that never answers times out to nothing', () async {
      final fake = FakeStore()..hang = true;
      final c = controller(fake);
      await c.check();
      expect(c.phase, UpdatePhase.idle);
      expect(fake.checks, 1);
    });

    test(
      'a failed check after a required block lets the user back in',
      () async {
        final fake = FakeStore(result: playUpdate(priority: 5));
        final c = controller(fake);
        await c.check();
        expect(c.phase, UpdatePhase.required);

        fake.checkError = Exception('offline');
        await c.check();
        expect(c.phase, UpdatePhase.idle);
      },
    );
  });

  group('flexible update', () {
    test(
      'offers it, remembers when, and does not offer again the same day',
      () async {
        final fake = FakeStore(result: playUpdate());
        final c = controller(fake);
        await c.check();
        expect(c.phase, UpdatePhase.offerFlexible);
        expect(c.offerRequired, isFalse);
        expect(await savedPrompt(), now.millisecondsSinceEpoch);

        c.dismiss();
        clock = now.add(const Duration(hours: 5));
        await c.check();
        expect(c.phase, UpdatePhase.idle);

        clock = now.add(const Duration(hours: 25));
        await c.check();
        expect(c.phase, UpdatePhase.offerFlexible);
      },
    );

    test(
      'accepting shows the download progress, then "Restart to update" installs it',
      () async {
        final fake = FakeStore(result: playUpdate());
        final c = controller(fake);
        await c.check();
        await c.accept();
        expect(fake.flexibleStarts, 1);
        expect(c.phase, UpdatePhase.downloading);
        expect(c.progress, isNull);

        fake.progressEvents.add(
          const DownloadProgress(
            InstallState.downloading,
            bytes: 42,
            total: 100,
          ),
        );
        await pumpEventQueue();
        expect(c.progress, closeTo(0.42, 1e-9));

        fake.progressEvents.add(
          const DownloadProgress(
            InstallState.downloaded,
            bytes: 100,
            total: 100,
          ),
        );
        await pumpEventQueue();
        expect(c.phase, UpdatePhase.readyToInstall);

        await c.restartToInstall();
        expect(fake.completes, 1);
      },
    );

    test("declining Play's download dialog goes back to nothing", () async {
      final fake = FakeStore(result: playUpdate())
        ..flexibleResult = UpdateFlowResult.cancelled;
      final c = controller(fake);
      await c.check();
      await c.accept();
      expect(c.phase, UpdatePhase.idle);
    });

    test('a failed download goes back to nothing', () async {
      final fake = FakeStore(result: playUpdate());
      final c = controller(fake);
      await c.check();
      await c.accept();
      fake.progressEvents.add(const DownloadProgress(InstallState.failed));
      await pumpEventQueue();
      expect(c.phase, UpdatePhase.idle);
    });

    test(
      'a download finished while the app was away offers the restart on resume',
      () async {
        final fake = FakeStore(
          result: playUpdate(state: InstallState.downloaded),
        );
        final c = controller(fake);
        c.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await pumpEventQueue();
        expect(fake.checks, 1);
        expect(c.phase, UpdatePhase.readyToInstall);
      },
    );
  });

  group('required update', () {
    test("starts Play's full-screen update without offering first", () async {
      final fake = FakeStore(result: playUpdate(priority: 4))
        ..immediateResult = UpdateFlowResult.accepted;
      final c = controller(fake);
      await c.check();
      expect(fake.immediateStarts, 1);
      expect(c.phase, UpdatePhase.idle);
      expect(await savedPrompt(), isNull);
    });

    test(
      "closing Play's screen blocks with an explanation and does not reopen it on resume",
      () async {
        final fake = FakeStore(result: playUpdate(priority: 5));
        final c = controller(fake);
        await c.check();
        expect(c.phase, UpdatePhase.required);
        expect(c.immediateFailed, isFalse);

        await c.check(); // the resume after Play's screen closed
        expect(fake.immediateStarts, 1);
        expect(c.phase, UpdatePhase.required);

        fake.immediateResult = UpdateFlowResult.accepted;
        await c.retryImmediate();
        expect(fake.immediateStarts, 2);
        expect(c.phase, UpdatePhase.idle);
      },
    );

    test(
      'a failed update is reported as failed, and the store can be opened',
      () async {
        final fake = FakeStore(result: playUpdate(priority: 5))
          ..immediateResult = UpdateFlowResult.failed;
        final c = controller(fake);
        await c.check();
        expect(c.phase, UpdatePhase.required);
        expect(c.immediateFailed, isTrue);
        expect(await c.openStore(), isTrue);
        expect(fake.storeOpened, 1);
      },
    );

    test('the policy decides what is required', () async {
      final fake = FakeStore(result: playUpdate(priority: 5));
      final c = controller(
        fake,
        policy: const UpdatePolicy(requiredPriority: 6),
      );
      await c.check();
      expect(fake.immediateStarts, 0);
      expect(c.phase, UpdatePhase.offerFlexible);
    });
  });

  group('iOS', () {
    AppStoreCheck store(String version) =>
        AppStoreCheck(storeVersion: version, currentVersion: '1.0.0');

    test(
      'offers a newer version in the chosen storefront and opens the store page on "Update"',
      () async {
        final fake = FakeStore(result: store('1.2.0'), checkUsesNetwork: true);
        final c = controller(fake);
        await c.check();
        expect(fake.lastCountry, 'ly');
        expect(c.phase, UpdatePhase.offerStore);
        expect(c.storeVersion, '1.2.0');

        await c.accept();
        expect(fake.storeOpened, 1);
        expect(c.phase, UpdatePhase.idle);
      },
    );

    test('looks the version up at most once a day', () async {
      final fake = FakeStore(result: store('1.0.0'), checkUsesNetwork: true);
      final c = controller(fake);
      await c.check();
      clock = now.add(const Duration(hours: 23));
      await c.check();
      expect(fake.checks, 1);

      clock = now.add(const Duration(hours: 24));
      await c.check();
      expect(fake.checks, 2);
    });
  });
}
