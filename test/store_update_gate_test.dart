import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import 'support/fake_store.dart';

/// Counts taps, to prove the app under the gate keeps its state.
class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('home $taps'),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<StoreUpdateController> show(
    WidgetTester tester,
    FakeStore fake, {
    String lang = 'en',
    StoreUpdateLabels Function(BuildContext)? labels,
    OfferBuilder? offerBuilder,
    OfferPresenter? offerPresenter,
    ProgressBarBuilder? progressBarBuilder,
    RequiredPageBuilder? requiredPageBuilder,
    Size screen = const Size(1080, 2400),
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final controller = StoreUpdateController(
      platform: fake,
      checkTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: StoreUpdateGate(
          controller: controller,
          appName: 'Hawiya',
          labels: labels,
          offerBuilder: offerBuilder,
          offerPresenter: offerPresenter,
          progressBarBuilder: progressBarBuilder,
          requiredPageBuilder: requiredPageBuilder,
          child: const _Home(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Lets a sheet close without waiting for an endless progress animation.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectTouchTarget(WidgetTester tester, Finder button) {
    final size = tester.getSize(button);
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  }

  testWidgets('no update: only the app, nothing on top', (tester) async {
    final fake = FakeStore();
    await show(tester, fake);
    expect(fake.checks, 1);
    expect(find.text('home 0'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(StoreUpdateGate.barKey), findsNothing);
    expect(find.byKey(StoreUpdateGate.requiredKey), findsNothing);
  });

  testWidgets('a hanging check shows nothing and leaves the app usable', (
    tester,
  ) async {
    final fake = FakeStore(result: playUpdate())..hang = true;
    await show(tester, fake);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('home 0'));
    await tester.pump();
    expect(find.text('home 1'), findsOneWidget);
  });

  testWidgets(
    'offer: Update starts the background download and shows its progress',
    (tester) async {
      final fake = FakeStore(result: playUpdate());
      await show(tester, fake);
      expect(find.text('A new version of Hawiya is ready'), findsOneWidget);
      expectTouchTarget(tester, find.widgetWithText(FilledButton, 'Update'));
      expectTouchTarget(tester, find.widgetWithText(TextButton, 'Later'));

      await tester.tap(find.text('Update'));
      await settle(tester);
      expect(fake.flexibleStarts, 1);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(StoreUpdateGate.barKey), findsOneWidget);
      expect(find.text('Downloading the update'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
        reason: 'size unknown until Play reports it',
      );

      fake.progressEvents.add(
        const DownloadProgress(InstallState.downloading, bytes: 42, total: 100),
      );
      await tester.pump();
      expect(find.text('42%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(0.42, 1e-9),
      );
    },
  );

  testWidgets(
    'Arabic offer reads right to left; Later closes it without downloading',
    (tester) async {
      final fake = FakeStore(result: playUpdate());
      final controller = await show(tester, fake, lang: 'ar');
      final title = find.text('إصدار جديد من ${_ltr('Hawiya')} جاهز');
      expect(title, findsOneWidget);
      expect(Directionality.of(tester.element(title)), TextDirection.rtl);
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(
        tester.getRect(find.byIcon(Icons.system_update)).center.dx,
        greaterThan(sheet.center.dx),
        reason: 'the badge starts on the right',
      );

      await tester.tap(find.text('لاحقاً'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(fake.flexibleStarts, 0);
      expect(controller.phase, UpdatePhase.idle);
    },
  );

  testWidgets(
    'downloaded: "Restart to update" installs it, and the app kept its state',
    (tester) async {
      final fake = FakeStore(result: playUpdate());
      await show(tester, fake);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('home 0'));
      await tester.pump();

      fake.result = playUpdate(state: InstallState.downloaded);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Update downloaded'), findsOneWidget);
      expect(
        find.text('home 1'),
        findsOneWidget,
        reason: 'the bar must not rebuild the app below it',
      );
      final restart = find.widgetWithText(FilledButton, 'Restart to update');
      expectTouchTarget(tester, restart);
      await tester.tap(restart);
      await tester.pump();
      expect(fake.completes, 1);
    },
  );

  testWidgets(
    "required: closing Play's update leaves a page back cannot leave; Update now retries",
    (tester) async {
      final fake = FakeStore(result: playUpdate(priority: 5));
      await show(tester, fake);
      expect(fake.immediateStarts, 1);
      expect(find.byKey(StoreUpdateGate.requiredKey), findsOneWidget);
      expect(find.text('Update Hawiya to continue'), findsOneWidget);
      expect(
        find.text('home 0'),
        findsNothing,
        reason: 'the app is hidden behind the page',
      );
      expect(find.textContaining("couldn't start"), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(StoreUpdateGate.requiredKey), findsOneWidget);

      final updateNow = find.widgetWithText(FilledButton, 'Update now');
      expectTouchTarget(tester, updateNow);
      expectTouchTarget(
        tester,
        find.widgetWithText(OutlinedButton, 'Open Google Play'),
      );
      fake.immediateResult = UpdateFlowResult.accepted;
      await tester.tap(updateNow);
      await tester.pumpAndSettle();
      expect(fake.immediateStarts, 2);
      expect(find.byKey(StoreUpdateGate.requiredKey), findsNothing);
      expect(find.text('home 0'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed required update says so in Arabic, and the store can be opened',
    (tester) async {
      final fake = FakeStore(result: playUpdate(priority: 4))
        ..immediateResult = UpdateFlowResult.failed;
      await show(tester, fake, lang: 'ar');
      expect(find.text('حدّث ${_ltr('Hawiya')} للمتابعة'), findsOneWidget);
      expect(find.textContaining('تعذّر بدء التحديث'), findsOneWidget);
      await tester.tap(find.text('افتح Google Play'));
      await tester.pump();
      expect(fake.storeOpened, 1);
    },
  );

  testWidgets(
    'a required update Play allows only in the background has no Later and stays open',
    (tester) async {
      final fake = FakeStore(result: playUpdate(priority: 5, immediate: false));
      await show(tester, fake);
      expect(
        find.textContaining('needed to keep Hawiya working'),
        findsOneWidget,
      );
      expect(find.text('Later'), findsNothing);
      await tester.tapAt(const Offset(20, 20)); // the barrier
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    'iOS: a newer App Store version is offered and Update opens the store page',
    (tester) async {
      final fake = FakeStore(
        result: const AppStoreCheck(
          storeVersion: '1.2.0',
          currentVersion: '1.0.0',
        ),
        checkUsesNetwork: true,
      );
      await show(tester, fake);
      expect(find.text('Hawiya 1.2.0 is available'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(fake.storeOpened, 1);
      expect(fake.flexibleStarts, 0);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('custom labels replace the built-in text', (tester) async {
    final fake = FakeStore(result: playUpdate());
    await show(
      tester,
      fake,
      labels: (context) => StoreUpdateLabels.of(
        context,
        appName: 'Hawiya',
      ).copyWith(offerTitle: 'Fresh build', update: 'Get it'),
    );
    expect(find.text('Fresh build'), findsOneWidget);
    await tester.tap(find.text('Get it'));
    await settle(tester);
    expect(fake.flexibleStarts, 1);
  });

  testWidgets('custom widgets replace the offer, the bar and the page', (
    tester,
  ) async {
    final fake = FakeStore(result: playUpdate());
    final controller = await show(
      tester,
      fake,
      offerBuilder: (context, offer) => TextButton(
        onPressed: offer.onUpdate,
        child: Text('my offer, required: ${offer.required}'),
      ),
      progressBarBuilder: (context, c, labels) =>
          Text('my bar ${c.phase.name}'),
      requiredPageBuilder: (context, c, labels) =>
          const Material(child: Text('my required page')),
    );
    await tester.tap(find.text('my offer, required: false'));
    await tester.pump();
    expect(find.text('my bar downloading'), findsOneWidget);
    expect(find.byType(UpdateProgressBar), findsNothing);

    fake.result = playUpdate(priority: 5);
    fake.progressEvents.add(const DownloadProgress(InstallState.canceled));
    await tester.pump();
    await controller.check();
    await tester.pumpAndSettle();
    expect(controller.phase, UpdatePhase.required);
    expect(find.text('my required page'), findsOneWidget);
    expect(find.byType(RequiredUpdatePage), findsNothing);
  });

  testWidgets(
    'the offer fits a phone in landscape: it scrolls instead of overflowing',
    (tester) async {
      final fake = FakeStore(result: playUpdate());
      await show(tester, fake, screen: const Size(1680, 945)); // 640 x 360 dp
      expect(tester.takeException(), isNull);
      final update = find.widgetWithText(FilledButton, 'Update');
      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      await tester.tap(update);
      await tester.pump();
      expect(fake.flexibleStarts, 1);
    },
  );
}

/// [text] in a left-to-right isolate, as the Arabic labels write a Latin name.
String _ltr(String text) =>
    '${String.fromCharCode(0x2066)}$text${String.fromCharCode(0x2069)}';
