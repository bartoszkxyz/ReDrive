import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/core/app_flavor.dart';

void main() {
  setUp(() {
    AppConfig.reset();
  });

  tearDown(() {
    AppConfig.reset();
  });

  group('AppFlavor enum', () {
    test('contains headunit and phone values', () {
      expect(AppFlavor.values, containsAll([AppFlavor.headunit, AppFlavor.phone]));
      expect(AppFlavor.values.length, 2);
    });

    test('isHeadunit returns true only for AppFlavor.headunit', () {
      expect(AppFlavor.headunit.isHeadunit, isTrue);
      expect(AppFlavor.headunit.isPhone, isFalse);

      expect(AppFlavor.phone.isHeadunit, isFalse);
      expect(AppFlavor.phone.isPhone, isTrue);
    });

    test('fromString parses phone case-insensitively', () {
      expect(AppFlavor.fromString('phone'), AppFlavor.phone);
      expect(AppFlavor.fromString('PHONE'), AppFlavor.phone);
      expect(AppFlavor.fromString('Phone'), AppFlavor.phone);
    });

    test('fromString defaults to headunit for null or unrecognized names', () {
      expect(AppFlavor.fromString('headunit'), AppFlavor.headunit);
      expect(AppFlavor.fromString('HEADUNIT'), AppFlavor.headunit);
      expect(AppFlavor.fromString(null), AppFlavor.headunit);
      expect(AppFlavor.fromString(''), AppFlavor.headunit);
      expect(AppFlavor.fromString('other'), AppFlavor.headunit);
    });
  });

  group('AppConfig singleton and defaults', () {
    test('default current configuration without initialize returns headunit', () {
      expect(AppConfig.current.flavor, AppFlavor.headunit);
      expect(AppConfig.current.appTitle, 'ReDrive Headunit');
      expect(AppConfig.current.flavor.isHeadunit, isTrue);
      expect(AppConfig.current.flavor.isPhone, isFalse);
      expect(AppConfig.isHeadunit, isTrue);
      expect(AppConfig.isPhone, isFalse);
    });

    test('initialize with headunit and default title sets headunit config', () {
      AppConfig.initialize(flavor: AppFlavor.headunit);

      expect(AppConfig.current.flavor, AppFlavor.headunit);
      expect(AppConfig.current.appTitle, 'ReDrive Headunit');
      expect(AppConfig.isHeadunit, isTrue);
      expect(AppConfig.isPhone, isFalse);
    });

    test('initialize with headunit and custom title sets custom title', () {
      AppConfig.initialize(
        flavor: AppFlavor.headunit,
        appTitle: 'Custom Headunit OS',
      );

      expect(AppConfig.current.flavor, AppFlavor.headunit);
      expect(AppConfig.current.appTitle, 'Custom Headunit OS');
      expect(AppConfig.isHeadunit, isTrue);
      expect(AppConfig.isPhone, isFalse);
    });

    test('initialize with phone and default title sets ReDrive', () {
      AppConfig.initialize(flavor: AppFlavor.phone);

      expect(AppConfig.current.flavor, AppFlavor.phone);
      expect(AppConfig.current.appTitle, 'ReDrive');
      expect(AppConfig.isHeadunit, isFalse);
      expect(AppConfig.isPhone, isTrue);
    });

    test('initialize with phone and custom title sets custom title', () {
      AppConfig.initialize(
        flavor: AppFlavor.phone,
        appTitle: 'ReDrive Companion App',
      );

      expect(AppConfig.current.flavor, AppFlavor.phone);
      expect(AppConfig.current.appTitle, 'ReDrive Companion App');
      expect(AppConfig.isHeadunit, isFalse);
      expect(AppConfig.isPhone, isTrue);
    });

    test('reset clears singleton back to default headunit configuration', () {
      AppConfig.initialize(
        flavor: AppFlavor.phone,
        appTitle: 'Temporary Phone',
      );
      expect(AppConfig.isPhone, isTrue);

      AppConfig.reset();

      expect(AppConfig.current.flavor, AppFlavor.headunit);
      expect(AppConfig.current.appTitle, 'ReDrive Headunit');
      expect(AppConfig.isHeadunit, isTrue);
      expect(AppConfig.isPhone, isFalse);
    });

    test('direct constructor instantiation works properly', () {
      const config = AppConfig(
        flavor: AppFlavor.phone,
        appTitle: 'Direct Config',
      );

      expect(config.flavor, AppFlavor.phone);
      expect(config.appTitle, 'Direct Config');
      expect(config.flavor.isHeadunit, isFalse);
      expect(config.flavor.isPhone, isTrue);
    });
  });
}
