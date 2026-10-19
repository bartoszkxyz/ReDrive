import 'core/app_flavor.dart';
import 'main.dart' show runRedriveApp;

/// Entrypoint for the OBDrive Headunit launcher target.
void main() async {
  await runRedriveApp(AppFlavor.headunit);
}
