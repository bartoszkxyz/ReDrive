import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/services/settings/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppPreferences.resetCacheForTesting();
  });

  group('AppPreferences - Boot & Autostart Configuration', () {
    test('isAutoLaunchOnBootEnabled defaults to true', () async {
      final enabled = await AppPreferences.isAutoLaunchOnBootEnabled();
      expect(enabled, isTrue);
    });

    test('setAutoLaunchOnBootEnabled persists value', () async {
      await AppPreferences.setAutoLaunchOnBootEnabled(false);
      expect(await AppPreferences.isAutoLaunchOnBootEnabled(), isFalse);

      await AppPreferences.setAutoLaunchOnBootEnabled(true);
      expect(await AppPreferences.isAutoLaunchOnBootEnabled(), isTrue);
    });

    test('getLastBootAction and getLastBootTimestamp default to null', () async {
      expect(await AppPreferences.getLastBootAction(), isNull);
      expect(await AppPreferences.getLastBootTimestamp(), isNull);
    });

    test('reads boot action and timestamp when set in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.last_boot_action': 'com.syu.action.ACC_ON',
        'flutter.last_boot_timestamp': '2026-10-15 15:30:00',
      });
      AppPreferences.resetCacheForTesting();

      expect(await AppPreferences.getLastBootAction(), 'com.syu.action.ACC_ON');
      expect(await AppPreferences.getLastBootTimestamp(), '2026-10-15 15:30:00');
    });
  });
}
