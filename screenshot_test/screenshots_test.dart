// Renders the screenshots used in the README and on pub.dev.
//
// Run from the package folder:
//   flutter test screenshot_test --update-goldens
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_update/store_update.dart';

import '../test/support/fake_store.dart';

const Size _screenSize = Size(390, 844);
const double _pixelRatio = 2;
const _brand = Color(0xFF2440DB);

/// Roboto and the Material icons from the Flutter SDK, and Noto Sans Arabic
/// from screenshot_test/fonts, so the screenshots show real text.
Future<void> _loadFonts() async {
  final engineDir = File(Platform.resolvedExecutable).parent;
  final material = Directory('${engineDir.parent.parent.path}/material_fonts');

  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    roboto.addFont(read('${material.path}/roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('${material.path}/materialicons-regular.otf'))).load();

  final arabic = FontLoader('Noto Sans Arabic');
  for (final weight in ['Regular', 'SemiBold', 'Bold']) {
    arabic.addFont(read('screenshot_test/fonts/NotoSansArabic-$weight.ttf'));
  }
  await arabic.load();
}

/// A plain app for the update UI to sit on.
class _SampleApp extends StatelessWidget {
  const _SampleApp({required this.arabic});

  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final items = arabic
        ? const [
            ('اجتماع الفريق', 'غداً الساعة 10:00'),
            ('قائمة المشتريات', '6 عناصر'),
            ('أفكار المشروع', 'عُدّلت أمس'),
            ('مواعيد الطبيب', 'الأحد القادم'),
          ]
        : const [
            ('Team meeting', 'Tomorrow at 10:00'),
            ('Groceries', '6 items'),
            ('Project ideas', 'Edited yesterday'),
            ('Dentist', 'Next Sunday'),
          ];
    return Scaffold(
      appBar: AppBar(title: Text(arabic ? 'ملاحظاتي' : 'Acme Notes')),
      body: ListView(
        children: [
          for (final (title, subtitle) in items)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.sticky_note_2)),
              title: Text(title),
              subtitle: Text(subtitle),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

void main() {
  setUpAll(_loadFonts);
  // This folder is a test folder the analyzer doesn't know about.
  // ignore: invalid_use_of_visible_for_testing_member
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<StoreUpdateController> show(
    WidgetTester tester,
    FakeStore store, {
    bool arabic = false,
  }) async {
    tester.view.physicalSize = _screenSize * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);
    debugDisableShadows = false; // real elevation; restored in shoot()
    final controller = StoreUpdateController(platform: store);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: _brand,
          fontFamily: arabic ? 'Noto Sans Arabic' : 'Roboto',
          fontFamilyFallback: const ['Roboto', 'Noto Sans Arabic'],
        ),
        locale: Locale(arabic ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: StoreUpdateGate(
          controller: controller,
          appName: arabic ? 'ملاحظاتي' : 'Acme Notes',
          child: _SampleApp(arabic: arabic),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> shoot(String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../screenshots/$name.png'),
    );
    debugDisableShadows = true;
  }

  Future<FakeStore> downloading(WidgetTester tester) async {
    final store = FakeStore(result: playUpdate());
    await show(tester, store);
    await tester.tap(find.text('Update'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    store.progressEvents.add(
      const DownloadProgress(
        InstallState.downloading,
        bytes: 15 * 1024 * 1024,
        total: 24 * 1024 * 1024,
      ),
    );
    await tester.pump();
    return store;
  }

  testWidgets('1 offer', (tester) async {
    await show(tester, FakeStore(result: playUpdate()));
    await shoot('1_offer');
  });

  testWidgets('2 downloading', (tester) async {
    await downloading(tester);
    await shoot('2_downloading');
  });

  testWidgets('3 ready', (tester) async {
    final store = await downloading(tester);
    store.progressEvents.add(
      const DownloadProgress(InstallState.downloaded, bytes: 1, total: 1),
    );
    await tester.pumpAndSettle();
    await shoot('3_ready');
  });

  testWidgets('4 required', (tester) async {
    await show(
      tester,
      FakeStore(result: playUpdate(priority: 5))
        ..immediateResult = UpdateFlowResult.failed,
    );
    await shoot('4_required');
  });

  testWidgets('5 offer in Arabic', (tester) async {
    await show(tester, FakeStore(result: playUpdate()), arabic: true);
    await shoot('5_offer_arabic');
  });

  testWidgets('6 App Store', (tester) async {
    await show(
      tester,
      FakeStore(
        result: const AppStoreCheck(
          storeVersion: '2.4.0',
          currentVersion: '2.3.1',
        ),
        checkUsesNetwork: true,
      ),
    );
    await shoot('6_app_store');
  });
}
