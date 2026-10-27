import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:obdrive/services/settings/app_preferences.dart';

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

/// Centralized troubleshooting logging service for OBDrive.
///
/// Features:
/// - Persisted toggle in [AppPreferences] (Debug / Log collection mode).
/// - Rolling in-memory buffer of recent entries for real-time UI display.
/// - File-based persistent storage (`obdrive_debug.log`) for export and post-mortem analysis.
/// - Automatic rotation/capping to prevent excessive disk consumption on headunits.
/// - Reactive stream for real-time UI log viewer.
class LogService {
  static const int maxMemoryEntries = 1500;
  static const int maxFileSizeBytes = 2 * 1024 * 1024; // 2 MB (reasonable rotation threshold)

  /// Optional override for testing rotation boundaries deterministically.
  static int? maxFileSizeBytesOverride;
  static int get activeMaxFileSizeBytes => maxFileSizeBytesOverride ?? maxFileSizeBytes;

  /// Optional override for testing public mirror directory persistence.
  static Directory? publicMirrorDirOverride;
  static Directory? _cachedMirrorDir;

  static bool _isEnabled = false;
  static bool get isEnabled => _isEnabled;

  static final List<LogEntry> _memoryBuffer = [];
  static final StreamController<LogEntry> _entryStreamController =
      StreamController<LogEntry>.broadcast();

  static File? _cachedLogFile;
  static File? _cachedRotatedLogFile;
  static File? _cachedCrashLogFile;
  static bool _isWriting = false;
  static Completer<void>? _currentWriteCompleter;
  static final List<String> _pendingWriteLines = [];

  /// Stream of new log entries emitted in real-time.
  static Stream<LogEntry> get onNewEntry => _entryStreamController.stream;

