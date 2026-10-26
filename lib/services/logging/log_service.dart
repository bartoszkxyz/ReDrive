import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:redrive/services/settings/app_preferences.dart';

/// Severity level for troubleshooting logs.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// A structured troubleshooting log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get levelLabel {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String get formatted {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    final timeStr = '$y-$m-$d $hh:$mm:$ss.$ms';

    final errStr = error != null ? ' | Error: $error' : '';
    final stackStr = stackTrace != null ? '\n$stackTrace' : '';

    return '$timeStr [$levelLabel] [$tag] $message$errStr$stackStr';
  }

  @override
  String toString() => formatted;
}

/// Centralized troubleshooting logging service for ReDrive.
///
/// Features:
/// - Persisted toggle in [AppPreferences] (Debug / Log collection mode).
/// - Rolling in-memory buffer of recent entries for real-time UI display.
/// - File-based persistent storage (`redrive_debug.log`) for export and post-mortem analysis.
/// - Automatic rotation/capping to prevent excessive disk consumption on headunits.
/// - Reactive stream for real-time UI log viewer.
class LogService {
  static const int maxMemoryEntries = 1500;
  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  static bool _isEnabled = false;
  static bool get isEnabled => _isEnabled;

  static final List<LogEntry> _memoryBuffer = [];
  static final StreamController<LogEntry> _entryStreamController =
      StreamController<LogEntry>.broadcast();

  static File? _cachedLogFile;
  static bool _isWriting = false;
  static final List<String> _pendingWriteLines = [];

  /// Stream of new log entries emitted in real-time.
  static Stream<LogEntry> get onNewEntry => _entryStreamController.stream;

  /// Initializes the service from stored user preferences.
  static Future<void> init() async {
    try {
      _isEnabled = await AppPreferences.isDebugLoggingEnabled();
      if (_isEnabled) {
        i('LogService initialized (debug logging active)', tag: 'System');
      }
    } catch (_) {
      _isEnabled = false;
    }
  }

  /// Sets whether debug/troubleshooting log collection is active.
  static Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    try {
      await AppPreferences.setDebugLoggingEnabled(enabled);
    } catch (_) {}

