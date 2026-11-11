/// In-app updates for Flutter apps: Google Play In-App Updates (immediate and
/// flexible, with download progress) on Android, and an App Store prompt with
/// the store page shown inside the app on iOS, plus a ready-made English and
/// Arabic UI.
///
/// ```dart
/// final updates = StoreUpdateController();
///
/// StoreUpdateGate(
///   controller: updates,
///   appName: 'My App',
///   child: const HomeScreen(),
/// );
/// ```
library;

export 'src/models.dart';
export 'src/platform_interface.dart';
export 'src/policy.dart';
export 'src/store_update_controller.dart';
export 'src/ui/forced_update_prompt.dart';
export 'src/ui/store_update_gate.dart';
export 'src/ui/store_update_labels.dart';
export 'src/ui/update_offer.dart';
export 'src/ui/update_widgets.dart';
