/// Application flavor enumeration and global configuration for ReDrive.
///
/// Distinguishes between:
/// - [AppFlavor.headunit]: The primary in-car launcher target (landscape-first,
///   background service, OBD2 polling, launcher intents).
/// - [AppFlavor.phone]: The companion app target (portrait-first, Bluetooth sync
///   client, map overlays, garage management).
enum AppFlavor {
  headunit,
  phone;

  bool get isHeadunit => this == AppFlavor.headunit;
  bool get isPhone => this == AppFlavor.phone;

  /// Helper to map build flavor string (e.g. from `package:flutter/services.dart`)
  /// to an [AppFlavor], defaulting to [AppFlavor.headunit] if null or unrecognized.
  static AppFlavor fromString(String? name) {
    if (name?.toLowerCase() == 'phone') {
      return AppFlavor.phone;
    }
    return AppFlavor.headunit;
  }
}

/// Global application configuration singleton.
class AppConfig {
  final AppFlavor flavor;
  final String appTitle;

  const AppConfig({
    required this.flavor,
    required this.appTitle,
  });

  static AppConfig? _instance;

  /// Current active configuration, defaulting to [AppFlavor.headunit] if not initialized.
  static AppConfig get current =>
      _instance ??
      const AppConfig(
        flavor: AppFlavor.headunit,
        appTitle: 'OBDrive Headunit',
      );

  /// Initializes the singleton configuration.
  static void initialize({
    required AppFlavor flavor,
    String? appTitle,
  }) {
    _instance = AppConfig(
      flavor: flavor,
      appTitle: appTitle ?? (flavor.isPhone ? 'OBDrive' : 'OBDrive Headunit'),
    );
  }

  /// Resets the configuration back to uninitialized state (useful for test isolation).
  static void reset() {
    _instance = null;
  }

  /// Convenience getter checking if current flavor is [AppFlavor.headunit].
  static bool get isHeadunit => current.flavor.isHeadunit;

  /// Convenience getter checking if current flavor is [AppFlavor.phone].
  static bool get isPhone => current.flavor.isPhone;
}
