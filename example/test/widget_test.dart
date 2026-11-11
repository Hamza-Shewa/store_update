import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';
import 'package:store_update_example/main.dart';
import 'package:store_update_example/prompt_styles.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The real store, as Google Play answers when there is no update.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('store_update'),
          (call) async => {'availability': 'none', 'installStatus': 'unknown'},
        );
  });

  testWidgets(
    'no update from the real store; a simulated one shows the offer',
    (tester) async {
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.text('Google Play: optional update'));
      await tester.pumpAndSettle();
      expect(find.text('A new version of Example is ready'), findsOneWidget);
    },
  );

  testWidgets('the simulated download fills the bar, then offers the restart', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Play: optional update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Downloading the update'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Restart to update'), findsOneWidget);
  });

  Future<void> tapTile(WidgetTester tester, String title) async {
    final tile = find.text(title);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  group('offer prompt styles', () {
    testWidgets('the dialog style shows the built-in prompt in a dialog', (
      tester,
    ) async {
      await tester.pumpWidget(const ExampleApp());
      await tapTile(tester, PromptStyle.dialog.title);
      await tapTile(tester, 'Google Play: optional update');
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('A new version of Example is ready'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'the changed sheet shows release notes and Update still downloads',
      (tester) async {
        await tester.pumpWidget(const ExampleApp());
        await tapTile(tester, PromptStyle.tweaked.title);
        await tapTile(tester, 'Google Play: optional update');
        expect(find.byType(UpdateBadge), findsNothing);
        expect(find.text("What's new"), findsOneWidget);
        expect(find.text('Faster sign-in'), findsOneWidget);

        final update = find.text('Update');
        await tester.ensureVisible(update);
        await tester.pumpAndSettle();
        await tester.tap(update);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text('Downloading the update'), findsOneWidget);
      },
    );

    testWidgets('your own prompt shows the App Store version', (tester) async {
      await tester.pumpWidget(const ExampleApp());
      await tapTile(tester, PromptStyle.custom.title);
      await tapTile(tester, 'App Store: newer version');
      expect(find.byType(CompactOffer), findsOneWidget);
      expect(find.text('Example 2.0.0 is available'), findsOneWidget);
      expect(find.text('Required'), findsNothing);
    });

    testWidgets(
      'your own prompt in Arabic: Arabic text, Later on the right of Update',
      (tester) async {
        await tester.pumpWidget(const ExampleApp());
        await tapTile(tester, 'Arabic (right to left)');
        await tapTile(tester, PromptStyle.custom.title);
        await tapTile(tester, 'Google Play: optional update');
        final later = find.widgetWithText(OutlinedButton, 'لاحقاً');
        final update = find.widgetWithText(FilledButton, 'تحديث');
        expect(later, findsOneWidget);
        expect(update, findsOneWidget);
        expect(
          tester.getCenter(later).dx,
          greaterThan(tester.getCenter(update).dx),
        );
        for (final button in [later, update]) {
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
      },
    );

    testWidgets('changing the style shows the simulated offer again in it', (
      tester,
    ) async {
      await tester.pumpWidget(const ExampleApp());
      await tapTile(tester, 'Google Play: optional update');
      expect(find.byType(BottomSheet), findsOneWidget);
      await tapTile(tester, 'Later');
      expect(find.byType(BottomSheet), findsNothing);

      await tapTile(tester, PromptStyle.dialog.title);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('A new version of Example is ready'), findsOneWidget);
    });
  });
}
