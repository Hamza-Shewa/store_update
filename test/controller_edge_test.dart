import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import 'support/fake_store.dart';

/// A store whose check answers only when [answer] completes.
class _SlowStore extends FakeStore {
  _SlowStore() : super(result: playUpdate(priority: 5));

  final answer = Completer<void>();

  @override
  Future<StoreCheck?> check({String appStoreCountry = 'us'}) async {
    await answer.future;
    return super.check(appStoreCountry: appStoreCountry);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StoreUpdateController controller(FakeStore fake) {
    final c = StoreUpdateController(
      platform: fake,
      checkTimeout: const Duration(seconds: 5),
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'a resume right after accepting does not hide the accepted download',
    () async {
      final fake = FakeStore(result: playUpdate());
      final c = controller(fake);
      await c.check();
      await c.accept();
      expect(c.phase, UpdatePhase.downloading);

      // Play's consent dialog closed: the app resumes, and Play still reports
      // the update as available (offered minutes ago, so the policy says none).
      await c.check();
      expect(c.phase, UpdatePhase.downloading);

      fake.progressEvents.add(
        const DownloadProgress(InstallState.downloaded, bytes: 1, total: 1),
      );
      await pumpEventQueue();
      expect(c.phase, UpdatePhase.readyToInstall);
    },
  );

  test('a download whose progress stream fails goes back to nothing', () async {
    final fake = FakeStore(result: playUpdate());
    final c = controller(fake);
    await c.check();
    await c.accept();
    fake.progressEvents.addError(Exception('channel closed'));
    await pumpEventQueue();
    expect(c.phase, UpdatePhase.idle);
  });

  test(
    "an immediate update the user left is resumed on the app's return",
    () async {
      final fake = FakeStore(
        result: const PlayCheck(PlayUpdateInfo(inProgress: true)),
      )..immediateResult = UpdateFlowResult.accepted;
      final c = controller(fake);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(fake.immediateStarts, 1);
    },
  );

  test(
    'a controller disposed during a check starts nothing afterwards',
    () async {
      final fake = _SlowStore();
      final c = StoreUpdateController(platform: fake);
      final checking = c.check();
      c.dispose();
      fake.answer.complete();
      await checking;
      expect(fake.immediateStarts, 0);
      expect(c.phase, UpdatePhase.idle);
    },
  );

  test('a second check while one runs is skipped', () async {
    final fake = _SlowStore();
    final c = controller(fake);
    final first = c.check();
    await c.check();
    expect(fake.checks, 0, reason: 'the second call returned without asking');
    fake.answer.complete();
    await first;
    expect(fake.checks, 1);
  });

  test(
    'iOS: when the App Store page cannot open, the offer comes back on the next check',
    () async {
      final fake = FakeStore(
        result: const AppStoreCheck(
          storeVersion: '2.0.0',
          currentVersion: '1.0.0',
        ),
        checkUsesNetwork: true,
      )..storeOpens = false;
      final c = controller(fake);
      await c.check();
      await c.accept();
      expect(c.phase, UpdatePhase.idle);

      await c.check();
      expect(fake.checks, 2, reason: 'not held back by the daily limit');
      expect(c.phase, UpdatePhase.offerStore);
    },
  );

  test('a failing completeFlexible leaves "Restart to update" up', () async {
    final fake = _ThrowingCompleteStore();
    final c = controller(fake);
    await c.check();
    expect(c.phase, UpdatePhase.readyToInstall);
    await c.restartToInstall();
    expect(c.phase, UpdatePhase.readyToInstall);
  });
}

class _ThrowingCompleteStore extends FakeStore {
  _ThrowingCompleteStore()
    : super(result: playUpdate(state: InstallState.downloaded));

  @override
  Future<void> completeFlexible() async => throw Exception('install failed');
}
