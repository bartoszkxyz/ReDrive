import 'core/app_flavor.dart';
import 'main.dart' show runRedriveApp;

/// Entrypoint for the OBDrive Phone companion target.
void main() async {
  await runRedriveApp(AppFlavor.phone);
}
