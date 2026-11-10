import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update_example/main.dart';

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
}
