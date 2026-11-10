import 'package:flutter_test/flutter_test.dart';
import 'package:store_update/store_update.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);
  const policy = UpdatePolicy();

  PlayUpdateInfo update({
    int priority = 0,
    bool immediate = true,
    bool flexible = true,
    InstallState state = InstallState.unknown,
    bool inProgress = false,
    bool available = true,
  }) => PlayUpdateInfo(
    available: available,
    inProgress: inProgress,
    versionCode: 11,
    priority: priority,
    stalenessDays: 3,
    immediateAllowed: immediate,
    flexibleAllowed: flexible,
    installState: state,
  );

  group('Android', () {
    test('no newer release: nothing to show', () {
      expect(
        policy.decideAndroid(update(available: false), now: now),
        isA<NoUpdate>(),
      );
    });

    test(
      'an ordinary release (priority 0-3) is offered as a background download',
      () {
        for (final p in [0, 1, 2, 3]) {
          final d = policy.decideAndroid(update(priority: p), now: now);
          expect(d, isA<OfferFlexible>(), reason: 'priority $p');
          expect((d as OfferFlexible).required, isFalse, reason: 'priority $p');
        }
      },
    );

    test('an optional offer waits a day after the last offer', () {
      final prompted = now.subtract(const Duration(hours: 23, minutes: 59));
      expect(
        policy.decideAndroid(update(), lastPrompt: prompted, now: now),
        isA<NoUpdate>(),
      );
      final dayOld = now.subtract(const Duration(hours: 24));
      expect(
        policy.decideAndroid(update(), lastPrompt: dayOld, now: now),
        isA<OfferFlexible>(),
      );
    });

    test('a clock moved backwards does not hide the offer forever', () {
      final future = now.add(const Duration(days: 3));
      expect(
        policy.decideAndroid(update(), lastPrompt: future, now: now),
        isA<OfferFlexible>(),
      );
    });

    test(
      'priority 4 and 5 start the full-screen update, even right after an offer',
      () {
        for (final p in [4, 5]) {
          expect(
            policy.decideAndroid(
              update(priority: p),
              lastPrompt: now,
              now: now,
            ),
            isA<StartImmediate>(),
            reason: 'priority $p',
          );
        }
      },
    );

    test(
      'a required release Play only allows as flexible has no "Later" and no daily limit',
      () {
        final d = policy.decideAndroid(
          update(priority: 5, immediate: false),
          lastPrompt: now,
          now: now,
        );
        expect(d, isA<OfferFlexible>());
        expect((d as OfferFlexible).required, isTrue);
      },
    );

    test('a release Play allows in neither flow is not offered', () {
      expect(
        policy.decideAndroid(
          update(priority: 5, immediate: false, flexible: false),
          now: now,
        ),
        isA<NoUpdate>(),
      );
      expect(
        policy.decideAndroid(update(flexible: false), now: now),
        isA<NoUpdate>(),
      );
    });

    test('a finished background download offers the restart at any time', () {
      expect(
        policy.decideAndroid(
          update(state: InstallState.downloaded),
          lastPrompt: now,
          now: now,
        ),
        isA<ShowReadyToInstall>(),
      );
    });

    test('a running background download shows its progress', () {
      expect(
        policy.decideAndroid(
          update(state: InstallState.downloading),
          lastPrompt: now,
          now: now,
        ),
        isA<ShowDownloading>(),
      );
      expect(
        policy.decideAndroid(update(state: InstallState.pending), now: now),
        isA<ShowDownloading>(),
      );
    });

    test(
      'an immediate update the user left is resumed, even when Play says immediate is not allowed',
      () {
        expect(
          policy.decideAndroid(
            update(available: false, inProgress: true, immediate: false),
            lastPrompt: now,
            now: now,
          ),
          isA<ResumeImmediate>(),
        );
      },
    );

    test(
      'install state names from the native side parse; unknown names fall back',
      () {
        expect(InstallState.parse('downloaded'), InstallState.downloaded);
        expect(InstallState.parse('canceled'), InstallState.canceled);
        expect(InstallState.parse('something-new'), InstallState.unknown);
        expect(InstallState.parse(null), InstallState.unknown);
      },
    );
  });

  group('custom policy', () {
    test('a lower required priority makes priority 2 required', () {
      const strict = UpdatePolicy(requiredPriority: 2);
      expect(
        strict.decideAndroid(update(priority: 2), now: now),
        isA<StartImmediate>(),
      );
      expect(
        strict.decideAndroid(update(priority: 1), now: now),
        isA<OfferFlexible>(),
      );
    });

    test('required priority 6 never requires an update', () {
      const never = UpdatePolicy(requiredPriority: 6);
      final d = never.decideAndroid(update(priority: 5), now: now);
      expect(d, isA<OfferFlexible>());
      expect((d as OfferFlexible).required, isFalse);
    });

    test('a shorter prompt gap offers again sooner', () {
      const often = UpdatePolicy(promptGap: Duration(hours: 1));
      final earlier = now.subtract(const Duration(hours: 1));
      expect(
        often.decideAndroid(update(), lastPrompt: earlier, now: now),
        isA<OfferFlexible>(),
      );
      expect(
        policy.decideAndroid(update(), lastPrompt: earlier, now: now),
        isA<NoUpdate>(),
      );
    });
  });

  group('iOS', () {
    test('a newer App Store version is offered', () {
      final d = decideIos(storeVersion: '1.1.0', currentVersion: '1.0.0');
      expect((d as OfferStoreVersion).version, '1.1.0');
    });

    test('the same or an older App Store version is not offered', () {
      expect(
        decideIos(storeVersion: '1.0.0', currentVersion: '1.0.0'),
        isA<NoUpdate>(),
      );
      expect(
        decideIos(storeVersion: '0.9.5', currentVersion: '1.0.0'),
        isA<NoUpdate>(),
      );
    });

    test(
      'a version this iOS cannot run is not offered; an unknown iOS does not block',
      () {
        expect(
          decideIos(
            storeVersion: '2.0.0',
            currentVersion: '1.0.0',
            minimumOs: '17.0',
            deviceOs: '16.7.2',
          ),
          isA<NoUpdate>(),
        );
        expect(
          decideIos(
            storeVersion: '2.0.0',
            currentVersion: '1.0.0',
            minimumOs: '15.0',
            deviceOs: '16.7.2',
          ),
          isA<OfferStoreVersion>(),
        );
        expect(
          decideIos(
            storeVersion: '2.0.0',
            currentVersion: '1.0.0',
            minimumOs: '17.0',
          ),
          isA<OfferStoreVersion>(),
        );
      },
    );

    test('reads the iOS version from Platform.operatingSystemVersion', () {
      expect(iosVersionFrom('Version 17.4.1 (Build 21E236)'), '17.4.1');
      expect(iosVersionFrom('Version 18.0 (Build 22A3354)'), '18.0');
      expect(iosVersionFrom('unknown'), isNull);
    });
  });

  group('isNewerVersion', () {
    test('compares each part as a number', () {
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('1.9.0', '1.10.0'), isFalse);
      expect(isNewerVersion('2.0', '1.99.99'), isTrue);
    });

    test('missing parts count as zero', () {
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.1', '1.0'), isTrue);
    });

    test('ignores a build or pre-release suffix', () {
      expect(isNewerVersion('1.0.0+12', '1.0.0+10'), isFalse);
      expect(isNewerVersion('1.0.1-beta', '1.0.0'), isTrue);
    });

    test('anything unparseable is never newer', () {
      expect(isNewerVersion('', '1.0.0'), isFalse);
      expect(isNewerVersion('abc', '1.0.0'), isFalse);
      expect(isNewerVersion('1.1.0', 'x'), isFalse);
    });
  });

  test('download progress as a fraction; an unknown size is null', () {
    expect(
      const DownloadProgress(
        InstallState.downloading,
        bytes: 25,
        total: 100,
      ).fraction,
      0.25,
    );
    expect(
      const DownloadProgress(InstallState.downloading, bytes: 25).fraction,
      isNull,
    );
    expect(
      const DownloadProgress(
        InstallState.downloading,
        bytes: 120,
        total: 100,
      ).fraction,
      1.0,
    );
  });
}
