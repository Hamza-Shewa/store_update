import 'package:flutter/widgets.dart';

/// The text of the update UI. Use [StoreUpdateLabels.of] for the built-in
/// English or Arabic text, and [copyWith] to change any of it.
@immutable
class StoreUpdateLabels {
  const StoreUpdateLabels({
    required this.offerTitle,
    required this.offerBody,
    required this.offerRequiredBody,
    required this.update,
    required this.later,
    required this.downloading,
    required this.percent,
    required this.ready,
    required this.restart,
    required this.requiredTitle,
    required this.requiredBody,
    required this.requiredFailed,
    required this.updateNow,
    required this.openStore,
    required this.storeOfferTitle,
    required this.storeOfferBody,
  });

  /// Built-in English text naming the app [appName].
  factory StoreUpdateLabels.en({required String appName}) => StoreUpdateLabels(
    offerTitle: 'A new version of $appName is ready',
    offerBody:
        "It downloads in the background while you keep using the app. "
        "We'll tell you when it's ready to install.",
    offerRequiredBody:
        'This update is needed to keep $appName working. It downloads in the '
        'background while you keep using the app.',
    update: 'Update',
    later: 'Later',
    downloading: 'Downloading the update',
    percent: (n) => '$n%',
    ready: 'Update downloaded',
    restart: 'Restart to update',
    requiredTitle: 'Update $appName to continue',
    requiredBody:
        'This version of $appName is no longer supported. Install the update '
        'to keep using it.',
    requiredFailed:
        "The update couldn't start. Check your connection and try again, or "
        'update from Google Play.',
    updateNow: 'Update now',
    openStore: 'Open Google Play',
    storeOfferTitle: (version) => '$appName $version is available',
    storeOfferBody:
        'Update from the App Store to get the latest fixes and improvements.',
  );

  /// Built-in Arabic text naming the app [appName]. Numbers, versions and a
  /// Latin [appName] are isolated so they read correctly right to left.
  factory StoreUpdateLabels.ar({required String appName}) {
    final app = _hasArabic(appName) ? appName : _isolate(appName);
    return StoreUpdateLabels(
      offerTitle: 'إصدار جديد من $app جاهز',
      offerBody:
          'يُنزَّل في الخلفية وأنت تستخدم التطبيق، وسنخبرك عندما يصبح جاهزاً للتثبيت.',
      offerRequiredBody:
          'هذا التحديث ضروري ليستمر $app في العمل، ويُنزَّل في الخلفية وأنت تستخدم التطبيق.',
      update: 'تحديث',
      later: 'لاحقاً',
      downloading: 'جارٍ تنزيل التحديث',
      percent: (n) => '${_isolate('$n')}٪',
      ready: 'تم تنزيل التحديث',
      restart: 'أعد التشغيل للتحديث',
      requiredTitle: 'حدّث $app للمتابعة',
      requiredBody:
          'لم يعد هذا الإصدار من $app مدعوماً. ثبّت التحديث لتستمر في استخدامه.',
      requiredFailed:
          'تعذّر بدء التحديث. تحقّق من اتصالك وحاول مجدداً، أو حدّث التطبيق من Google Play.',
      updateNow: 'حدّث الآن',
      openStore: 'افتح Google Play',
      storeOfferTitle: (version) => 'الإصدار ${_isolate(version)} من $app متاح',
      storeOfferBody:
          'حدّث التطبيق من App Store لتحصل على أحدث الإصلاحات والتحسينات.',
    );
  }

  /// Arabic when the [context]'s locale is Arabic, English otherwise.
  factory StoreUpdateLabels.of(
    BuildContext context, {
    required String appName,
  }) => Localizations.maybeLocaleOf(context)?.languageCode == 'ar'
      ? StoreUpdateLabels.ar(appName: appName)
      : StoreUpdateLabels.en(appName: appName);

  /// Title of the background download offer.
  final String offerTitle;

  /// Body of an optional download offer.
  final String offerBody;

  /// Body of a required download offer (no "Later").
  final String offerRequiredBody;

  /// The offer's accept button.
  final String update;

  /// The offer's dismiss button.
  final String later;

  /// Shown while the update downloads.
  final String downloading;

  /// The download percentage, from 0 to 100.
  final String Function(int percent) percent;

  /// Shown once the update has downloaded.
  final String ready;

  /// The button that installs a downloaded update.
  final String restart;

  /// Title of the required-update page.
  final String requiredTitle;

  /// Why the required update is needed.
  final String requiredBody;

  /// Shown when Play's update could not start.
  final String requiredFailed;

  /// The required page's button that starts Play's update again.
  final String updateNow;

  /// The required page's button that opens the store.
  final String openStore;

  /// iOS: title naming the App Store [version].
  final String Function(String version) storeOfferTitle;

  /// iOS: body of the App Store offer.
  final String storeOfferBody;

  StoreUpdateLabels copyWith({
    String? offerTitle,
    String? offerBody,
    String? offerRequiredBody,
    String? update,
    String? later,
    String? downloading,
    String Function(int percent)? percent,
    String? ready,
    String? restart,
    String? requiredTitle,
    String? requiredBody,
    String? requiredFailed,
    String? updateNow,
    String? openStore,
    String Function(String version)? storeOfferTitle,
    String? storeOfferBody,
  }) => StoreUpdateLabels(
    offerTitle: offerTitle ?? this.offerTitle,
    offerBody: offerBody ?? this.offerBody,
    offerRequiredBody: offerRequiredBody ?? this.offerRequiredBody,
    update: update ?? this.update,
    later: later ?? this.later,
    downloading: downloading ?? this.downloading,
    percent: percent ?? this.percent,
    ready: ready ?? this.ready,
    restart: restart ?? this.restart,
    requiredTitle: requiredTitle ?? this.requiredTitle,
    requiredBody: requiredBody ?? this.requiredBody,
    requiredFailed: requiredFailed ?? this.requiredFailed,
    updateNow: updateNow ?? this.updateNow,
    openStore: openStore ?? this.openStore,
    storeOfferTitle: storeOfferTitle ?? this.storeOfferTitle,
    storeOfferBody: storeOfferBody ?? this.storeOfferBody,
  );

  /// Wraps [text] in a left-to-right isolate.
  static String _isolate(String text) => '\u2066$text\u2069';

  static bool _hasArabic(String text) =>
      RegExp('[\u0600-\u06FF]').hasMatch(text);
}
