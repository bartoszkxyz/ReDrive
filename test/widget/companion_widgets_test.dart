import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/diagnostics_screen.dart';
import 'package:redrive/screens/home_screen.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/widget/companion/mechanic_report_sheet.dart';
import 'package:redrive/widget/companion/parked_car_status_card.dart';
import 'package:redrive/widget/companion/sync_status_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedTime = DateTime(2026, 10, 18, 14, 30);

  final testSnapshot = ParkedCarSnapshot(
    timestamp: fixedTime,
    vehicleId: 'swift_07',
    vehicleName: 'Suzuki Swift 3',
    latitude: 42.6977,
    longitude: 23.3219,
    remainingFuelLiters: 35.5,
    fuelLevelPercent: 79.0,
    estimatedRangeKm: 512.0,
    batteryVoltage: 12.55,
    coolantTempC: 86.0,
    odometerKm: 154210.0,
    lastTripId: 'trip_1001',
  );

  group('ParkedCarStatusCard', () {
    testWidgets(
        'renders coordinates, fuel, battery, range, and odometer',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParkedCarStatusCard(snapshot: testSnapshot),
          ),
        ),
      );

      // Card key
      expect(find.byKey(const Key('parked_car_status_card')), findsOneWidget);

      // Header: Vehicle Name & Timestamp
      expect(find.text('Suzuki Swift 3'), findsOneWidget);
      expect(find.byKey(const Key('parked_car_timestamp')), findsOneWidget);

      // GPS Coordinates badge
      final locationBadgeFinder =
          find.byKey(const Key('parked_car_location_badge'));
      expect(locationBadgeFinder, findsOneWidget);
      expect(
        find.descendant(
          of: locationBadgeFinder,
          matching: find.text('42.6977, 23.3219'),
        ),
        findsOneWidget,
      );

      // Fuel Level
      final fuelFinder = find.byKey(const Key('parked_car_fuel'));
      expect(fuelFinder, findsOneWidget);
      expect(find.text('35.5 L (79%)'), findsOneWidget);

      // Estimated Range
      final rangeFinder = find.byKey(const Key('parked_car_range'));
      expect(rangeFinder, findsOneWidget);
      expect(find.text('~512 km'), findsOneWidget);

      // Battery Voltage
      final batteryFinder = find.byKey(const Key('parked_car_battery'));
      expect(batteryFinder, findsOneWidget);
      expect(find.text('12.55 V'), findsOneWidget);

      // Odometer
      final odometerFinder = find.byKey(const Key('parked_car_odometer'));
      expect(odometerFinder, findsOneWidget);
      expect(find.text('154210 km'), findsOneWidget);
    });

    testWidgets('renders Location unavailable badge when coordinates are null',
        (tester) async {
      final noCoordsSnapshot = ParkedCarSnapshot(
        timestamp: fixedTime,
        vehicleId: 'swift_07',
        vehicleName: 'Suzuki Swift 3',
        latitude: null,
        longitude: null,
        remainingFuelLiters: 20.0,
        fuelLevelPercent: 50.0,
        estimatedRangeKm: 300.0,
        batteryVoltage: 12.6,
        odometerKm: 154210.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParkedCarStatusCard(snapshot: noCoordsSnapshot),
          ),
        ),
      );

      final locationBadgeFinder =
          find.byKey(const Key('parked_car_location_badge'));
      expect(locationBadgeFinder, findsOneWidget);
      expect(
        find.descendant(
          of: locationBadgeFinder,
          matching: find.text('Location unavailable'),
        ),
        findsOneWidget,
      );
    });
  });

  group('SyncStatusPill', () {
    testWidgets('renders each SyncConnectionState with appropriate label',
        (tester) async {
      final testCases = [
        (SyncConnectionState.disconnected, 'Disconnected'),
        (SyncConnectionState.listening, 'Listening...'),
        (SyncConnectionState.connecting, 'Syncing...'),
        (SyncConnectionState.syncing, 'Syncing...'),
        (SyncConnectionState.connected, 'Connected'),
        (SyncConnectionState.synced, 'Synced'),
        (SyncConnectionState.error, 'Sync Error'),
      ];

      for (final (state, expectedLabel) in testCases) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyncStatusPill(connectionState: state),
            ),
          ),
        );

        expect(find.byKey(const Key('sync_status_pill')), findsOneWidget);
        expect(find.text(expectedLabel), findsOneWidget);
      }
    });

    testWidgets('tapping pill calls onTap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusPill(
              connectionState: SyncConnectionState.synced,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('sync_status_pill')));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('MechanicReportSheet', () {
    final vehicle = VehicleProfile.defaultSuzukiSwiftM15A().copyWith(
      vin: 'TS18VIN987654321',
    );

    const storedDtc = DtcCode(
      code: 'P0300',
      system: 'Powertrain',
      title: 'Random/Multiple Cylinder Misfire Detected',
      description: 'Multiple cylinders misfiring',
      severity: 'Critical',
      isPending: false,
      symptoms: 'Check engine light blinking',
      possibleCauses: 'Faulty spark plugs or ignition coils',
    );

    const pendingDtc = DtcCode(
      code: 'P0171',
      system: 'Powertrain',
      title: 'System Too Lean (Bank 1)',
      description: 'Air-fuel mixture too lean',
      severity: 'Warning',
      isPending: true,
      symptoms: 'Hesitation during acceleration',
      possibleCauses: 'Intake manifold vacuum leak',
    );

    final anomaly = TripAnomalyEpisode(
      id: 'anom_01',
      severity: AnomalySeverity.problem,
      category: AnomalyCategory.powerLoss,
      title: 'Severe Engine Misfire',
      description: 'RPM stutter under heavy load',
      startTime: fixedTime,
      endTime: fixedTime.add(const Duration(seconds: 10)),
      dtcCodes: const ['P0300'],
    );

    final testReport = MechanicDiagnosticReport(
      reportId: 'rep_widget_test',
      generatedAt: fixedTime,
      vehicle: vehicle,
      currentOdometerKm: 154210.0,
      storedDtcs: const [storedDtc],
      pendingDtcs: const [pendingDtc],
      recentAnomalies: [anomaly],
      latestSnapshot: testSnapshot,
    );

    testWidgets(
        'renders vehicle info, DTCs, anomaly items, and tapping share button copies formatted text to clipboard',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments;
          if (args is Map) {
            clipboardText = args['text']?.toString();
          }
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MechanicReportSheet(report: testReport),
          ),
        ),
      );

      // Title & Header info
      expect(find.byKey(const Key('mechanic_report_title')), findsOneWidget);
      expect(find.textContaining('Suzuki Swift 3'), findsOneWidget);
      expect(find.textContaining('TS18VIN987654321'), findsOneWidget);
      expect(find.textContaining('154210.0 km'), findsOneWidget);

      // Stored DTC item
      expect(find.text('P0300'), findsOneWidget);
      expect(find.text('Multiple cylinders misfiring'), findsOneWidget);

      // Pending DTC item
      expect(find.text('P0171'), findsOneWidget);
      expect(find.text('Air-fuel mixture too lean'), findsOneWidget);

      // Recent Anomaly item
      expect(find.text('Severe Engine Misfire'), findsOneWidget);
      expect(find.text('RPM stutter under heavy load'), findsOneWidget);

      // Share Button
      final shareBtn = find.byKey(const Key('mechanic_report_share_button'));
      expect(shareBtn, findsOneWidget);

      // Tap Share Button
      await tester.tap(shareBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify snackbar is shown
      expect(find.text('Report copied to clipboard'), findsOneWidget);

      // Verify clipboard received the formatted summary
      expect(clipboardText, isNotNull);
      expect(clipboardText, equals(testReport.toFormattedTextSummary()));
      expect(clipboardText, contains('TS18VIN987654321'));
      expect(clipboardText, contains('P0300'));

      // Dismiss snackbars to ensure no lingering timers
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
          .clearSnackBars();
      await tester.pump();
    });
  });

  group('Screen Integrations', () {
    testWidgets(
        'HomeScreen renders SyncStatusPill in top bar and ParkedCarStatusCard when snapshot exists',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final syncService = BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: 'phone',
        inMemory: true,
      );
      await syncService.updateParkedSnapshot(testSnapshot);

      final syncProvider = SyncProvider(syncService: syncService);
      final obdProvider = ObdProvider();
      final tripProvider = TripProvider();
      final garageProvider = GarageProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: obdProvider),
            ChangeNotifierProvider.value(value: tripProvider),
            ChangeNotifierProvider.value(value: garageProvider),
            ChangeNotifierProvider.value(value: syncProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header bar SyncStatusPill
      expect(find.byKey(const Key('sync_status_pill')), findsOneWidget);

      // ParkedCarStatusCard
      expect(find.byKey(const Key('parked_car_status_card')), findsOneWidget);
      expect(find.text('Suzuki Swift 3'), findsOneWidget);

      tripProvider.dispose();
      syncProvider.dispose();
      obdProvider.dispose();
      garageProvider.dispose();
    });

    testWidgets(
        'DiagnosticsScreen renders generate_mechanic_report_button and opens MechanicReportSheet',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final syncService = BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: 'headunit',
        inMemory: true,
      );
      await syncService.updateParkedSnapshot(testSnapshot);

      final syncProvider = SyncProvider(syncService: syncService);
      final obdProvider = ObdProvider();
      final tripProvider = TripProvider();
      final garageProvider = GarageProvider();

      syncProvider.bindProviders(
        tripProvider: tripProvider,
        garageProvider: garageProvider,
        obdProvider: obdProvider,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: obdProvider),
            ChangeNotifierProvider.value(value: tripProvider),
            ChangeNotifierProvider.value(value: garageProvider),
            ChangeNotifierProvider.value(value: syncProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: DiagnosticsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final reportButton =
          find.byKey(const Key('generate_mechanic_report_button'));
      expect(reportButton, findsOneWidget);

      await tester.tap(reportButton);
      await tester.pumpAndSettle();

      // Mechanic Report Sheet opened
      expect(find.byKey(const Key('mechanic_report_title')), findsOneWidget);
      expect(find.byKey(const Key('mechanic_report_share_button')),
          findsOneWidget);

      tripProvider.dispose();
      syncProvider.dispose();
      obdProvider.dispose();
      garageProvider.dispose();
    });
  });
}
