import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/core/theme/custom_dashboard_theme.dart';
import 'package:obdrive/core/theme/theme_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomDashboardTheme and CustomThemeColors', () {
    test('1. CustomDashboardTheme JSON round-trip for default, sport red, and stealth OLED presets', () {
      final defaultTheme = CustomDashboardTheme.defaultTheme();
      final defaultRoundTrip = CustomDashboardTheme.fromJson(defaultTheme.toJson());
      expect(defaultRoundTrip, equals(defaultTheme));
      expect(defaultRoundTrip.id, equals('obdrive_neon_lime'));

      final sportRed = CustomDashboardTheme.sportRed();
      final sportRoundTrip = CustomDashboardTheme.fromJson(sportRed.toJson());
      expect(sportRoundTrip, equals(sportRed));
      expect(sportRoundTrip.id, equals('sport_track_red'));
      expect(sportRoundTrip.colors.primaryAccent, equals(const Color(0xFFFF3333)));
      expect(sportRoundTrip.colors.secondaryAccent, equals(const Color(0xFFFFB800)));

      final stealthOled = CustomDashboardTheme.stealthOled();
      final stealthRoundTrip = CustomDashboardTheme.fromJson(stealthOled.toJson());
      expect(stealthRoundTrip, equals(stealthOled));
      expect(stealthRoundTrip.id, equals('stealth_oled'));
      expect(stealthRoundTrip.colors.background, equals(const Color(0xFF000000)));
      expect(stealthRoundTrip.colors.surfaceCard, equals(const Color(0xFF0D0D0E)));
      expect(stealthRoundTrip.colors.primaryAccent, equals(const Color(0xFFE0E6ED)));
    });

    test('2. Safe hex color parsing handles #RRGGBB, #AARRGGBB, missing #, and invalid characters (falling back gracefully)', () {
      const fallback = Color(0xFF123456);

      // #RRGGBB
      expect(CustomThemeColors.parseColor('#BDF343', fallback), equals(const Color(0xFFBDF343)));
      expect(CustomThemeColors.parseColor('#00E5FF', fallback), equals(const Color(0xFF00E5FF)));

      // #AARRGGBB
      expect(CustomThemeColors.parseColor('#80BDF343', fallback), equals(const Color(0x80BDF343)));
      expect(CustomThemeColors.parseColor('#FFFFFFFF', fallback), equals(const Color(0xFFFFFFFF)));

      // missing #
      expect(CustomThemeColors.parseColor('BDF343', fallback), equals(const Color(0xFFBDF343)));
      expect(CustomThemeColors.parseColor('80BDF343', fallback), equals(const Color(0x80BDF343)));

      // 0x prefix
      expect(CustomThemeColors.parseColor('0xFFBDF343', fallback), equals(const Color(0xFFBDF343)));

      // #RGB shorthand
      expect(CustomThemeColors.parseColor('#FFF', fallback), equals(const Color(0xFFFFFFFF)));
      expect(CustomThemeColors.parseColor('FFF', fallback), equals(const Color(0xFFFFFFFF)));

      // #ARGB shorthand
      expect(CustomThemeColors.parseColor('#8FFF', fallback), equals(const Color(0x88FFFFFF)));

      // Int value
      expect(CustomThemeColors.parseColor(0xFFBDF343, fallback), equals(const Color(0xFFBDF343)));

      // Invalid characters
      expect(CustomThemeColors.parseColor('#GGGGGG', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('INVALID', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('#12ZZ45', fallback), equals(fallback));

      // Invalid lengths and null
      expect(CustomThemeColors.parseColor('', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('   ', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor(null, fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('#12', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('#12345', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('#1234567', fallback), equals(fallback));
      expect(CustomThemeColors.parseColor('#123456789', fallback), equals(fallback));

      // Test fromJson fallback behaviour on invalid values
      final colors = CustomThemeColors.fromJson({
        'primaryAccent': '#FF0000',
        'background': 'INVALID_COLOR',
      });
      expect(colors.primaryAccent, equals(const Color(0xFFFF0000)));
      expect(colors.background, equals(const Color(0xFF070709))); // default fallback
    });

    test('7. toMaterialTheme() returns a valid ThemeData with matching primary and scaffold background colors', () {
      final sportTheme = CustomDashboardTheme.sportRed();
      final materialTheme = sportTheme.toMaterialTheme();

      expect(materialTheme.useMaterial3, isTrue);
      expect(materialTheme.brightness, equals(Brightness.dark));
      expect(materialTheme.scaffoldBackgroundColor, equals(sportTheme.colors.background));
      expect(materialTheme.cardColor, equals(sportTheme.colors.surfaceCard));
      expect(materialTheme.colorScheme.primary, equals(sportTheme.colors.primaryAccent));
      expect(materialTheme.colorScheme.secondary, equals(sportTheme.colors.secondaryAccent));
      expect(materialTheme.colorScheme.surface, equals(sportTheme.colors.background));
      expect(materialTheme.colorScheme.surfaceContainer, equals(sportTheme.colors.surfaceCard));
      expect(materialTheme.colorScheme.onSurface, equals(sportTheme.colors.textMain));
    });
  });

  group('ThemeEngine', () {
    test('3. ThemeEngine starts with default theme and notifies listeners when a new theme is applied', () async {
      final engine = ThemeEngine(inMemory: true);
      expect(engine.currentTheme.id, equals('obdrive_neon_lime'));
      expect(engine.colors.primaryAccent, equals(const Color(0xFFBDF343)));
      expect(engine.gaugeStyle.needleStyle, equals(GaugeNeedleStyle.solidBlade));

      int notifyCount = 0;
      engine.addListener(() {
        notifyCount++;
      });

      await engine.applyTheme(CustomDashboardTheme.sportRed());
      expect(notifyCount, equals(1));
      expect(engine.currentTheme.id, equals('sport_track_red'));
      expect(engine.colors.primaryAccent, equals(const Color(0xFFFF3333)));
      expect(engine.materialTheme.colorScheme.primary, equals(const Color(0xFFFF3333)));
    });

    test('4. importThemeFromJsonString parses custom theme JSON and updates currentTheme and colors', () async {
      final engine = ThemeEngine(inMemory: true);
      final jsonMap = {
        'id': 'retro_wave',
        'name': 'Retro Wave Synth',
        'author': 'Tester',
        'version': '2.1',
        'colors': {
          'background': '#0A051B',
          'surfaceCard': '#180E33',
          'primaryAccent': '#FF007F',
          'secondaryAccent': '#00F0FF',
          'textMain': '#FFFFFF',
          'textMuted': '#9D8EC2',
          'coolantNormal': '#00FFA3',
          'coolantWarning': '#FFD600',
          'coolantOverheat': '#FF0055',
          'engineLoadLow': '#00FFA3',
          'engineLoadMedium': '#FFD600',
          'engineLoadHigh': '#FF0055',
          'fuelFlowBarStart': '#00FFA3',
          'fuelFlowBarEnd': '#FF007F',
        },
        'gaugeStyle': {
          'needleStyle': 'sweepingLine',
          'arcThickness': 10.5,
          'glowIntensity': 0.6,
          'showTicks': false,
        },
      };

      int notifyCount = 0;
      engine.addListener(() => notifyCount++);

      final success = await engine.importThemeFromJsonString(jsonEncode(jsonMap));
      expect(success, isTrue);
      expect(notifyCount, equals(1));

      expect(engine.currentTheme.id, equals('retro_wave'));
      expect(engine.currentTheme.name, equals('Retro Wave Synth'));
      expect(engine.currentTheme.author, equals('Tester'));
      expect(engine.currentTheme.version, equals('2.1'));
      expect(engine.colors.background, equals(const Color(0xFF0A051B)));
      expect(engine.colors.primaryAccent, equals(const Color(0xFFFF007F)));
      expect(engine.colors.secondaryAccent, equals(const Color(0xFF00F0FF)));
      expect(engine.gaugeStyle.needleStyle, equals(GaugeNeedleStyle.sweepingLine));
      expect(engine.gaugeStyle.arcThickness, equals(10.5));
      expect(engine.gaugeStyle.glowIntensity, equals(0.6));
      expect(engine.gaugeStyle.showTicks, isFalse);
    });

    test('5. importThemeFromJsonString returns false on invalid JSON without throwing unhandled exceptions', () async {
      final engine = ThemeEngine(inMemory: true);
      final initialTheme = engine.currentTheme;

      expect(await engine.importThemeFromJsonString('{bad json:'), isFalse);
      expect(await engine.importThemeFromJsonString('not a json string'), isFalse);
      expect(await engine.importThemeFromJsonString('[1, 2, 3]'), isFalse);
      expect(await engine.importThemeFromJsonString('"plain string"'), isFalse);
      expect(await engine.importThemeFromJsonString(''), isFalse);

      // Theme remains unchanged after failed imports
      expect(engine.currentTheme, equals(initialTheme));
    });

    test('6. resetToDefault restores the default theme', () async {
      final engine = ThemeEngine(inMemory: true);
      await engine.applyTheme(CustomDashboardTheme.stealthOled());
      expect(engine.currentTheme.id, equals('stealth_oled'));

      int notifyCount = 0;
      engine.addListener(() => notifyCount++);

      await engine.resetToDefault();
      expect(notifyCount, equals(1));
      expect(engine.currentTheme, equals(CustomDashboardTheme.defaultTheme()));
      expect(engine.currentTheme.id, equals('obdrive_neon_lime'));
    });

    test('8. File persistence: verifies saving and reloading from a temporary file', () async {
      final tempDir = Directory.systemTemp.createTempSync('theme_persistence_test');
      final tempFile = File('${tempDir.path}/active_theme.json');

      try {
        final engine1 = ThemeEngine(customThemeFile: tempFile, inMemory: false);
        await engine1.applyTheme(CustomDashboardTheme.sportRed());

        expect(await tempFile.exists(), isTrue);
        final fileContent = await tempFile.readAsString();
        final savedJson = jsonDecode(fileContent) as Map<String, dynamic>;
        expect(savedJson['id'], equals('sport_track_red'));

        // Second engine points to the saved file and reloads it
        final engine2 = ThemeEngine(customThemeFile: tempFile, inMemory: false);
        await engine2.loadPersistedTheme();

        expect(engine2.currentTheme.id, equals('sport_track_red'));
        expect(engine2.colors.primaryAccent, equals(const Color(0xFFFF3333)));

        // Reset to default should delete persisted file
        await engine2.resetToDefault();
        expect(engine2.currentTheme.id, equals('obdrive_neon_lime'));
        expect(await tempFile.exists(), isFalse);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
