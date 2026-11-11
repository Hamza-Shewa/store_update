import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_update/store_update.dart';

const _lri = 0x2066; // left-to-right isolate
const _pdi = 0x2069; // pop directional isolate

void main() {
  test('English names the app and the version', () {
    final en = StoreUpdateLabels.en(appName: 'Acme');
    expect(en.offerTitle, 'A new version of Acme is ready');
    expect(en.requiredTitle, 'Update Acme to continue');
    expect(en.storeOfferTitle('2.1.0'), 'Acme 2.1.0 is available');
    expect(en.percent(42), '42%');
  });

  test('Arabic isolates numbers, versions and a Latin app name', () {
    final ar = StoreUpdateLabels.ar(appName: 'Acme');
    final percent = ar.percent(70);
    expect(percent.codeUnits.first, _lri);
    expect(percent, contains('70'));
    expect(percent.endsWith('٪'), isTrue);

    final title = ar.storeOfferTitle('2.1.0');
    expect(
      title,
      contains(String.fromCharCodes([_lri, ...'2.1.0'.codeUnits, _pdi])),
    );
    expect(
      title,
      contains(String.fromCharCodes([_lri, ...'Acme'.codeUnits, _pdi])),
    );
  });

  test('the forced prompt has its own text in both languages', () {
    final en = StoreUpdateLabels.en(appName: 'Acme');
    expect(en.forcedTitle, 'Update Acme to continue');
    expect(en.exit, 'Exit');
    expect(en.forcedFailed, contains("couldn't open"));
    expect(en.forcedFailed, isNot(contains('Google Play')));

    final ar = StoreUpdateLabels.ar(appName: 'Acme');
    expect(ar.exit, 'خروج');
    expect(
      ar.forcedTitle,
      contains(String.fromCharCodes([_lri, ...'Acme'.codeUnits, _pdi])),
    );
    expect(en.copyWith(exit: 'Quit').exit, 'Quit');
  });

  test('Arabic keeps an Arabic app name as it is', () {
    final ar = StoreUpdateLabels.ar(appName: 'هوية');
    expect(ar.offerTitle, 'إصدار جديد من هوية جاهز');
    expect(ar.offerTitle.codeUnits, isNot(contains(_lri)));
  });

  test('copyWith changes only what it is given', () {
    final en = StoreUpdateLabels.en(appName: 'Acme');
    final changed = en.copyWith(requiredBody: 'Needed for the new server.');
    expect(changed.requiredBody, 'Needed for the new server.');
    expect(changed.offerTitle, en.offerTitle);
    expect(changed.percent(5), '5%');
  });

  testWidgets('of() follows the locale: Arabic for ar, English otherwise', (
    tester,
  ) async {
    final seen = <String, String>{};
    for (final lang in ['ar', 'en', 'fr']) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              seen[lang] = StoreUpdateLabels.of(
                context,
                appName: 'Acme',
              ).update;
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(seen, {'ar': 'تحديث', 'en': 'Update', 'fr': 'Update'});
  });
}
