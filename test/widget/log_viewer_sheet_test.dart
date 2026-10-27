import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/services/logging/log_service.dart';
import 'package:obdrive/widget/settings/log_viewer_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempMirrorDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempMirrorDir = await Directory.systemTemp.createTemp('obdrive_widget_test_');
    LogService.publicMirrorDirOverride = tempMirrorDir;
    await LogService.init();
    await LogService.clearLogs();
  });

  tearDown(() async {
    LogService.publicMirrorDirOverride = null;
    if (await tempMirrorDir.exists()) {
      await tempMirrorDir.delete(recursive: true);
    }
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(
        body: LogViewerSheet(),
      ),
    );
  }

  group('LogViewerSheet Widget Tests', () {
    testWidgets('renders diagnostic sheet header with title, entries count, and mirror path',
        (tester) async {
      await tester.runAsync(() async {
        await LogService.setEnabled(true);
        LogService.i('Diagnostic UI verification message', tag: 'UITest');
        await LogService.flush();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('Diagnostic Logs'), findsOneWidget);
      expect(find.textContaining('Mirror:'), findsOneWidget);
      expect(find.textContaining('Logging Active'), findsOneWidget);
      expect(find.text('OBD'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);

      // Verify log message appears in list
      expect(find.textContaining('Diagnostic UI verification message'), findsOneWidget);
    });

    testWidgets('search filter narrows visible log entries in list', (tester) async {
      await tester.runAsync(() async {
        await LogService.setEnabled(true);
        LogService.i('First searchable item', tag: 'App');
        LogService.i('Second distinct item', tag: 'App');
        await LogService.flush();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('First searchable item'), findsOneWidget);
      expect(find.textContaining('Second distinct item'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'First');
      await tester.pumpAndSettle();

      expect(find.textContaining('First searchable item'), findsOneWidget);
      expect(find.textContaining('Second distinct item'), findsNothing);
    });

    testWidgets('clear logs button opens confirmation dialog and clears logs', (tester) async {
      await tester.runAsync(() async {
        await LogService.setEnabled(true);
        LogService.i('Message to be cleared', tag: 'Clear');
        await LogService.flush();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Message to be cleared'), findsOneWidget);

      // Tap delete icon
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Clear All Logs?'), findsOneWidget);

      // Confirm clear in dialog
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Message to be cleared'), findsNothing);
      expect(find.textContaining('Logs cleared by user'), findsOneWidget);
    });
  });
}
