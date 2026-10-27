import 'core/app_flavor.dart';
import 'main.dart' show runOBDriveApp;

/// Entrypoint for the OBDrive Phone companion target.
void main() async {
  await runOBDriveApp(AppFlavor.phone);
}
