import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/models/sync_models.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';
import 'package:obdrive/services/sync/network_sync_manager.dart';
import 'package:obdrive/widget/companion/sync_status_pill.dart';
import 'package:obdrive/widget/companion/vehicle_link_modal_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSnapshot = ParkedCarSnapshot(
    timestamp: DateTime(2026, 10, 19, 14, 30),
    latitude: 52.2297,
    longitude: 21.0122,
    vehicleId: 'swift_15',
    vehicleName: 'Suzuki Swift 3',
    odometerKm: 142350.0,
    remainingFuelLiters: 32.5,
    fuelLevelPercent: 72.0,
    estimatedRangeKm: 477.9,
    batteryVoltage: 12.6,
  );

  Widget createTestWidget({
    required SyncProvider syncProvider,
    Widget? child,
  }) {
    return ChangeNotifierProvider<SyncProvider>.value(
      value: syncProvider,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: child ??
              Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => VehicleLinkModalSheet.show(context),
                  child: const Text('Open Sheet'),
                ),
              ),
        ),
      ),
    );
  }

  group('VehicleLinkModalSheet & SyncStatusPill Tests', () {
    testWidgets('VehicleLinkModalSheet renders all status cards, gateway, and action buttons',
        (tester) async {
      final syncService = BluetoothSyncService(
        deviceId: 'test_phone',
        deviceRole: 'phone',
        inMemory: true,
      );
      await syncService.updateParkedSnapshot(testSnapshot);

      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(createTestWidget(syncProvider: syncProvider));
      await tester.pumpAndSettle();

      // Open modal sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Header title
      expect(find.text('Vehicle Link & Diagnostics'), findsOneWidget);

      // Target Gateway
      expect(find.text('192.168.43.1:7355'), findsOneWidget);

      // Reported vehicle vitals from snapshot
      expect(find.text('Battery: 12.6V'), findsOneWidget);
      expect(find.text('Fuel: 72%'), findsOneWidget);
      expect(find.text('Odo: 142350 km'), findsOneWidget);

      // Buttons
      expect(find.byKey(const Key('run_self_test_button')), findsOneWidget);
      expect(find.byKey(const Key('link_sheet_sync_now_button')), findsOneWidget);

      syncProvider.dispose();
    });

    testWidgets('Tapping run_self_test_button executes 4-step self-test and displays results',
        (tester) async {
      final syncService = BluetoothSyncService(
        deviceId: 'test_phone',
        deviceRole: 'phone',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);
      syncProvider.overrideSelfTestReport = LinkSelfTestReport(
        steps: const [
          LinkStepResult(
            step: LinkSelfTestStep.wifiEnabled,
            status: LinkStepStatus.passed,
            title: 'Phone Wi-Fi State',
            details: 'Active interface(s): 192.168.43.15 (wlan0)',
          ),
          LinkStepResult(
            step: LinkSelfTestStep.androidAutoSubnet,
            status: LinkStepStatus.passed,
            title: 'Android Auto Subnet',
            details: 'Connected to in-car Android Auto hotspot subnet (192.168.43.x).',
          ),
          LinkStepResult(
            step: LinkSelfTestStep.headunitSocketPing,
            status: LinkStepStatus.passed,
            title: 'Headunit Socket Ping',
            details: 'Headunit server responded in 18ms.',
            pingMs: 18,
          ),
          LinkStepResult(
            step: LinkSelfTestStep.protocolHandshake,
            status: LinkStepStatus.passed,
            title: 'Protocol Handshake & Status',
            details: 'OBDrive v2 frame handshake verified.',
          ),
        ],
        timestamp: DateTime.now(),
        overallSuccess: true,
        diagnosticTip: 'All checks passed! Direct Android Auto link is operational.',
      );

      await tester.pumpWidget(createTestWidget(syncProvider: syncProvider));
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Tap Run Test button
      await tester.tap(find.byKey(const Key('run_self_test_button')));
      await tester.pumpAndSettle();

      // The 4 self-test steps should now be displayed in the results card
      expect(find.text('Phone Wi-Fi State'), findsOneWidget);
      expect(find.text('Android Auto Subnet'), findsOneWidget);
      expect(find.text('Headunit Socket Ping'), findsOneWidget);
      expect(find.text('Protocol Handshake & Status'), findsOneWidget);
      expect(find.text('All checks passed! Direct Android Auto link is operational.'), findsOneWidget);

      syncProvider.dispose();
    });

    testWidgets('SyncStatusPill supports single-tap and double-tap gestures', (tester) async {
      bool singleTapped = false;
      bool doubleTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SyncStatusPill(
                connectionState: SyncConnectionState.disconnected,
                onTap: () => singleTapped = true,
                onDoubleTap: () => doubleTapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pillFinder = find.byKey(const Key('sync_status_pill'));
      expect(pillFinder, findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);

      // Single tap (wait beyond kDoubleTapTimeout)
      await tester.tap(pillFinder);
      await tester.pump(const Duration(milliseconds: 350));
      expect(singleTapped, isTrue);

      // Reset
      singleTapped = false;

      // Double tap
      await tester.tap(pillFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(pillFinder);
      await tester.pumpAndSettle();
      expect(doubleTapped, isTrue);
    });
  });
}