  /// Initializes the service from stored user preferences.
  static Future<void> init() async {
    try {
      _isEnabled = await AppPreferences.isDebugLoggingEnabled();
      if (_isEnabled) {
        final mirror = await getPublicOBDriveDirectory();
        final mirrorDesc = mirror != null ? 'mirrored to ${mirror.path}' : 'internal sandbox only';
        i('LogService initialized (debug logging active, $mirrorDesc)', tag: 'System');
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

    // 6. If it's an error, also append immediately to obdrive_crash.log
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

  /// Flushes all pending log lines to disk and mirrors immediately.
  static Future<void> flush() async {
    while (_isWriting || _pendingWriteLines.isNotEmpty) {
      if (!_isWriting && _pendingWriteLines.isNotEmpty) {
        await _flushQueueToFile();
      } else if (_currentWriteCompleter != null && !_currentWriteCompleter!.isCompleted) {
        await _currentWriteCompleter!.future;
      } else {
        break;
      }
    }
  }

  static Future<void> _flushQueueToFile() async {
    if (_isWriting || _pendingWriteLines.isEmpty) return;
    _isWriting = true;
    if (_currentWriteCompleter == null || _currentWriteCompleter!.isCompleted) {
      _currentWriteCompleter = Completer<void>();
    }

    try {
      final file = await getLogFile();
      final batch = List<String>.from(_pendingWriteLines);
      _pendingWriteLines.clear();

      bool needRotate = false;
      if (file.existsSync()) {
        final length = file.lengthSync();
        if (length >= activeMaxFileSizeBytes) {
          needRotate = true;
        }
      }

      if (needRotate) {
        // Rotate primary file: archive current to obdrive_debug.1.log
        final rotatedFile = await getRotatedLogFile();
        try {
          if (rotatedFile.existsSync()) {
            rotatedFile.deleteSync();
          }
          rotatedFile.parent.createSync(recursive: true);
          file.renameSync(rotatedFile.path);
        } catch (_) {
          try {
            file.copySync(rotatedFile.path);
            file.deleteSync();
          } catch (_) {}
        }

        // Fresh primary file with latest batch
        await file.writeAsString(
          '--- LOG ROTATED (archived to obdrive_debug.1.log) ---\n${batch.join('\n')}\n',
          mode: FileMode.write,
          flush: true,
        );
      } else {
        await file.writeAsString(
          '${batch.join('\n')}\n',
          mode: FileMode.append,
          flush: true,
        );
      }

      // Mirror write asynchronously to public downloads directory
      await _mirrorWrite(
        needRotate
            ? ['--- LOG ROTATED (archived to obdrive_debug.1.log) ---', ...batch]
            : batch,
        rotate: needRotate,
      );
    } catch (_) {
      // Ignore file write errors gracefully (e.g. storage permissions or headless tests)
    } finally {
      _isWriting = false;
      if (_pendingWriteLines.isNotEmpty) {
        unawaited(_flushQueueToFile());
      } else {
        if (_currentWriteCompleter != null && !_currentWriteCompleter!.isCompleted) {
          _currentWriteCompleter!.complete();
        }
      }
    }
  }

  /// Mirrors written log batches to the public OBDrive downloads directory.
  static Future<void> _mirrorWrite(List<String> lines, {bool rotate = false}) async {
    try {
      final mirrorDir = await getPublicOBDriveDirectory();
      if (mirrorDir == null) return;

      final mirrorFile = File('${mirrorDir.path}/obdrive_debug.log');
      final mirrorRotated = File('${mirrorDir.path}/obdrive_debug.1.log');

      if (rotate) {
        try {
          if (mirrorRotated.existsSync()) {
            mirrorRotated.deleteSync();
          }
          if (mirrorFile.existsSync()) {
            try {
              mirrorFile.renameSync(mirrorRotated.path);
            } catch (_) {
              mirrorFile.copySync(mirrorRotated.path);
              mirrorFile.deleteSync();
            }
          }
        } catch (_) {}
      }

      await mirrorFile.writeAsString(
        '${lines.join('\n')}\n',
        mode: rotate ? FileMode.write : FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Mirror writes must never throw or disrupt application logging
    }
  }

  static void _appendCrashLog(String formattedLine) {
    unawaited(() async {
      try {
        final crashFile = await getCrashLogFile();
        await crashFile.writeAsString('$formattedLine\n', mode: FileMode.append, flush: true);
      } catch (_) {}

      try {
        final mirrorDir = await getPublicOBDriveDirectory();
        if (mirrorDir != null) {
          final mirrorCrashFile = File('${mirrorDir.path}/obdrive_crash.log');
          await mirrorCrashFile.writeAsString('$formattedLine\n', mode: FileMode.append, flush: true);
        }
      } catch (_) {}
    }());
  }

  /// Resolves the public, user-accessible directory for mirrored logs.
  /// On Android: `/storage/emulated/0/Download/OBDrive` (or `/storage/emulated/0/OBDrive`).
  /// On Desktop/Linux: `$HOME/Downloads/OBDrive`.
  static Future<Directory?> getPublicOBDriveDirectory() async {
    if (publicMirrorDirOverride != null) {
      return publicMirrorDirOverride;
    }
    if (_cachedMirrorDir != null && _cachedMirrorDir!.existsSync()) {
      return _cachedMirrorDir;
    }

    if (Platform.isAndroid) {
      const publicCandidates = <String>[
        '/storage/emulated/0/Download/OBDrive',
        '/storage/emulated/0/OBDrive',
      ];

      for (final path in publicCandidates) {
        try {
          final dir = Directory(path);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          final probe = File('${dir.path}/.probe_${DateTime.now().millisecondsSinceEpoch}');
          probe.writeAsStringSync('ok', flush: true);
          probe.deleteSync();
          _cachedMirrorDir = dir;
          return dir;
        } catch (_) {
          // Candidate not writable, proceed to next
        }
      }

      // Fallback: app-specific external storage which does not require WRITE_EXTERNAL_STORAGE
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final fallbackDir = Directory('${extDir.path}/OBDrive');
          if (!fallbackDir.existsSync()) {
            fallbackDir.createSync(recursive: true);
          }
          _cachedMirrorDir = fallbackDir;
          return fallbackDir;
        }
      } catch (_) {}
    } else {
      // Desktop / Linux / macOS
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        try {
          final dir = Directory('$home/Downloads/OBDrive');
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          _cachedMirrorDir = dir;
          return dir;
        } catch (_) {}
      }
    }

    return null;
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

    _cachedCrashLogFile = File('${dir.path}/obdrive_crash.log');
    return _cachedCrashLogFile!;
  }

  /// Returns the target active log file on disk.
  static Future<File> getLogFile() async {
    if (_cachedLogFile != null) return _cachedLogFile!;

    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }

    _cachedLogFile = File('${dir.path}/obdrive_debug.log');
    return _cachedLogFile!;
  }

