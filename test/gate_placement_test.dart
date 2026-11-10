import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import 'support/fake_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StoreUpdateController controllerFor(WidgetTester tester, FakeStore fake) {
    final c = StoreUpdateController(
      platform: fake,
      checkTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A screen the user opened on top of home.
  Route<void> details() => MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('details')),
  );

  testWidgets(
    'the required page covers a screen pushed on top of home, and back cannot leave it',
    (tester) async {
      final fake = FakeStore();
      final controller = controllerFor(tester, fake);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: StoreUpdateGate(
            controller: controller,
            appName: 'Acme',
            child: const Scaffold(body: Text('home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigatorKey.currentState!.push(details());
      await tester.pumpAndSettle();
      expect(find.text('details'), findsOneWidget);

      fake.result = playUpdate(
        priority: 5,
      ); // the app resumes; Play's screen is closed
      await controller.check();
      await tester.pumpAndSettle();
      expect(find.byKey(StoreUpdateGate.requiredKey), findsOneWidget);
      expect(find.text('details'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(StoreUpdateGate.requiredKey), findsOneWidget);

      fake.immediateResult = UpdateFlowResult.accepted;
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.byKey(StoreUpdateGate.requiredKey), findsNothing);
      expect(
        find.text('details'),
        findsOneWidget,
        reason: 'the user is back where they were',
      );
    },
  );

  testWidgets(
    'in MaterialApp.builder the sheet and the download bar show over any screen',
    (tester) async {
      final fake = FakeStore();
      final controller = controllerFor(tester, fake);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => StoreUpdateGate(
            controller: controller,
            navigatorKey: navigatorKey,
            appName: 'Acme',
            child: child!,
          ),
          home: const Scaffold(body: Text('home')),
        ),
      );
      await tester.pumpAndSettle();
      navigatorKey.currentState!.push(details());
      await tester.pumpAndSettle();

      fake.result = playUpdate();
      await controller.check();
      await tester.pumpAndSettle();
      expect(find.text('A new version of Acme is ready'), findsOneWidget);

      await tester.tap(find.text('Update'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      fake.progressEvents.add(
        const DownloadProgress(InstallState.downloading, bytes: 3, total: 10),
      );
      await tester.pump();
      expect(find.text('details'), findsOneWidget);
      expect(find.byKey(StoreUpdateGate.barKey), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
    },
  );

  testWidgets(
    'while disabled nothing is checked; enabling starts the checks without rebuilding the child',
    (tester) async {
      final fake = FakeStore(result: playUpdate());
      final controller = controllerFor(tester, fake);
      final childKey = GlobalKey();
      Widget app(bool enabled) => MaterialApp(
        home: StoreUpdateGate(
          controller: controller,
          appName: 'Acme',
          enabled: enabled,
          child: Scaffold(key: childKey, body: const Text('home')),
        ),
      );

      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      expect(fake.checks, 0);
      final before = childKey.currentState;

      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(fake.checks, 1);
      expect(find.text('A new version of Acme is ready'), findsOneWidget);
      expect(childKey.currentState, same(before));
    },
  );
}
