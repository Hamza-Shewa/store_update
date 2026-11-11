import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import 'support/fake_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<StoreUpdateController> show(
    WidgetTester tester,
    FakeStore fake, {
    String lang = 'en',
    OfferBuilder? offerBuilder,
    OfferPresenter? offerPresenter,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
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
          offerBuilder: offerBuilder,
          offerPresenter: offerPresenter,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Lets a prompt close without waiting for an endless progress animation.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  /// A custom prompt with plain buttons that shows what it was given.
  Widget plainPrompt(BuildContext context, UpdateOffer offer) => Material(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('mine: ${offer.storeVersion ?? 'play'}'),
        TextButton(onPressed: offer.onUpdate, child: const Text('Go')),
        if (offer.onLater case final later?)
          TextButton(onPressed: later, child: const Text('Not now')),
      ],
    ),
  );

  group('offerBuilder', () {
    testWidgets('its onUpdate closes the prompt and starts the download', (
      tester,
    ) async {
      final fake = FakeStore(result: playUpdate());
      final controller = await show(tester, fake, offerBuilder: plainPrompt);
      expect(find.text('mine: play'), findsOneWidget);
      expect(find.byType(UpdateOfferSheet), findsNothing);

      await tester.tap(find.text('Go'));
      await settle(tester);
      expect(fake.flexibleStarts, 1);
      expect(controller.phase, UpdatePhase.downloading);
      expect(find.text('mine: play'), findsNothing);
    });

    testWidgets('its onLater closes the prompt without updating', (
      tester,
    ) async {
      final fake = FakeStore(result: playUpdate());
      final controller = await show(tester, fake, offerBuilder: plainPrompt);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(fake.flexibleStarts, 0);
      expect(controller.phase, UpdatePhase.idle);
      expect(find.text('mine: play'), findsNothing);
    });

    testWidgets(
      'a required offer has no onLater, and back cannot close the custom prompt',
      (tester) async {
        final fake = FakeStore(
          result: playUpdate(priority: 5, immediate: false),
        );
        UpdateOffer? given;
        await show(
          tester,
          fake,
          offerBuilder: (context, offer) {
            given = offer;
            return plainPrompt(context, offer);
          },
        );
        expect(given!.required, isTrue);
        expect(given!.onLater, isNull);
        expect(find.text('Not now'), findsNothing);

        await pressBack(tester);
        expect(find.text('mine: play'), findsOneWidget);
        expect(fake.flexibleStarts, 0);
      },
    );

    testWidgets('an iOS offer gives the prompt the App Store version', (
      tester,
    ) async {
      final fake = FakeStore(
        result: const AppStoreCheck(
          storeVersion: '1.2.0',
          currentVersion: '1.0.0',
        ),
        checkUsesNetwork: true,
      );
      await show(tester, fake, offerBuilder: plainPrompt);
      expect(find.text('mine: 1.2.0'), findsOneWidget);
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(fake.storeOpened, 1);
    });

    testWidgets('UpdateOfferSheet keeps the built-in prompt with changes', (
      tester,
    ) async {
      final fake = FakeStore(result: playUpdate());
      await show(
        tester,
        fake,
        offerBuilder: (context, offer) => UpdateOfferSheet(
          offer: offer,
          content: const Text('Faster transfers'),
        ),
      );
      expect(find.text('A new version of Hawiya is ready'), findsOneWidget);
      expect(find.text('Faster transfers'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await settle(tester);
      expect(fake.flexibleStarts, 1);
    });
  });

  group('offerPresenter', () {
    testWidgets('by default the prompt is a bottom sheet', (tester) async {
      await show(tester, FakeStore(result: playUpdate()));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets(
      'showUpdateOfferDialog shows the built-in prompt in a dialog; Update starts the download',
      (tester) async {
        final fake = FakeStore(result: playUpdate());
        await show(tester, fake, offerPresenter: showUpdateOfferDialog);
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('A new version of Hawiya is ready'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Update'));
        await settle(tester);
        expect(fake.flexibleStarts, 1);
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets('a dialog Later closes it without updating', (tester) async {
      final fake = FakeStore(result: playUpdate());
      final controller = await show(
        tester,
        fake,
        offerPresenter: showUpdateOfferDialog,
      );
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fake.flexibleStarts, 0);
      expect(controller.phase, UpdatePhase.idle);
    });

    testWidgets(
      'a required offer in a dialog has no Later; the barrier and back do not close it',
      (tester) async {
        final fake = FakeStore(
          result: playUpdate(priority: 5, immediate: false),
        );
        await show(tester, fake, offerPresenter: showUpdateOfferDialog);
        expect(find.text('Later'), findsNothing);

        await tester.tapAt(const Offset(10, 10)); // the barrier
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);

        await pressBack(tester);
        expect(find.byType(Dialog), findsOneWidget);
        expect(fake.flexibleStarts, 0);
      },
    );

    testWidgets('Arabic: the dialog prompt reads right to left', (
      tester,
    ) async {
      await show(
        tester,
        FakeStore(result: playUpdate()),
        lang: 'ar',
        offerPresenter: showUpdateOfferDialog,
      );
      final update = find.widgetWithText(FilledButton, 'تحديث');
      final later = find.widgetWithText(TextButton, 'لاحقاً');
      expect(update, findsOneWidget);
      expect(later, findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(UpdateOfferSheet))),
        TextDirection.rtl,
      );
      // The badge sits at the start of the line: the right in Arabic.
      final dialog = tester.getRect(find.byType(Dialog));
      final badge = tester.getRect(find.byType(UpdateBadge));
      expect(dialog.right - badge.right, lessThan(badge.left - dialog.left));
    });

    testWidgets(
      'a custom presenter is told whether the offer is required, and its result decides',
      (tester) async {
        final fake = FakeStore(result: playUpdate());
        final requiredSeen = <bool>[];
        await show(
          tester,
          fake,
          offerPresenter: (context, builder, {required required}) {
            requiredSeen.add(required);
            return Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (context) => Scaffold(body: builder(context)),
              ),
            );
          },
        );
        expect(requiredSeen, [false]);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('A new version of Hawiya is ready'), findsOneWidget);

        await tester.tap(find.text('Update'));
        await settle(tester);
        expect(fake.flexibleStarts, 1);
        expect(find.text('home'), findsOneWidget);
      },
    );

    testWidgets(
      'a presenter that throws counts as Later and is reported; the next check offers again',
      (tester) async {
        final fake = FakeStore(
          result: playUpdate(priority: 5, immediate: false),
        );
        var calls = 0;
        final controller = await show(
          tester,
          fake,
          offerPresenter: (context, builder, {required required}) {
            calls++;
            if (calls == 1) throw StateError('no route');
            return showUpdateOfferSheet(context, builder, required: required);
          },
        );
        expect(tester.takeException(), isA<StateError>());
        expect(calls, 1);
        expect(controller.phase, UpdatePhase.idle);
        expect(fake.flexibleStarts, 0);

        await controller.check();
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.byType(BottomSheet), findsOneWidget);
      },
    );
  });

  group('UpdateOfferSheet', () {
    Future<void> pumpSheet(WidgetTester tester, UpdateOfferSheet sheet) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: sheet)));

    final labels = StoreUpdateLabels.en(appName: 'Hawiya');

    testWidgets(
      'without changes it shows the badge, the text and two buttons',
      (tester) async {
        var updates = 0, laters = 0;
        await pumpSheet(
          tester,
          UpdateOfferSheet(
            offer: UpdateOffer(
              labels: labels,
              onUpdate: () => updates++,
              onLater: () => laters++,
            ),
          ),
        );
        expect(find.byType(UpdateBadge), findsOneWidget);
        expect(find.text(labels.offerBody), findsOneWidget);
        await tester.tap(find.text('Update'));
        await tester.tap(find.text('Later'));
        expect((updates, laters), (1, 1));
      },
    );

    testWidgets(
      'icon, content and button styles change it; touch targets stay at least 48',
      (tester) async {
        const green = Color(0xFF2E7D32);
        await pumpSheet(
          tester,
          UpdateOfferSheet(
            offer: UpdateOffer(labels: labels, onUpdate: () {}, onLater: () {}),
            icon: const Icon(Icons.rocket_launch, key: Key('my-icon')),
            content: const Text('Faster transfers'),
            updateButtonStyle: FilledButton.styleFrom(backgroundColor: green),
            laterButtonStyle: TextButton.styleFrom(
              foregroundColor: green,
              minimumSize: const Size(64, 64),
            ),
          ),
        );
        expect(find.byKey(const Key('my-icon')), findsOneWidget);
        expect(find.byType(UpdateBadge), findsNothing);

        // The content sits between the text and the buttons.
        final body = tester.getRect(find.text(labels.offerBody));
        final notes = tester.getRect(find.text('Faster transfers'));
        final update = find.widgetWithText(FilledButton, 'Update');
        expect(notes.top, greaterThan(body.bottom));
        expect(tester.getRect(update).top, greaterThan(notes.bottom));

        final updateStyle = tester.widget<FilledButton>(update).style!;
        expect(updateStyle.backgroundColor!.resolve({}), green);
        final later = find.widgetWithText(TextButton, 'Later');
        expect(
          tester.widget<TextButton>(later).style!.foregroundColor!.resolve({}),
          green,
        );
        // Unset fields keep the built-in 48 target; set ones win over it.
        expect(tester.getSize(update).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(later).height, 64);
      },
    );

    testWidgets('a required offer has no Later and the required text', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        UpdateOfferSheet(
          offer: UpdateOffer(labels: labels, onUpdate: () {}),
        ),
      );
      expect(find.text('Later'), findsNothing);
      expect(find.text(labels.offerRequiredBody), findsOneWidget);
    });
  });
}
