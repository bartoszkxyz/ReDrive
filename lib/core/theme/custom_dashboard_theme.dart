import 'package:flutter/material.dart';

/// Needle visual style for dashboard gauges.
enum GaugeNeedleStyle {
  solidBlade,
  sweepingLine,
  digitalArcOnly,
}

/// Palette and status indicators for custom dashboard rendering.
class CustomThemeColors {
  final Color background;
  final Color surfaceCard;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color textMain;
  final Color textMuted;
  final Color coolantNormal;
  final Color coolantWarning;
  final Color coolantOverheat;
  final Color engineLoadLow;
  final Color engineLoadMedium;
  final Color engineLoadHigh;
  final Color fuelFlowBarStart;
  final Color fuelFlowBarEnd;

  const CustomThemeColors({
    this.background = const Color(0xFF070709),
    this.surfaceCard = const Color(0xFF13151B),
    this.primaryAccent = const Color(0xFFBDF343),
    this.secondaryAccent = const Color(0xFF00E5FF),
    this.textMain = Colors.white,
    this.textMuted = const Color(0xFF8A90A2),
    this.coolantNormal = const Color(0xFF00E676),
    this.coolantWarning = const Color(0xFFFFB300),
    this.coolantOverheat = const Color(0xFFFF1744),
    this.engineLoadLow = const Color(0xFF00E676),
    this.engineLoadMedium = const Color(0xFFFFB300),
    this.engineLoadHigh = const Color(0xFFFF1744),
    this.fuelFlowBarStart = const Color(0xFF00E676),
    this.fuelFlowBarEnd = const Color(0xFFFF5252),
  });

  /// Safe hex color parser handling `#RGB`, `#ARGB`, `#RRGGBB`, `#AARRGGBB`,
  /// optional `#` or `0x` prefixes, and gracefully falling back on errors.
  static Color parseColor(dynamic val, Color fallback) => _parseColor(val, fallback);

  static Color _parseColor(dynamic val, Color fallback) {
    if (val == null) return fallback;
    if (val is int) return Color(val);
    if (val is! String) return fallback;

    String hex = val.trim();
    if (hex.isEmpty) return fallback;

    if (hex.startsWith('#')) {
      hex = hex.substring(1).trim();
    } else if (hex.toLowerCase().startsWith('0x')) {
      hex = hex.substring(2).trim();
    }

    if (hex.length == 3) {
      // #RGB -> #FFRRGGBB
      hex = 'FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
    } else if (hex.length == 4) {
      // #ARGB -> #AARRGGBB
      hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}';
    } else if (hex.length == 6) {
      // #RRGGBB -> #FFRRGGBB
      hex = 'FF$hex';
    } else if (hex.length == 8) {
      // #AARRGGBB
    } else {
      return fallback;
    }

