import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import 'support/fake_store.dart';

const _iosUpdate = AppStoreCheck(
  storeVersion: '2.0.0',
  currentVersion: '1.0.0',
);

/// An App Store, whose checks go over the network.
FakeStore _appStore() => FakeStore(result: _iosUpdate, checkUsesNetwork: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int cancels;

  setUp(() {
    cancels = 0;
    SharedPreferences.setMockInitialValues({});
  });

  StoreUpdateController controller(
    FakeStore fake, {
    FutureOr<void> Function()? onUpdateCancel,
  }) {
    final c = StoreUpdateController(
      platform: fake,
      checkTimeout: const Duration(milliseconds: 50),
      onUpdateCancel: onUpdateCancel ?? () => cancels++,
    );
    addTearDown(c.dispose);
    return c;
  }

  group('controller', () {
    test(
      'Play: closing the full-screen update cancels (closes the app)',
      () async {
        // Priority 0: Play itself would only offer it, the app forces it.
        final fake = FakeStore(result: playUpdate(priority: 0))
          ..immediateResult = UpdateFlowResult.cancelled;
        final c = controller(fake);

        await c.forceUpdate();

        expect(c.phase, UpdatePhase.forced);
        expect(c.forced, isTrue);
        expect(fake.immediateStarts, 1);
        expect(fake.flexibleStarts, 0);
        expect(cancels, 1);
      },
    );

    test('Play: an accepted update leaves the app waiting', () async {
      final fake = FakeStore(result: playUpdate())
        ..immediateResult = UpdateFlowResult.accepted;
      final c = controller(fake);

      await c.forceUpdate();

      expect(fake.immediateStarts, 1);
      expect(cancels, 0);
      expect(c.phase, UpdatePhase.forced);
      expect(c.forcedFailed, isFalse);
      expect(c.forcedBusy, isFalse);
    });

    test('Play: a failed update is reported without cancelling; Update now '
        'retries, then falls back to the store page', () async {
      final fake = FakeStore(result: playUpdate())
        ..immediateResult = UpdateFlowResult.failed
        ..storeOpens = false;
      final c = controller(fake);

      await c.forceUpdate();
      expect(c.forcedFailed, isTrue);
      expect(cancels, 0);
      expect(fake.storeOpened, 0, reason: 'only a tap opens the store');

      await c.startForcedUpdate();
      expect(fake.immediateStarts, 2);
      expect(fake.storeOpened, 1);
      expect(c.forcedFailed, isTrue, reason: 'the store did not open either');

      fake.storeOpens = true;
      await c.startForcedUpdate();
      expect(fake.storeOpened, 2);
      expect(c.forcedFailed, isFalse);
      expect(c.phase, UpdatePhase.forced);
    });

    test('Play: resumes a full-screen update already in progress', () async {
      final fake = FakeStore(
        result: const PlayCheck(PlayUpdateInfo(inProgress: true)),
      );
      final c = controller(fake);

      await c.forceUpdate();

      expect(fake.immediateStarts, 1);
      expect(cancels, 1, reason: 'the fake closes it (cancelled)');
    });

    test('Play: installs a background download that already finished; a '
        'failed install is reported', () async {
      final fake = FakeStore(result: playUpdate(state: InstallState.downloaded))
        ..completeError = Exception('install failed');
      final c = controller(fake);

      await c.forceUpdate();

      expect(fake.completes, 1);
      expect(fake.immediateStarts, 0);
      expect(c.forcedFailed, isTrue);
      expect(cancels, 0);
    });

    test('Play has no update for this build: waits for the user, then opens '
        'the store page', () async {
      final fake = FakeStore(result: playUpdate(available: false));
      final c = controller(fake);

      await c.forceUpdate();
      expect(c.phase, UpdatePhase.forced);
      expect(fake.immediateStarts, 0);
      expect(fake.storeOpened, 0);

      await c.startForcedUpdate();
      expect(fake.immediateStarts, 0);
      expect(fake.storeOpened, 1);
      expect(cancels, 0);
    });

    test('iOS: no App Store lookup, so Update now opens the store at once; '
        'a store that fails to open is reported', () async {
      final fake = _appStore()
        ..hang =
            true // a lookup would never answer
        ..storeOpens = false;
      final c = controller(fake);

      await c.forceUpdate();
      expect(fake.checks, 0);
      expect(c.forcedBusy, isFalse);

      await c.startForcedUpdate();
      expect(fake.storeOpened, 1);
      expect(c.forcedFailed, isTrue);
    });

    test('a failed Play check still forces the update', () async {
      final fake = FakeStore()..checkError = Exception('offline');
      final c = controller(fake);

      await c.forceUpdate();
      expect(c.phase, UpdatePhase.forced);

      await c.startForcedUpdate();
      expect(fake.storeOpened, 1);
    });

    test('Play\'s update screen already open for a required release: forcing '
        'waits on it instead of opening a second one', () async {
      final screen = Completer<UpdateFlowResult>();
      final fake = FakeStore(result: playUpdate(priority: 5))
        ..immediateCompleter = screen;
      final c = controller(fake);

      final checking = c.check(); // opens Play's screen and waits on it
      await pumpEventQueue();
      expect(fake.immediateStarts, 1);

      final forcing = c.forceUpdate();
      await pumpEventQueue();
      screen.complete(UpdateFlowResult.cancelled);
      await Future.wait([checking, forcing]);

      expect(fake.immediateStarts, 1);
      expect(cancels, 1, reason: 'closing that screen cancels too');
      expect(c.forcedFailed, isFalse);
      expect(c.phase, UpdatePhase.forced);
    });

    test('Update now tapped while Play is still being asked runs afterwards, '
        'and the prompt is busy meanwhile', () async {
      final answer = Completer<StoreCheck?>();
      final fake = FakeStore()..checkCompleter = answer;
      final c = controller(fake);

      final forcing = c.forceUpdate();
      await pumpEventQueue();
      expect(c.forcedBusy, isTrue);

      await c.startForcedUpdate(); // remembered, not dropped
      expect(fake.storeOpened, 0);

      answer.complete(playUpdate(available: false));
      await forcing;

      expect(fake.storeOpened, 1);
      expect(c.forcedBusy, isFalse);
    });

    test('a background download already running keeps going and installs '
        'when it finishes', () async {
      final fake = FakeStore(
        result: playUpdate(state: InstallState.downloading),
      )..immediateResult = UpdateFlowResult.cancelled;
      final c = controller(fake);
      await c.check();
      expect(c.phase, UpdatePhase.downloading);

      await c.forceUpdate();
      expect(fake.immediateStarts, 0, reason: 'not over the download');
      expect(c.forcedDownloading, isTrue);
      expect(c.forcedBusy, isTrue);

      fake.progressEvents.add(
        const DownloadProgress(InstallState.downloading, bytes: 5, total: 10),
      );
      await pumpEventQueue();
      expect(c.progress, 0.5);
      expect(c.phase, UpdatePhase.forced);

      await c.startForcedUpdate(); // nothing to do while it downloads
      expect(fake.immediateStarts, 0);

      fake.progressEvents.add(const DownloadProgress(InstallState.downloaded));
      await pumpEventQueue();
      expect(fake.completes, 1);
      expect(c.forcedBusy, isFalse);
      expect(cancels, 0);
    });

    test('Play reports a download on launch: it is followed; if it fails, '
        'Update now can start Play\'s update', () async {
      final fake = FakeStore(result: playUpdate(state: InstallState.pending))
        ..immediateResult = UpdateFlowResult.accepted;
      final c = controller(fake);

      await c.forceUpdate();
      expect(fake.progressEvents.hasListener, isTrue);
      expect(c.forcedBusy, isTrue);

      fake.progressEvents.add(const DownloadProgress(InstallState.failed));
      await pumpEventQueue();
      expect(c.forcedBusy, isFalse);
      expect(fake.progressEvents.hasListener, isFalse);

      fake.result = playUpdate();
      await c.startForcedUpdate();
      expect(fake.immediateStarts, 1);
    });

    test('a check already running when forced does not undo it', () async {
      final fake = FakeStore(result: playUpdate(priority: 5))
        ..immediateResult = UpdateFlowResult.failed;
      final c = controller(fake);

      final running = c.check();
      await c.forceUpdate();
      await running;

      expect(c.phase, UpdatePhase.forced);
      expect(c.forcedFailed, isTrue);
    });

    test('once forced, resume checks and offers change nothing', () async {
      final fake = FakeStore(result: playUpdate(available: false));
      final c = controller(fake);
      await c.forceUpdate();
      final checks = fake.checks;

      await c.check();
      await c.forceUpdate();
      c.dismiss();
      await c.accept();

      expect(fake.checks, checks);
      expect(fake.flexibleStarts, 0);
      expect(c.phase, UpdatePhase.forced);
    });

    test('the required page\'s Update now follows the forced rules', () async {
      final fake = FakeStore(result: playUpdate())
        ..immediateResult = UpdateFlowResult.failed;
      final c = controller(fake);
      await c.forceUpdate();

      fake.immediateResult = UpdateFlowResult.cancelled;
      await c.retryImmediate();

      expect(fake.immediateStarts, 2);
      expect(cancels, 1);
      expect(c.phase, UpdatePhase.forced);
    });

    test('your own onUpdateCancel runs instead of closing the app, and the '
        'update stays forced', () async {
      final log = <String>[];
      final fake = FakeStore(result: playUpdate(available: false));
      final c = controller(fake, onUpdateCancel: () => log.add('logged out'));
      await c.forceUpdate();

      await c.cancelForcedUpdate();

      expect(log, ['logged out']);
      expect(c.phase, UpdatePhase.forced);
      await c.startForcedUpdate();
      expect(fake.storeOpened, 1);
    });
  });

  group('controller, second review', () {
    test('forced while Play asks about a background download, then declined: '
        'Update now works again', () async {
      final consent = Completer<UpdateFlowResult>();
      final fake = FakeStore(result: playUpdate())
        ..flexibleCompleter = consent
        ..immediateResult = UpdateFlowResult.accepted;
      final c = controller(fake);
      await c.check();
      expect(c.phase, UpdatePhase.offerFlexible);

      final accepting = c.accept(); // Play's consent dialog is open
      await pumpEventQueue();
      await c.forceUpdate();
      expect(c.forcedBusy, isTrue, reason: 'it may still become a download');

      consent.complete(UpdateFlowResult.cancelled);
      await accepting;
      expect(c.forcedBusy, isFalse);
      expect(fake.progressEvents.hasListener, isFalse);

      await c.startForcedUpdate();
      expect(fake.immediateStarts, 1);
    });

    test('a download stream that errors lets Update now work again', () async {
      final fake = FakeStore(
        result: playUpdate(state: InstallState.downloading),
      );
      final c = controller(fake);
      await c.forceUpdate();
      expect(c.forcedBusy, isTrue);

      fake.progressEvents.addError(Exception('Play went away'));
      await pumpEventQueue();

      expect(c.forcedBusy, isFalse);
      expect(c.phase, UpdatePhase.forced);
    });

    test('after dispose, the forced buttons still work', () async {
      final fake = FakeStore(result: playUpdate(available: false));
      final c = StoreUpdateController(
        platform: fake,
        checkTimeout: const Duration(milliseconds: 50),
        onUpdateCancel: () => cancels++,
      );
      await c.forceUpdate();
      c.dispose();

      await c.startForcedUpdate();
      expect(fake.storeOpened, 1);
      await c.cancelForcedUpdate();
      expect(cancels, 1);
    });

    test('an onUpdateCancel that throws is reported, not thrown', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final c = controller(
        FakeStore(),
        onUpdateCancel: () => throw StateError('no session'),
      );

      await c.cancelForcedUpdate();

      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.library, 'store_update');
    });

    test('listeners see the forced state complete when told', () async {
      final fake = FakeStore(
        result: playUpdate(state: InstallState.downloading),
      );
      final c = controller(fake);
      await c.check();
      final seen = <String>[];
      c.addListener(
        () => seen.add('${c.phase.name} ${c.forced} ${c.forcedDownloading}'),
      );

      await c.forceUpdate();

      expect(seen.first, 'forced true true');
    });

    test('exitApp: Android finishes the activity, then ends the process; iOS '
        'only ends it', () async {
      for (final android in [true, false]) {
        final calls = <String>[];
        await StoreUpdateController.exitAppWith(
          android: android,
          finishActivity: () async => calls.add('finish'),
          endProcess: (code) => calls.add('exit $code'),
        );
        expect(calls, android ? ['finish', 'exit 0'] : ['exit 0']);
      }
    });
  });

  group('gate', () {
    final forced = find.byKey(StoreUpdateGate.forcedKey);

    Widget app({
      required StoreUpdateController controller,
      bool forceUpdate = true,
      bool enabled = true,
      bool inBuilder = false,
      String lang = 'en',
      ForcedPromptBuilder? forcedPromptBuilder,
      GlobalKey<NavigatorState>? navigatorKey,
    }) {
      Widget gate(Widget child) => StoreUpdateGate(
        controller: controller,
        appName: 'Hawiya',
        enabled: enabled,
        forceUpdate: forceUpdate,
        forcedPromptBuilder: forcedPromptBuilder,
        child: child,
      );
      const home = Scaffold(body: Center(child: Text('home')));
      return MaterialApp(
        navigatorKey: navigatorKey,
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // In the builder, without navigatorKey, as a first setup often is.
        builder: inBuilder ? (context, child) => gate(child!) : null,
        home: inBuilder ? home : gate(home),
      );
    }

    Future<void> show(WidgetTester tester, Widget widget) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
    }

    /// A page the app pushes, with a button that counts taps.
    Route<void> page(String name, VoidCallback onTap) => MaterialPageRoute(
      builder: (_) => Scaffold(
        body: Center(
          child: TextButton(onPressed: onTap, child: Text(name)),
        ),
      ),
    );

    for (final inBuilder in [false, true]) {
      final where = inBuilder ? 'in MaterialApp.builder' : 'around a screen';

      testWidgets('$where: shows the prompt, and no navigation removes or '
          'covers it', (tester) async {
        final key = GlobalKey<NavigatorState>();
        final c = controller(_appStore());
        await show(
          tester,
          app(controller: c, inBuilder: inBuilder, navigatorKey: key),
        );
        expect(forced, findsOneWidget);
        expect(find.text('Update Hawiya to continue'), findsOneWidget);

        var taps = 0;
        unawaited(
          key.currentState!.pushReplacement(page('next', () => taps++)),
        );
        await tester.pumpAndSettle();
        unawaited(key.currentState!.push(page('deep link', () => taps++)));
        await tester.pumpAndSettle();

        expect(find.text('deep link'), findsOneWidget);
        expect(forced, findsOneWidget);
        await tester.tap(find.text('deep link'), warnIfMissed: false);
        expect(taps, 0, reason: 'the barrier blocks the app');

        await tester.tap(find.text('Exit'));
        expect(cancels, 1);
      });
    }

    testWidgets('back and a tap outside do not close it; buttons are touch '
        'sized', (tester) async {
      final c = controller(_appStore());
      await show(tester, app(controller: c));

      for (final button in [
        find.widgetWithText(FilledButton, 'Update now'),
        find.widgetWithText(TextButton, 'Exit'),
      ]) {
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(forced, findsOneWidget);
      expect(cancels, 0);
    });

    testWidgets('Exit cancels; Update now opens the store; a store that fails '
        'to open says so', (tester) async {
      final fake = _appStore()..storeOpens = false;
      final c = controller(fake);
      await show(tester, app(controller: c));
      expect(find.textContaining("couldn't open"), findsNothing);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(fake.storeOpened, 1);
      expect(
        find.text(
          "The update couldn't open. Check your connection and try again.",
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      expect(cancels, 1);
      expect(forced, findsOneWidget);
    });

    testWidgets('busy while Play is asked: a spinner instead of Update now', (
      tester,
    ) async {
      final answer = Completer<StoreCheck?>();
      final fake = FakeStore()..checkCompleter = answer;
      final c = controller(fake);
      await tester.pumpWidget(app(controller: c));
      await tester.pump(); // the post-frame force
      await tester.pump();

      final update = find.byType(FilledButton);
      expect(tester.widget<FilledButton>(update).onPressed, isNull);
      expect(
        find.descendant(of: update, matching: find.text('Update now')),
        findsOneWidget,
        reason: 'the spinner has text beside it',
      );
      expect(
        find.descendant(
          of: update,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      answer.complete(playUpdate(available: false));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(update).onPressed, isNotNull);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('nothing while the flag is false; turning it on forces, even '
        'with the gate disabled', (tester) async {
      final c = controller(_appStore());
      await show(
        tester,
        app(controller: c, forceUpdate: false, enabled: false),
      );
      expect(forced, findsNothing);
      expect(c.forced, isFalse);

      await show(tester, app(controller: c, enabled: false));
      expect(c.forced, isTrue);
      expect(forced, findsOneWidget);
    });

    testWidgets('replaces the required-update page', (tester) async {
      final fake = FakeStore(result: playUpdate(priority: 5))
        ..immediateResult = UpdateFlowResult.cancelled;
      final c = controller(fake);
      await show(tester, app(controller: c, forceUpdate: false));
      expect(find.byKey(StoreUpdateGate.requiredKey), findsOneWidget);

      fake.immediateResult = UpdateFlowResult.failed;
      await show(tester, app(controller: c));
      expect(find.byKey(StoreUpdateGate.requiredKey), findsNothing);
      expect(forced, findsOneWidget);
      expect(cancels, 0);
    });

    testWidgets('a new controller takes the forced update over, even with '
        'the flag now false', (tester) async {
      final first = controller(_appStore());
      await show(tester, app(controller: first));
      expect(forced, findsOneWidget);

      var secondCancels = 0;
      final second = controller(
        _appStore(),
        onUpdateCancel: () => secondCancels++,
      );
      await show(tester, app(controller: second, forceUpdate: false));
      expect(second.forced, isTrue);
      expect(forced, findsOneWidget);

      await tester.tap(find.text('Exit'));
      expect(secondCancels, 1);
      expect(cancels, 0, reason: 'not the old controller');
    });

    testWidgets('Arabic, right to left', (tester) async {
      final c = controller(_appStore());
      await show(tester, app(controller: c, lang: 'ar'));

      expect(find.text('حدّث الآن'), findsOneWidget);
      expect(find.text('خروج'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('خروج'))),
        TextDirection.rtl,
      );
      // The badge sits at the start edge, which is the right in Arabic.
      final dialog = tester.getRect(find.byType(Dialog));
      final badge = tester.getRect(find.byType(UpdateBadge));
      expect(dialog.right - badge.right, lessThan(badge.left - dialog.left));
    });

    testWidgets('screen readers hear the prompt by name and not the app '
        'beneath', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = controller(_appStore());
      await show(tester, app(controller: c));

      expect(
        find.semantics.byPredicate(
          (node) =>
              node.label == 'Update Hawiya to continue' &&
              node.getSemanticsData().flagsCollection.namesRoute &&
              node.getSemanticsData().flagsCollection.scopesRoute,
        ),
        findsOne,
      );
      expect(find.semantics.byLabel('home'), findsNothing);
      semantics.dispose();
    });

    testWidgets('your own prompt gets the model; Exit can run your own logic', (
      tester,
    ) async {
      final c = controller(_appStore()..storeOpens = false);
      ForcedUpdatePrompt? seen;
      var signedOut = 0;
      await show(
        tester,
        app(
          controller: c,
          forcedPromptBuilder: (context, prompt) {
            seen = prompt;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: prompt.onUpdate,
                    child: Text(prompt.labels.updateNow),
                  ),
                  TextButton(
                    onPressed: () => signedOut++, // instead of onUpdateCancel
                    child: const Text('Sign out'),
                  ),
                  if (prompt.failed) const Text('try later'),
                ],
              ),
            );
          },
        ),
      );

      expect(find.byType(ForcedUpdateDialog), findsNothing);
      expect(seen!.labels.exit, 'Exit');
      await tester.tap(find.text('Sign out'));
      expect(signedOut, 1);
      expect(cancels, 0);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.text('try later'), findsOneWidget);
      expect(seen!.failed, isTrue);
    });

    testWidgets('the built-in prompt takes your icon, content and button '
        'styles', (tester) async {
      final c = controller(_appStore());
      await show(
        tester,
        app(
          controller: c,
          forcedPromptBuilder: (context, prompt) => ForcedUpdateDialog(
            prompt: prompt,
            icon: const Icon(Icons.lock_clock),
            content: const Text('Fixes a security issue.'),
            exitButtonStyle: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ),
      );

      expect(find.byIcon(Icons.lock_clock), findsOneWidget);
      expect(find.byType(UpdateBadge), findsNothing);
      expect(find.text('Fixes a security issue.'), findsOneWidget);
      final exit = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Exit'),
      );
      expect(exit.style!.foregroundColor!.resolve(<WidgetState>{}), Colors.red);
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Exit')).height,
        greaterThanOrEqualTo(48),
        reason: 'your style is merged over the built-in touch size',
      );
    });

    group('second review', () {
      for (final inBuilder in [false, true]) {
        final where = inBuilder ? 'in MaterialApp.builder' : 'around a screen';

        testWidgets('$where: a keyboard cannot reach the app beneath', (
          tester,
        ) async {
          final appButton = FocusNode();
          addTearDown(appButton.dispose);
          var taps = 0;
          final fake = _appStore();
          final c = controller(fake);
          Widget build(bool force) {
            Widget gate(Widget child) => StoreUpdateGate(
              controller: c,
              appName: 'Hawiya',
              forceUpdate: force,
              child: child,
            );
            final home = Scaffold(
              body: Center(
                child: TextButton(
                  focusNode: appButton,
                  onPressed: () => taps++,
                  child: const Text('pay'),
                ),
              ),
            );
            return MaterialApp(
              builder: inBuilder ? (context, child) => gate(child!) : null,
              home: inBuilder ? home : gate(home),
            );
          }

          await show(tester, build(false));
          appButton.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(taps, 1, reason: 'the keyboard works before forcing');

          await show(tester, build(true));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(taps, 1);
          expect(fake.storeOpened, 1, reason: 'focus is on Update now');

          appButton.requestFocus(); // the app tries to take it back
          await tester.pump();
          expect(appButton.hasFocus, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(taps, 1);
        });
      }

      testWidgets('shows again when the app replaces its root navigator', (
        tester,
      ) async {
        final c = controller(_appStore());
        Widget appWith(Key key) => MaterialApp(
          key: key,
          home: StoreUpdateGate(
            controller: c,
            appName: 'Hawiya',
            forceUpdate: true,
            child: const Scaffold(body: Text('home')),
          ),
        );
        await show(tester, appWith(const ValueKey('login')));
        expect(forced, findsOneWidget);

        await show(tester, appWith(const ValueKey('main')));
        expect(forced, findsOneWidget);
        await tester.tap(find.text('Exit'));
        expect(cancels, 1);
      });

      testWidgets('one prompt when two gates share a controller', (
        tester,
      ) async {
        final c = controller(_appStore());
        Widget gate(Widget child) => StoreUpdateGate(
          controller: c,
          appName: 'Hawiya',
          forceUpdate: true,
          child: child,
        );
        await show(
          tester,
          MaterialApp(
            builder: (context, child) => gate(child!),
            home: gate(const Scaffold(body: Text('home'))),
          ),
        );
        expect(forced, findsOneWidget);
      });

      testWidgets('in MaterialApp.builder, a custom prompt can use tooltips '
          'and text fields', (tester) async {
        final c = controller(_appStore());
        await show(
          tester,
          app(
            controller: c,
            inBuilder: true,
            forcedPromptBuilder: (context, prompt) => Center(
              child: Material(
                child: Tooltip(
                  message: 'why',
                  child: SizedBox(
                    width: 200,
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: prompt.labels.exit,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField), 'feedback');
        expect(find.text('feedback'), findsOneWidget);
      });

      testWidgets('the prompt follows the gate when the gate is rebuilt', (
        tester,
      ) async {
        final c = controller(_appStore());
        Widget build(String exit) => MaterialApp(
          home: StoreUpdateGate(
            controller: c,
            labels: (context) =>
                StoreUpdateLabels.en(appName: 'Hawiya').copyWith(exit: exit),
            forceUpdate: true,
            child: const Scaffold(body: Text('home')),
          ),
        );
        await show(tester, build('Leave'));
        expect(find.text('Leave'), findsOneWidget);

        await show(tester, build('Quit'));
        expect(find.text('Quit'), findsOneWidget);
        expect(find.text('Leave'), findsNothing);
      });

      testWidgets('a running download shows its progress on the button', (
        tester,
      ) async {
        final fake = FakeStore(
          result: playUpdate(state: InstallState.downloading),
        );
        final c = controller(fake);
        // The spinner never settles, so pump frames instead.
        await tester.pumpWidget(app(controller: c));
        await tester.pump();
        await tester.pump();

        fake.progressEvents.add(
          const DownloadProgress(InstallState.downloading, bytes: 1, total: 2),
        );
        await tester.pump();
        expect(find.text('Downloading the update 50%'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      });

      testWidgets('dialog colour, shape, width and the barrier colour can '
          'change', (tester) async {
        final c = controller(_appStore());
        const shape = RoundedRectangleBorder();
        await show(
          tester,
          MaterialApp(
            home: StoreUpdateGate(
              controller: c,
              appName: 'Hawiya',
              forceUpdate: true,
              forcedBarrierColor: Colors.indigo,
              forcedPromptBuilder: (context, prompt) => ForcedUpdateDialog(
                prompt: prompt,
                backgroundColor: Colors.amber,
                shape: shape,
                maxWidth: 300,
              ),
              child: const Scaffold(body: Text('home')),
            ),
          ),
        );

        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(dialog.backgroundColor, Colors.amber);
        expect(dialog.shape, shape);
        final card = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Material),
        );
        expect(tester.getSize(card.first).width, lessThanOrEqualTo(300));
        expect(
          tester
              .widget<ModalBarrier>(
                find.descendant(
                  of: forced,
                  matching: find.byType(ModalBarrier),
                ),
              )
              .color,
          Colors.indigo,
        );
      });
    });
  });
}
