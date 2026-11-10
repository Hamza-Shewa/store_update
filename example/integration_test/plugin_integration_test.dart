// Runs on a real device or emulator: `flutter test integration_test` from the
// example directory. A debug build is not installed from a store, so the
// check must answer "no update" without throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:store_update/store_update.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a build not installed from a store gets no update', (
    tester,
  ) async {
    final check = await StoreUpdatePlatform.instance.check();
    expect(
      check,
      anyOf(
        isNull,
        isA<PlayCheck>().having((c) => c.info.available, 'available', false),
      ),
    );
  });

  testWidgets('the controller stays idle', (tester) async {
    final controller = StoreUpdateController();
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.phase, UpdatePhase.idle);
  });
}
