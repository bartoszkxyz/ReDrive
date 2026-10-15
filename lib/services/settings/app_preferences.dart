import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized service for persisting app & hardware configuration
/// such as the last connected OBD2 adapter and vehicle specs (e.g. Suzuki Swift M15A).
class AppPreferences {
  static const String _keyLastObdMac = 'last_obd_mac';
  static const String _keyLastObdName = 'last_obd_name';
  static const String _keyAutoConnect = 'auto_connect_enabled';
  static const String _keyAutoTrip = 'auto_trip_enabled';
  static const String _keyDisplacement = 'engine_displacement_liters';
  static const String _keyMinTripDistance = 'min_trip_distance_km';
  static const String _keyDebugLogging = 'debug_logging_enabled';
  static const String _keyAutoLaunchOnBoot = 'auto_launch_on_boot';
  static const String _keyLastBootAction = 'last_boot_action';
  static const String _keyLastBootTimestamp = 'last_boot_timestamp';

  static SharedPreferences? _prefs;

  /// Drops the cached [SharedPreferences] instance so tests that call
  /// `SharedPreferences.setMockInitialValues` start from true defaults.
  @visibleForTesting
  static void resetCacheForTesting() => _prefs = null;

  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Returns the MAC address of the last connected OBD Bluetooth device.
  static Future<String?> getLastObdMac() async {
    final prefs = await _instance;
    return prefs.getString(_keyLastObdMac);
  }

  /// Returns the display name of the last connected OBD Bluetooth device.
  static Future<String?> getLastObdName() async {
    final prefs = await _instance;
    return prefs.getString(_keyLastObdName);
  }

  /// Persists the last connected OBD device info.
  static Future<void> saveLastConnectedDevice({
    required String mac,
    String? name,
  }) async {
    final prefs = await _instance;
    await prefs.setString(_keyLastObdMac, mac);
    if (name != null) {
      await prefs.setString(_keyLastObdName, name);
    }
  }

  /// Whether the app/service should automatically attempt to connect to the last device.
  static Future<bool> isAutoConnectEnabled() async {
    final prefs = await _instance;
    return prefs.getBool(_keyAutoConnect) ?? true;
  }

  static Future<void> setAutoConnectEnabled(bool enabled) async {
    final prefs = await _instance;
    await prefs.setBool(_keyAutoConnect, enabled);
  }

  /// Whether trips should start automatically when engine runs (RPM > 400).
  static Future<bool> isAutoTripEnabled() async {
    final prefs = await _instance;
    return prefs.getBool(_keyAutoTrip) ?? true;
  }

  static Future<void> setAutoTripEnabled(bool enabled) async {
    final prefs = await _instance;
    await prefs.setBool(_keyAutoTrip, enabled);
  }

  /// Configured engine displacement in liters (defaults to 1.5 for Suzuki Swift M15A).
  static Future<double> getEngineDisplacement() async {
    final prefs = await _instance;
    return prefs.getDouble(_keyDisplacement) ?? 1.5;
  }

  static Future<void> setEngineDisplacement(double displacement) async {
    final prefs = await _instance;
    await prefs.setDouble(_keyDisplacement, displacement);
  }

  /// Minimum trip distance in kilometers required to save to history.
  /// Defaults to 0.1 km (allows short urban trips and test sequences to persist).
  static Future<double> getMinTripDistanceKm() async {
    final prefs = await _instance;
    return prefs.getDouble(_keyMinTripDistance) ?? 0.1;
  }

  static Future<void> setMinTripDistanceKm(double km) async {
    final prefs = await _instance;
    await prefs.setDouble(_keyMinTripDistance, km);
  }

  /// Whether diagnostic debug logging is enabled for troubleshooting.
  static Future<bool> isDebugLoggingEnabled() async {
    final prefs = await _instance;
    return prefs.getBool(_keyDebugLogging) ?? false;
  }

  static Future<void> setDebugLoggingEnabled(bool enabled) async {
    final prefs = await _instance;
    await prefs.setBool(_keyDebugLogging, enabled);
  }

  /// Whether ReDrive automatically brings its UI to the front on ignition (false = silent background start).
  static Future<bool> isAutoLaunchOnBootEnabled() async {
    final prefs = await _instance;
    return prefs.getBool(_keyAutoLaunchOnBoot) ?? false;
  }

  static Future<void> setAutoLaunchOnBootEnabled(bool enabled) async {
    final prefs = await _instance;
    await prefs.setBool(_keyAutoLaunchOnBoot, enabled);
  }

  /// The last automotive broadcast intent caught by HeadunitBootReceiver.
  static Future<String?> getLastBootAction() async {
    final prefs = await _instance;
    return prefs.getString(_keyLastBootAction);
  }

  /// The timestamp of the last automotive broadcast intent caught by HeadunitBootReceiver.
  static Future<String?> getLastBootTimestamp() async {
    final prefs = await _instance;
    return prefs.getString(_keyLastBootTimestamp);
  }
}
