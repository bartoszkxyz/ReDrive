import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/screens/diagnostics_screen.dart';

void main() {
  group('DiagnosticsScreen Widget Tests', () {
    late ObdProvider obdProvider;

    setUp(() async {
      obdProvider = ObdProvider();
      await obdProvider.startDemoMode();
    });

    tearDown(() {
      obdProvider.dispose();
    });

    Widget createSubject() {
      return ChangeNotifierProvider<ObdProvider>.value(
        value: obdProvider,
        child: const MaterialApp(
          home: DiagnosticsScreen(),
        ),
      );
    }

    testWidgets('renders title and mode switchers', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.text('ECU CODES & LIVE SENSORS'), findsOneWidget);
      expect(find.text('Fault Codes (DTC)'), findsOneWidget);
      expect(find.text('Live Sensors'), findsOneWidget);
      expect(find.text('Ready to Diagnose'), findsOneWidget);
      expect(find.text('Scan For Codes'), findsOneWidget);
    });

    testWidgets('switches between DTC and Live Sensors view', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Tap Live Sensors segment
      await tester.tap(find.text('Live Sensors'));
      await tester.pumpAndSettle();

      // Category chips should be visible
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Engine'), findsOneWidget);
      expect(find.text('Air & Fuel'), findsOneWidget);
      expect(find.text('Temperatures'), findsOneWidget);
      expect(find.text('Electrical'), findsOneWidget);

      // Search field should be present
      expect(find.byType(TextField), findsOneWidget);

      // Switch back to Fault Codes
      await tester.tap(find.text('Fault Codes (DTC)'));
      await tester.pumpAndSettle();

      expect(find.text('Scan For Codes'), findsOneWidget);
    });

    testWidgets('scans DTC codes and displays results in demo mode', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final scanButton = find.widgetWithText(ElevatedButton, 'Scan For Codes');
      expect(scanButton, findsOneWidget);

      // Tap scan button
      await tester.tap(scanButton);
      await tester.pump(); // Start scan

      // Scanning indicator should be active
      expect(find.text('Scanning ECU...'), findsOneWidget);

      // Fast forward past simulated scan delay (1200ms)
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      // Trouble codes should now be populated
      expect(find.text('3 FAULT CODES FOUND'), findsOneWidget);
      expect(find.text('P0300'), findsOneWidget);
      expect(find.text('P0171'), findsOneWidget);
      expect(find.text('P0420'), findsOneWidget);

      // Clear button should now be visible
      expect(find.text('Clear'), findsOneWidget);

      // Tap P0300 to expand/collapse details
      expect(find.text('Symptoms: '), findsAtLeastNWidgets(1));
      expect(find.text('Causes: '), findsAtLeastNWidgets(1));
    });

    testWidgets('clears DTC codes after confirmation dialog', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Scan first
      await tester.tap(find.widgetWithText(ElevatedButton, 'Scan For Codes'));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(find.text('3 FAULT CODES FOUND'), findsOneWidget);

      // Tap Clear
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      // Warning dialog should appear
      expect(find.text('Clear Fault Codes?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Clear Codes'), findsOneWidget);

      // Confirm clearing
      await tester.tap(find.text('Clear Codes'));
      await tester.pump(); // Start clear

      // Fast forward past simulated clear delay (1000ms)
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      // All codes should now be cleared
      expect(find.text('No Fault Codes Detected'), findsOneWidget);
    });

    testWidgets('filters live sensors by category and search', (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Switch to Live Sensors
      await tester.tap(find.text('Live Sensors'));
      await tester.pumpAndSettle();

      // Filter by Temperatures
      await tester.tap(find.text('Temperatures'));
      await tester.pumpAndSettle();

      expect(find.text('Engine Coolant Temp'), findsOneWidget);

      // Search by query
      await tester.enterText(find.byType(TextField), 'Coolant');
      await tester.pumpAndSettle();

      expect(find.text('Engine Coolant Temp'), findsOneWidget);

      // Non-matching search
      await tester.enterText(find.byType(TextField), 'NonExistentSensor');
      await tester.pumpAndSettle();

      expect(find.text('No sensors match "NonExistentSensor"'), findsOneWidget);
    });
  });
}
