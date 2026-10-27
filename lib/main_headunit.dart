import 'core/app_flavor.dart';
import 'main.dart' show runOBDriveApp;

/// Entrypoint for the OBDrive Headunit launcher target.
void main() async {
  await runOBDriveApp(AppFlavor.headunit);
}
