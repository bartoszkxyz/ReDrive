import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/logging/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LogService.init();
    await LogService.clearLogs();
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
  });
}
