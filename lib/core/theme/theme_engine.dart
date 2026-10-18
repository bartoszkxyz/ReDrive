import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'custom_dashboard_theme.dart';

/// Theme management and sideloading engine for OBDrive and Headunit Launcher.
/// Supports in-memory fast mode, hot reloading, JSON sideloading, and persistence.
class ThemeEngine extends ChangeNotifier {
  final File? customThemeFile;
  final bool inMemory;

  CustomDashboardTheme _currentTheme = CustomDashboardTheme.defaultTheme();
  Future<void>? _initFuture;

  CustomDashboardTheme get currentTheme => _currentTheme;
  CustomThemeColors get colors => _currentTheme.colors;
  CustomGaugeStyle get gaugeStyle => _currentTheme.gaugeStyle;
  ThemeData get materialTheme => _currentTheme.toMaterialTheme();
  Future<void>? get initFuture => _initFuture;

  ThemeEngine({
    this.customThemeFile,
    this.inMemory = false,
  }) {
    if (!inMemory) {
      _initFuture = _loadPersistedTheme();
    }
  }

  Future<File?> _getThemeFile() async {
    if (customThemeFile != null) return customThemeFile;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/active_theme.json');
    } catch (_) {
      return null;
    }
  }

  /// Public accessor for testing or manual reloads of the persisted theme file.
  Future<void> loadPersistedTheme() => _loadPersistedTheme();

  Future<void> _loadPersistedTheme() async {
    try {
      final file = await _getThemeFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          await applyTheme(CustomDashboardTheme.fromJson(decoded), persist: false);
        } else if (decoded is Map) {
          await applyTheme(
            CustomDashboardTheme.fromJson(Map<String, dynamic>.from(decoded)),
            persist: false,
          );
        }
      }
    } catch (_) {
      // Gracefully ignore corrupt or unreadable files.
    }
  }

  /// Applies a new dashboard theme and optionally persists it to disk.
  Future<void> applyTheme(CustomDashboardTheme theme, {bool persist = true}) async {
    _currentTheme = theme;
    if (persist && !inMemory) {
      try {
        final file = await _getThemeFile();
        if (file != null) {
          if (!await file.parent.exists()) {
            await file.parent.create(recursive: true);
          }
          await file.writeAsString(jsonEncode(theme.toJson()));
        }
      } catch (_) {
        // Fallback gracefully if writing fails.
      }
    }
    notifyListeners();
  }

  /// Resets the active theme to OBDrive Neon Lime default and removes persisted configuration.
  Future<void> resetToDefault() async {
    await applyTheme(CustomDashboardTheme.defaultTheme(), persist: false);
    if (!inMemory) {
      try {
        final file = await _getThemeFile();
        if (file != null && await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore deletion failures.
      }
    }
  }

  /// Parses raw theme JSON string and applies the imported theme.
  /// Returns `true` on success, or `false` on malformed JSON without throwing.
  Future<bool> importThemeFromJsonString(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        return false;
      }
      final Map<String, dynamic> map = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded);
      final theme = CustomDashboardTheme.fromJson(map);
      await applyTheme(theme);
      return true;
    } catch (_) {
      return false;
    }
  }
}