  /// Returns the rotated archive log file on disk.
  static Future<File> getRotatedLogFile() async {
    if (_cachedRotatedLogFile != null) return _cachedRotatedLogFile!;

    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }

    _cachedRotatedLogFile = File('${dir.path}/obdrive_debug.1.log');
    return _cachedRotatedLogFile!;
  }

  /// Returns the current total size of all active and rotated log files on disk in bytes.
  static Future<int> getLogFileSize() async {
    int total = 0;
    try {
      final file = await getLogFile();
      if (file.existsSync()) {
        total += file.lengthSync();
      }
      final rotated = await getRotatedLogFile();
      if (rotated.existsSync()) {
        total += rotated.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  /// Clears in-memory buffer and resets all log files on disk and in the mirror directory.
  static Future<void> clearLogs() async {
    _memoryBuffer.clear();
    _pendingWriteLines.clear();
    try {
      final file = await getLogFile();
      if (file.existsSync()) {
        file.deleteSync();
      }
      final rotated = await getRotatedLogFile();
      if (rotated.existsSync()) {
        rotated.deleteSync();
      }
      final crashFile = await getCrashLogFile();
      if (crashFile.existsSync()) {
        crashFile.deleteSync();
      }

      // Also clean public mirror files
      final mirrorDir = await getPublicOBDriveDirectory();
      if (mirrorDir != null) {
        final mirrorLog = File('${mirrorDir.path}/obdrive_debug.log');
        if (mirrorLog.existsSync()) mirrorLog.deleteSync();
        final mirrorRotated = File('${mirrorDir.path}/obdrive_debug.1.log');
        if (mirrorRotated.existsSync()) mirrorRotated.deleteSync();
        final mirrorCrash = File('${mirrorDir.path}/obdrive_crash.log');
        if (mirrorCrash.existsSync()) mirrorCrash.deleteSync();
      }
    } catch (_) {}
    i('Logs cleared by user', tag: 'System');
  }

  /// Returns all currently stored memory log entries.
  static List<LogEntry> getEntries() {
    return List<LogEntry>.unmodifiable(_memoryBuffer);
  }

  /// Returns full log contents as a single formatted string for copying or exporting.
  /// Combines critical crash logs, rotated archive history, and active session logs.
  static Future<String> exportLogs() async {
    final buffer = StringBuffer();
    try {
      final crashFile = await getCrashLogFile();
      if (crashFile.existsSync()) {
        final crashContent = await crashFile.readAsString();
        if (crashContent.trim().isNotEmpty) {
          buffer.writeln('=== CRITICAL / CRASH LOGS ===');
          buffer.writeln(crashContent.trim());
          buffer.writeln('===============================\n');
        }
      }
    } catch (_) {}

    // Flush any pending entries before reading disk logs
    await flush();

    bool readFromDisk = false;
    try {
      final rotatedFile = await getRotatedLogFile();
      if (rotatedFile.existsSync()) {
        final rotatedContent = await rotatedFile.readAsString();
        if (rotatedContent.trim().isNotEmpty) {
          buffer.writeln('=== ARCHIVED LOGS (obdrive_debug.1.log) ===');
          buffer.writeln(rotatedContent.trim());
          buffer.writeln('===========================================\n');
          readFromDisk = true;
        }
      }

      final file = await getLogFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          buffer.writeln(content.trim());
          readFromDisk = true;
        }
      }
    } catch (_) {}

    if (readFromDisk) {
      return buffer.toString().trim();
    }

    // Fallback to memory buffer if disk was unavailable or empty
    if (_memoryBuffer.isNotEmpty) {
      buffer.writeln(_memoryBuffer.map((e) => e.formatted).join('\n'));
      return buffer.toString().trim();
    }

    if (buffer.isNotEmpty) {
      return buffer.toString().trim();
    }
    return 'No logs collected yet.';
  }
}