    if (enabled) {
      i('Debug logging ENABLED by user', tag: 'System');
    } else {
      i('Debug logging DISABLED by user', tag: 'System');
    }
  }

  /// Logs a message at [LogLevel.debug].
  static void d(String message, {String tag = 'App', Object? error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.debug, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Logs a message at [LogLevel.info].
  static void i(String message, {String tag = 'App', Object? error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.info, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Logs a message at [LogLevel.warning].
  static void w(String message, {String tag = 'App', Object? error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.warning, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Logs a message at [LogLevel.error].
  static void e(String message, {String tag = 'App', Object? error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.error, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Main log dispatch method.
  static void log(
    String message, {
    LogLevel level = LogLevel.info,
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    // 1. Forward to Dart developer log for IDE / logcat visibility
    developer.log(
      message,
      name: tag,
      error: error,
      stackTrace: stackTrace,
      level: _toDeveloperLogLevel(level),
    );

    // 2. Always capture warnings, errors, and fatal exceptions, even if verbose debug logging is disabled.
    // Verbose debug and info messages are only captured when _isEnabled is true.
    final bool isCritical = level == LogLevel.warning || level == LogLevel.error;
    if (!_isEnabled && !isCritical) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    // 3. Add to memory buffer
    _memoryBuffer.add(entry);
    if (_memoryBuffer.length > maxMemoryEntries) {
      _memoryBuffer.removeRange(0, _memoryBuffer.length - maxMemoryEntries);
    }

    // 4. Notify live stream listeners
    if (_entryStreamController.hasListener) {
      _entryStreamController.add(entry);
    }

    // 5. Queue for background file write
    _queueFileLine(entry.formatted);

    // 6. If it's an error, also append immediately to redrive_crash.log
    if (level == LogLevel.error) {
      _appendCrashLog(entry.formatted);
    }
  }

  static int _toDeveloperLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }

  static void _queueFileLine(String line) {
    _pendingWriteLines.add(line);
    if (!_isWriting) {
      _flushQueueToFile();
    }
  }

  static Future<void> _flushQueueToFile() async {
    if (_isWriting || _pendingWriteLines.isEmpty) return;
    _isWriting = true;

    try {
      final file = await getLogFile();
      final batch = List<String>.from(_pendingWriteLines);
      _pendingWriteLines.clear();

      // Check file size before appending
      if (await file.exists()) {
        final length = await file.length();
        if (length > maxFileSizeBytes) {
          // Truncate/rotate file: overwrite with latest batch
          await file.writeAsString(
            '--- LOG ROTATED (size exceeded 5MB) ---\n${batch.join('\n')}\n',
            mode: FileMode.write,
            flush: true,
          );
          _isWriting = false;
          if (_pendingWriteLines.isNotEmpty) {
            unawaited(_flushQueueToFile());
          }
          return;
        }
      }

      await file.writeAsString(
        '${batch.join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Ignore file write errors gracefully (e.g. storage permissions or headless tests)
    } finally {
      _isWriting = false;
      if (_pendingWriteLines.isNotEmpty) {
        unawaited(_flushQueueToFile());
      }
    }
  }

  static File? _cachedCrashLogFile;

  static void _appendCrashLog(String formattedLine) {
    unawaited(() async {
      try {
        final crashFile = await getCrashLogFile();
        await crashFile.writeAsString('$formattedLine\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    }());
  }

  /// Returns the persistent crash log file on disk.
  static Future<File> getCrashLogFile() async {
    if (_cachedCrashLogFile != null) return _cachedCrashLogFile!;

    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }

    _cachedCrashLogFile = File('${dir.path}/redrive_crash.log');
    return _cachedCrashLogFile!;
  }

  /// Returns the target log file on disk.
  static Future<File> getLogFile() async {
    if (_cachedLogFile != null) return _cachedLogFile!;

    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }

    _cachedLogFile = File('${dir.path}/redrive_debug.log');
    return _cachedLogFile!;
  }

  /// Returns the current size of the log file on disk in bytes.
  static Future<int> getLogFileSize() async {
    try {
      final file = await getLogFile();
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Clears in-memory buffer and resets the log file on disk.
  static Future<void> clearLogs() async {
    _memoryBuffer.clear();
    _pendingWriteLines.clear();
    try {
      final file = await getLogFile();
      if (await file.exists()) {
        await file.delete();
      }
      final crashFile = await getCrashLogFile();
      if (await crashFile.exists()) {
        await crashFile.delete();
      }
    } catch (_) {}
    i('Logs cleared by user', tag: 'System');
  }

  /// Returns all currently stored memory log entries.
  static List<LogEntry> getEntries() {
    return List<LogEntry>.unmodifiable(_memoryBuffer);
  }

  /// Returns full log contents as a single formatted string for copying or exporting.
  static Future<String> exportLogs() async {
    final buffer = StringBuffer();
    try {
      final crashFile = await getCrashLogFile();
      if (await crashFile.exists()) {
        final crashContent = await crashFile.readAsString();
        if (crashContent.trim().isNotEmpty) {
          buffer.writeln('=== CRITICAL / CRASH LOGS ===');
          buffer.writeln(crashContent.trim());
          buffer.writeln('===============================\n');
        }
      }
    } catch (_) {}

    // If memory buffer has entries, it always contains the most up-to-date log session
    if (_memoryBuffer.isNotEmpty) {
      buffer.writeln(_memoryBuffer.map((e) => e.formatted).join('\n'));
      return buffer.toString().trim();
    }

    try {
      final file = await getLogFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          buffer.writeln(content.trim());
          return buffer.toString().trim();
        }
      }
    } catch (_) {}

    if (buffer.isNotEmpty) {
      return buffer.toString().trim();
    }
    return 'No logs collected yet.';
  }
}
