import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/logging/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempMirrorDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempMirrorDir = await Directory.systemTemp.createTemp('redrive_mirror_test_');
    LogService.publicMirrorDirOverride = tempMirrorDir;
    LogService.maxFileSizeBytesOverride = null;
    await LogService.init();
    await LogService.clearLogs();
  });

  tearDown(() async {
    LogService.publicMirrorDirOverride = null;
    LogService.maxFileSizeBytesOverride = null;
    if (await tempMirrorDir.exists()) {
      await tempMirrorDir.delete(recursive: true);
    }
  });

  group('LogService Tests', () {
    test('init sets disabled by default', () {
      expect(LogService.isEnabled, isFalse);
      expect(LogService.getEntries(), isEmpty);
    });

    test('logs are not buffered when debug logging is disabled', () {
      LogService.i('This should not be saved', tag: 'Test');
      expect(LogService.getEntries(), isEmpty);
    });

    test('enabling debug logging records entries with appropriate levels', () async {
      await LogService.setEnabled(true);
      expect(LogService.isEnabled, isTrue);

      LogService.d('Debug message', tag: 'TestD');
      LogService.i('Info message', tag: 'TestI');
      LogService.w('Warning message', tag: 'TestW');
      LogService.e('Error message', tag: 'TestE');

      final entries = LogService.getEntries();
      // 1 system enable message + 4 recorded messages = 5
      expect(entries.length, greaterThanOrEqualTo(4));

      final last4 = entries.sublist(entries.length - 4);
      expect(last4[0].level, LogLevel.debug);
      expect(last4[0].message, 'Debug message');
      expect(last4[0].tag, 'TestD');

      expect(last4[1].level, LogLevel.info);
      expect(last4[1].message, 'Info message');

      expect(last4[2].level, LogLevel.warning);
      expect(last4[2].message, 'Warning message');

      expect(last4[3].level, LogLevel.error);
      expect(last4[3].message, 'Error message');
    });

    test('exportLogs returns combined formatted logs', () async {
      await LogService.setEnabled(true);
      LogService.i('Unique test entry for export', tag: 'ExportTest');

      final exported = await LogService.exportLogs();
      expect(exported, contains('[INFO] [ExportTest] Unique test entry for export'));
    });

    test('clearLogs empties the buffer', () async {
      await LogService.setEnabled(true);
      LogService.i('Entry to be cleared', tag: 'ClearTest');
      expect(LogService.getEntries(), isNotEmpty);

      await LogService.clearLogs();
      // After clear, only the "Logs cleared by user" system log is present
      final entries = LogService.getEntries();
      expect(entries.length, 1);
      expect(entries.first.message, 'Logs cleared by user');
    });

    test('disabling debug logging stops recording new messages', () async {
      await LogService.setEnabled(true);
      LogService.i('Message while enabled', tag: 'Test');

      await LogService.setEnabled(false);
      expect(LogService.isEnabled, isFalse);

      final countBefore = LogService.getEntries().length;
      LogService.i('Message after disabled', tag: 'Test');
      expect(LogService.getEntries().length, countBefore);
    });

    test('automatic mirroring writes redrive_debug.log to public mirror directory', () async {
      await LogService.setEnabled(true);
      LogService.i('Mirror verification message', tag: 'MirrorTest');
      await LogService.flush();

      final mirrorFile = File('${tempMirrorDir.path}/redrive_debug.log');
      expect(await mirrorFile.exists(), isTrue);

      final content = await mirrorFile.readAsString();
      expect(content, contains('[INFO] [MirrorTest] Mirror verification message'));
    });

    test('critical errors are mirrored to redrive_crash.log in public directory', () async {
      LogService.e('Catastrophic failure simulation', tag: 'CrashTest');
      await LogService.flush();
      await Future.delayed(const Duration(milliseconds: 50));

      final mirrorCrash = File('${tempMirrorDir.path}/redrive_crash.log');
      expect(await mirrorCrash.exists(), isTrue);

      final content = await mirrorCrash.readAsString();
      expect(content, contains('[ERROR] [CrashTest] Catastrophic failure simulation'));
    });

    test('log rotation archives to redrive_debug.1.log and preserves historical entries', () async {
      await LogService.setEnabled(true);

      // Set a low rotation threshold for deterministic testing
      LogService.maxFileSizeBytesOverride = 200; // 200 bytes threshold

      // Write generation 0 entries
      LogService.i('First generation line 1 - very important history', tag: 'Gen0');
      LogService.i('First generation line 2 - additional context', tag: 'Gen0');
      await LogService.flush();

      final logFile = await LogService.getLogFile();
      final rotatedFile = await LogService.getRotatedLogFile();
      final mirrorLog = File('${tempMirrorDir.path}/redrive_debug.log');
      final mirrorRotated = File('${tempMirrorDir.path}/redrive_debug.1.log');

      expect(await logFile.length(), greaterThanOrEqualTo(200));
      expect(await rotatedFile.exists(), isFalse);

      // Write next entry which exceeds 200 bytes and triggers rotation
      LogService.i('Second generation line 1 - fresh post-rotation log', tag: 'Gen1');
      await LogService.flush();

      // Verify rotation happened
      expect(await rotatedFile.exists(), isTrue, reason: 'Archived file redrive_debug.1.log should exist');
      expect(await mirrorRotated.exists(), isTrue, reason: 'Mirror redrive_debug.1.log should exist');

      // Verify archived file has Gen0 content
      final archivedContent = await rotatedFile.readAsString();
      expect(archivedContent, contains('First generation line 1 - very important history'));

      // Verify active file has Gen1 content and rotation banner
      final activeContent = await logFile.readAsString();
      expect(activeContent, contains('--- LOG ROTATED'));
      expect(activeContent, contains('Second generation line 1 - fresh post-rotation log'));

      // Verify mirror files match
      final mirrorArchived = await mirrorRotated.readAsString();
      expect(mirrorArchived, contains('First generation line 1 - very important history'));
      final mirrorActive = await mirrorLog.readAsString();
      expect(mirrorActive, contains('Second generation line 1 - fresh post-rotation log'));

      // Verify getLogFileSize counts both active and archived files
      final totalSize = await LogService.getLogFileSize();
      expect(totalSize, equals(await logFile.length() + await rotatedFile.length()));

      // Verify exportLogs seamlessly combines archived history and active entries
      final exported = await LogService.exportLogs();
      expect(exported, contains('=== ARCHIVED LOGS (redrive_debug.1.log) ==='));
      expect(exported, contains('First generation line 1 - very important history'));
      expect(exported, contains('Second generation line 1 - fresh post-rotation log'));
    });

    test('clearLogs deletes both active and rotated logs and mirror directory files', () async {
      await LogService.setEnabled(true);
      LogService.maxFileSizeBytesOverride = 150;

      LogService.i('Entry before rotation', tag: 'Rotate');
      await LogService.flush();
      LogService.i('Entry after rotation', tag: 'Rotate');
      await LogService.flush();

      final logFile = await LogService.getLogFile();
      final rotatedFile = await LogService.getRotatedLogFile();
      final mirrorLog = File('${tempMirrorDir.path}/redrive_debug.log');
      final mirrorRotated = File('${tempMirrorDir.path}/redrive_debug.1.log');

      expect(await logFile.exists(), isTrue);

      await LogService.clearLogs();

      expect(await logFile.exists(), isFalse);
      expect(await rotatedFile.exists(), isFalse);
      expect(await mirrorLog.exists(), isFalse);
      expect(await mirrorRotated.exists(), isFalse);
    });
  });
}