    final intVal = int.tryParse(hex, radix: 16);
    if (intVal == null) return fallback;
    return Color(intVal);
  }

  /// Safe hex formatting helper.
  static String toHex(Color c) => _toHex(c);

  static String _toHex(Color c) {
    return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  Map<String, dynamic> toJson() => {
    'background': _toHex(background),
    'surfaceCard': _toHex(surfaceCard),
    'primaryAccent': _toHex(primaryAccent),
    'secondaryAccent': _toHex(secondaryAccent),
    'textMain': _toHex(textMain),
    'textMuted': _toHex(textMuted),
    'coolantNormal': _toHex(coolantNormal),
    'coolantWarning': _toHex(coolantWarning),
    'coolantOverheat': _toHex(coolantOverheat),
    'engineLoadLow': _toHex(engineLoadLow),
    'engineLoadMedium': _toHex(engineLoadMedium),
    'engineLoadHigh': _toHex(engineLoadHigh),
    'fuelFlowBarStart': _toHex(fuelFlowBarStart),
    'fuelFlowBarEnd': _toHex(fuelFlowBarEnd),
  };

  factory CustomThemeColors.fromJson(Map<String, dynamic> json) {
    const defaults = CustomThemeColors();
    return CustomThemeColors(
      background: _parseColor(json['background'], defaults.background),
      surfaceCard: _parseColor(json['surfaceCard'], defaults.surfaceCard),
      primaryAccent: _parseColor(json['primaryAccent'], defaults.primaryAccent),
      secondaryAccent: _parseColor(json['secondaryAccent'], defaults.secondaryAccent),
      textMain: _parseColor(json['textMain'], defaults.textMain),
      textMuted: _parseColor(json['textMuted'], defaults.textMuted),
      coolantNormal: _parseColor(json['coolantNormal'], defaults.coolantNormal),
      coolantWarning: _parseColor(json['coolantWarning'], defaults.coolantWarning),
      coolantOverheat: _parseColor(json['coolantOverheat'], defaults.coolantOverheat),
      engineLoadLow: _parseColor(json['engineLoadLow'], defaults.engineLoadLow),
      engineLoadMedium: _parseColor(json['engineLoadMedium'], defaults.engineLoadMedium),
      engineLoadHigh: _parseColor(json['engineLoadHigh'], defaults.engineLoadHigh),
      fuelFlowBarStart: _parseColor(json['fuelFlowBarStart'], defaults.fuelFlowBarStart),
      fuelFlowBarEnd: _parseColor(json['fuelFlowBarEnd'], defaults.fuelFlowBarEnd),
    );
  }

  CustomThemeColors copyWith({
    Color? background,
    Color? surfaceCard,
    Color? primaryAccent,
    Color? secondaryAccent,
    Color? textMain,
    Color? textMuted,
    Color? coolantNormal,
    Color? coolantWarning,
    Color? coolantOverheat,
    Color? engineLoadLow,
    Color? engineLoadMedium,
    Color? engineLoadHigh,
    Color? fuelFlowBarStart,
    Color? fuelFlowBarEnd,
  }) {
    return CustomThemeColors(
      background: background ?? this.background,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      textMain: textMain ?? this.textMain,
      textMuted: textMuted ?? this.textMuted,
      coolantNormal: coolantNormal ?? this.coolantNormal,
      coolantWarning: coolantWarning ?? this.coolantWarning,
      coolantOverheat: coolantOverheat ?? this.coolantOverheat,
      engineLoadLow: engineLoadLow ?? this.engineLoadLow,
      engineLoadMedium: engineLoadMedium ?? this.engineLoadMedium,
      engineLoadHigh: engineLoadHigh ?? this.engineLoadHigh,
      fuelFlowBarStart: fuelFlowBarStart ?? this.fuelFlowBarStart,
      fuelFlowBarEnd: fuelFlowBarEnd ?? this.fuelFlowBarEnd,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomThemeColors &&
          runtimeType == other.runtimeType &&
          background == other.background &&
          surfaceCard == other.surfaceCard &&
          primaryAccent == other.primaryAccent &&
          secondaryAccent == other.secondaryAccent &&
          textMain == other.textMain &&
          textMuted == other.textMuted &&
          coolantNormal == other.coolantNormal &&
          coolantWarning == other.coolantWarning &&
          coolantOverheat == other.coolantOverheat &&
          engineLoadLow == other.engineLoadLow &&
          engineLoadMedium == other.engineLoadMedium &&
          engineLoadHigh == other.engineLoadHigh &&
          fuelFlowBarStart == other.fuelFlowBarStart &&
          fuelFlowBarEnd == other.fuelFlowBarEnd;

  @override
  int get hashCode => Object.hash(
        background,
        surfaceCard,
        primaryAccent,
        secondaryAccent,
        textMain,
        textMuted,
        coolantNormal,
        coolantWarning,
        coolantOverheat,
        engineLoadLow,
        engineLoadMedium,
        engineLoadHigh,
        fuelFlowBarStart,
        fuelFlowBarEnd,
      );
}

/// Gauge drawing parameters and needle style.
class CustomGaugeStyle {
  final GaugeNeedleStyle needleStyle;
  final double arcThickness;
  final double glowIntensity;
  final bool showTicks;

  const CustomGaugeStyle({
    this.needleStyle = GaugeNeedleStyle.solidBlade,
    this.arcThickness = 8.0,
    this.glowIntensity = 0.3,
    this.showTicks = true,
  });

  Map<String, dynamic> toJson() => {
    'needleStyle': needleStyle.name,
    'arcThickness': arcThickness,
    'glowIntensity': glowIntensity,
    'showTicks': showTicks,
  };

  factory CustomGaugeStyle.fromJson(Map<String, dynamic> json) {
    final needleStr = json['needleStyle']?.toString();
    final needleStyle = GaugeNeedleStyle.values.firstWhere(
      (e) => e.name.toLowerCase() == needleStr?.toLowerCase(),
      orElse: () => GaugeNeedleStyle.solidBlade,
    );
    return CustomGaugeStyle(
      needleStyle: needleStyle,
      arcThickness: (json['arcThickness'] as num?)?.toDouble() ?? 8.0,
      glowIntensity: (json['glowIntensity'] as num?)?.toDouble() ?? 0.3,
      showTicks: json['showTicks'] is bool ? json['showTicks'] as bool : true,
    );
  }

  CustomGaugeStyle copyWith({
    GaugeNeedleStyle? needleStyle,
    double? arcThickness,
    double? glowIntensity,
    bool? showTicks,
  }) {
    return CustomGaugeStyle(
      needleStyle: needleStyle ?? this.needleStyle,
      arcThickness: arcThickness ?? this.arcThickness,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      showTicks: showTicks ?? this.showTicks,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomGaugeStyle &&
          runtimeType == other.runtimeType &&
          needleStyle == other.needleStyle &&
          arcThickness == other.arcThickness &&
          glowIntensity == other.glowIntensity &&
          showTicks == other.showTicks;

  @override
  int get hashCode => Object.hash(needleStyle, arcThickness, glowIntensity, showTicks);
}

/// Complete dashboard theme definition with color palette, gauge configuration,
/// and Material 3 theme mapping.
class CustomDashboardTheme {
  final String id;
  final String name;
  final String author;
  final String version;
  final CustomThemeColors colors;
  final CustomGaugeStyle gaugeStyle;

  const CustomDashboardTheme({
    required this.id,
    required this.name,
    this.author = 'ReDrive',
    this.version = '1.0',
    this.colors = const CustomThemeColors(),
    this.gaugeStyle = const CustomGaugeStyle(),
  });

  /// Factory default returning high-contrast OBDrive Neon Lime theme.
  factory CustomDashboardTheme.defaultTheme() => const CustomDashboardTheme(
    id: 'obdrive_neon_lime',
    name: 'OBDrive Neon Lime',
    author: 'ReDrive',
    version: '1.0',
    colors: CustomThemeColors(),
    gaugeStyle: CustomGaugeStyle(),
  );

  /// Sport Track Red preset (Suzuki Sport Redline).
  factory CustomDashboardTheme.sportRed() => const CustomDashboardTheme(
    id: 'sport_track_red',
    name: 'Suzuki Sport Redline',
    author: 'ReDrive',
    version: '1.0',
    colors: CustomThemeColors(
      primaryAccent: Color(0xFFFF3333),
      secondaryAccent: Color(0xFFFFB800),
      fuelFlowBarEnd: Color(0xFFFF3333),
    ),
    gaugeStyle: CustomGaugeStyle(
      needleStyle: GaugeNeedleStyle.sweepingLine,
      arcThickness: 8.0,
      glowIntensity: 0.4,
      showTicks: true,
    ),
  );

  /// Stealth OLED Minimal preset (Pitch black background with silver/white accents).
  factory CustomDashboardTheme.stealthOled() => const CustomDashboardTheme(
    id: 'stealth_oled',
    name: 'Stealth OLED Minimal',
    author: 'ReDrive',
    version: '1.0',
    colors: CustomThemeColors(
      background: Color(0xFF000000),
      surfaceCard: Color(0xFF0D0D0E),
      primaryAccent: Color(0xFFE0E6ED),
      secondaryAccent: Color(0xFF8A90A2),
    ),
    gaugeStyle: CustomGaugeStyle(
      needleStyle: GaugeNeedleStyle.digitalArcOnly,
      arcThickness: 6.0,
      glowIntensity: 0.1,
      showTicks: false,
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'version': version,
    'colors': colors.toJson(),
    'gaugeStyle': gaugeStyle.toJson(),
  };

  factory CustomDashboardTheme.fromJson(Map<String, dynamic> json) {
    return CustomDashboardTheme(
      id: json['id'] as String? ?? 'custom_theme',
      name: json['name'] as String? ?? 'Custom Theme',
      author: json['author'] as String? ?? 'Unknown',
      version: json['version'] as String? ?? '1.0',
      colors: json['colors'] is Map<String, dynamic>
          ? CustomThemeColors.fromJson(json['colors'] as Map<String, dynamic>)
          : (json['colors'] is Map
              ? CustomThemeColors.fromJson(Map<String, dynamic>.from(json['colors'] as Map))
              : const CustomThemeColors()),
      gaugeStyle: json['gaugeStyle'] is Map<String, dynamic>
          ? CustomGaugeStyle.fromJson(json['gaugeStyle'] as Map<String, dynamic>)
          : (json['gaugeStyle'] is Map
              ? CustomGaugeStyle.fromJson(Map<String, dynamic>.from(json['gaugeStyle'] as Map))
              : const CustomGaugeStyle()),
    );
  }

  /// Converts this custom dashboard theme to a modern Material 3 dark ThemeData.
  ThemeData toMaterialTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.background,
      cardColor: colors.surfaceCard,
      colorScheme: ColorScheme.dark(
        primary: colors.primaryAccent,
        onPrimary: Colors.black,
        secondary: colors.secondaryAccent,
        onSecondary: Colors.black,
        surface: colors.background,
        surfaceContainer: colors.surfaceCard,
        onSurface: colors.textMain,
        onSurfaceVariant: colors.textMuted,
        outline: colors.textMuted.withValues(alpha: 0.3),
        outlineVariant: colors.textMuted.withValues(alpha: 0.15),
      ),
    );
  }

  CustomDashboardTheme copyWith({
    String? id,
    String? name,
    String? author,
    String? version,
    CustomThemeColors? colors,
    CustomGaugeStyle? gaugeStyle,
  }) {
    return CustomDashboardTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      version: version ?? this.version,
      colors: colors ?? this.colors,
      gaugeStyle: gaugeStyle ?? this.gaugeStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomDashboardTheme &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          author == other.author &&
          version == other.version &&
          colors == other.colors &&
          gaugeStyle == other.gaugeStyle;

  @override
  int get hashCode => Object.hash(id, name, author, version, colors, gaugeStyle);
}
