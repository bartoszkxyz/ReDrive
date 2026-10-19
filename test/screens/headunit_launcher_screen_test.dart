import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/core/theme/theme_engine.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/headunit_launcher_screen.dart';
import 'package:redrive/services/gps/gps_location_service.dart';
import 'package:redrive/services/headunit/native_app_launcher_service.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_anomaly_detector.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';

/// In-memory test double implementing [TripProvider] with zero disk I/O.
class FakeTripProvider extends ChangeNotifier implements TripProvider {
  @override
  List<Trip> pastTrips;

  @override
  ActiveTripState activeTrip;

  FakeTripProvider({
    this.pastTrips = const [],
    ActiveTripState? activeTrip,
  }) : activeTrip = activeTrip ?? ActiveTripState.initial();

  VehicleProfile _profile = VehicleProfile.defaultSuzukiSwiftM15A();
  final GpsLocationService _gpsService = GpsLocationService();
  GpsFix? _latestFix;

  @override
  VehicleProfile get activeVehicleProfile => _profile;

  @override
  FuelCalculator get fuelCalculator => FuelCalculator.fromVehicleProfile(_profile);

  @override
  GpsLocationService get gpsService => _gpsService;

  @override
  GpsFix? get latestGpsFix => _latestFix;

  @override
  List<TripRoutePoint> get activeRoutePoints => activeTrip.routePoints;

  @override
  void updateGpsFix(GpsFix fix) {
    _latestFix = fix;
  }

  @override
  void applyVehicleProfile(VehicleProfile profile) {
    _profile = profile;
  }

  @override
  double get effectiveOdometerKm => _profile.effectiveOdometerKm(totalDistance);

  @override
  double get totalDistance =>
      pastTrips.fold(0.0, (acc, t) => acc + t.distanceKm);

  @override
  double get totalFuelConsumed =>
      pastTrips.fold(0.0, (acc, t) => acc + t.fuelConsumedLiters);

  @override
  double get overallAvgFuel =>
      totalDistance > 0 ? (totalFuelConsumed / totalDistance) * 100.0 : 0.0;

  @override
  double get minTripDistanceKm => 0.1;

  @override
  bool get autoTripEnabled => true;

  @override
  Future<void> get initialized => Future.value();

  @override
  TripTimeseriesService get timeseriesService => throw UnimplementedError();

  @override
  TripAnomalyDetector get anomalyDetector => throw UnimplementedError();

  @override
  Future<List<String>> exportTripTimeseries(
    Trip trip, {
    TimeseriesExportFormat format = TimeseriesExportFormat.both,
  }) async => [];

  @override
  void bindToObd(ObdProvider obdProvider) {}

  @override
  void updateFromObd(ObdProvider obdProvider) {}

  @override
  void processDataPoint(
    ObdData data, {
    DateTime? timestamp,
    GpsFix? gpsFix,
  }) {}

  @override
  void processDataPointForTesting(
    ObdData data, [
    DateTime? timestamp,
    GpsFix? gpsFix,
  ]) {}

  @override
  void recordDtcCodes(
    List<DtcCode> codes, {
    DateTime? timestamp,
    bool isTripStart = false,
    GpsFix? gpsFix,
  }) {}

  @override
  Future<void> saveCheckpoint([DateTime? now]) async {}

  @override
  Future<void> setAutoTripEnabled(bool enabled) async {}

  @override
  Future<void> setMinTripDistanceKm(double km) async {}

  @override
  void manualStartTrip([DateTime? startTime]) {}

  @override
  Future<void> manualEndTrip([DateTime? finishTime]) async {}

  @override
  Future<void> deleteTrip(String id) async {
    pastTrips = pastTrips.where((t) => t.id != id).toList();
    notifyListeners();
  }

  @override
  Future<void> markTripsAsSynced(
    Iterable<String> tripIds, {
    int maxUnsyncedTrips = 35,
    int maxSyncedTrips = 5,
  }) async {}

  @override
  Future<void> ingestSyncedTrip(
    Trip trip, {
    List<String>? timeseriesLines,
  }) async {}

  @override
  Future<void> Function(Trip trip)? onTripFinished;

  @override
  Future<void> Function()? onSpeedZeroStandstill;

  @override
  Future<void> clearHistory() async {
    pastTrips = [];
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.redrive/storage');
  final List<MethodCall> methodCalls = [];

  final mockApps = [
    {
      'packageName': 'com.zjinnova.zlink',
      'activityName': 'com.zjinnova.android.zlink.features.main.MainActivity',
      'label': 'TLINK5',
    },
    {
      'packageName': 'com.tw.radio',
      'activityName': 'com.tw.radio.RadioActivity',
      'label': 'Radio',
    },
    {
      'packageName': 'com.spotify.music',
      'activityName': 'com.spotify.music.MainActivity',
      'label': 'Spotify',
    },
  ];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      if (call.method == 'startDvrService') {
        return true;
      }
      if (call.method == 'isDvrRunning') {
        return true;
      }
      if (call.method == 'launchApp') {
        return true;
      }
      if (call.method == 'getInstalledApps') {
        return mockApps;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget buildLauncherHarness({
    required TripProvider tripProvider,
    required ObdProvider obdProvider,
    required ThemeEngine themeEngine,
    required SyncProvider syncProvider,
    VoidCallback? onOpenDashboard,
    VoidCallback? onOpenTrips,
    VoidCallback? onOpenConnections,
    VoidCallback? onOpenSettings,
    DateTime Function()? nowProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TripProvider>.value(value: tripProvider),
        ChangeNotifierProvider<ObdProvider>.value(value: obdProvider),
        ChangeNotifierProvider<ThemeEngine>.value(value: themeEngine),
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
      ],
      child: MaterialApp(
        home: HeadunitLauncherScreen(
          onOpenDashboard: onOpenDashboard,
          onOpenTrips: onOpenTrips,
          onOpenConnections: onOpenConnections,
          onOpenSettings: onOpenSettings,
          nowProvider: nowProvider,
          enablePeriodicTimers: false,
        ),
      ),
    );
  }

  group('HeadunitLauncherScreen (1280x720 Landscape Cockpit)', () {
    testWidgets('initializes and triggers background DVR service start',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
          nowProvider: () => DateTime(2026, 10, 18, 12, 45),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((call) => call.method == 'startDvrService'),
        isTrue,
      );

      // Verify Cockpit Header Bar items
      expect(find.byKey(const Key('cockpit_header_time')), findsOneWidget);
      expect(find.text('12:45 PM'), findsOneWidget);
      expect(find.byKey(const Key('dvr_rec_badge')), findsOneWidget);
      expect(find.byKey(const Key('bt_status_badge')), findsOneWidget);
      expect(find.byKey(const Key('cockpit_settings_button')), findsOneWidget);
    });

    testWidgets('TripFlightComputerCard renders duration, distance, avg fuel, and fuel used',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider(
        activeTrip: ActiveTripState(
          isActive: true,
          startTime: DateTime(2026, 10, 18, 11, 57),
          duration: const Duration(minutes: 48, seconds: 12),
          distanceKm: 55.1,
          fuelConsumedLiters: 3.42,
          avgFuelConsumption: 6.2,
          instantFuelL100km: 6.8,
          instantFuelLPerHour: 5.4,
          avgSpeed: 68.0,
          maxSpeed: 110.0,
          maxRpm: 3200,
          currentSpeed: 70,
          currentRpm: 2400,
        ),
      );
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
          nowProvider: () => DateTime(2026, 10, 18, 12, 45),
        ),
      );
      await tester.pumpAndSettle();

      // Card is mounted
      expect(find.byKey(const Key('trip_flight_computer_card')), findsOneWidget);

      // Duration
      expect(find.byKey(const Key('flight_trip_duration')), findsOneWidget);
      expect(find.text('48:12'), findsOneWidget);

      // Distance
      expect(find.byKey(const Key('flight_trip_distance')), findsOneWidget);
      expect(find.text('55.1 km'), findsOneWidget);

      // Average Fuel
      expect(find.byKey(const Key('flight_trip_avg_fuel')), findsOneWidget);
      expect(find.text('6.2 L/100km'), findsOneWidget);

      // Total Fuel Used
      expect(find.byKey(const Key('flight_trip_fuel_used')), findsOneWidget);
      expect(find.text('3.42 L'), findsOneWidget);

      // Top Timepiece Header text
      expect(
        find.textContaining('12:45 PM • Sunday, October 18, 2026'),
        findsOneWidget,
      );
    });

    testWidgets('InstantFuelFlowBar renders economy numbers and shows DFCO: ACTIVE when triggered',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      obdProvider.setDataForTesting(const ObdData(
        coolantTemp: 85,
        engineLoad: 38.0,
        isDfcoActive: true,
      ));

      final tripProvider = FakeTripProvider(
        activeTrip: ActiveTripState(
          isActive: true,
          startTime: DateTime.now(),
          duration: const Duration(minutes: 10),
          distanceKm: 12.0,
          fuelConsumedLiters: 0.8,
          avgFuelConsumption: 5.5,
          instantFuelL100km: 0.0,
          instantFuelLPerHour: 0.0,
          avgSpeed: 50.0,
          maxSpeed: 80.0,
          maxRpm: 2500,
          currentSpeed: 60,
          currentRpm: 2200,
        ),
      );
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // Flow bar exists
      expect(find.byKey(const Key('instant_fuel_flow_bar')), findsOneWidget);
      expect(find.text('0.0 L/100km'), findsOneWidget);
      expect(find.text('0.0 L/h'), findsOneWidget);

      // DFCO active badge is visible
      expect(find.byKey(const Key('dfco_active_badge')), findsOneWidget);
      expect(find.text('DFCO: ACTIVE'), findsOneWidget);

      // Now disable DFCO
      obdProvider.setDataForTesting(const ObdData(
        coolantTemp: 85,
        engineLoad: 45.0,
        isDfcoActive: false,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dfco_active_badge')), findsNothing);
    });

    testWidgets('EngineVitalsCard renders Coolant, Engine Load, and portal buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      obdProvider.setDataForTesting(const ObdData(
        coolantTemp: 85,
        engineLoad: 38.0,
      ));

      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      bool dashboardOpened = false;
      bool tripsOpened = false;
      bool connectionsOpened = false;

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
          onOpenDashboard: () => dashboardOpened = true,
          onOpenTrips: () => tripsOpened = true,
          onOpenConnections: () => connectionsOpened = true,
        ),
      );
      await tester.pumpAndSettle();

      // PipApplicationBay is mounted
      expect(find.byKey(const Key('pip_application_bay')), findsOneWidget);

      // Coolant in 6-tile grid
      expect(find.byKey(const Key('cockpit_coolant_card')), findsOneWidget);
      expect(find.text('85 °C'), findsOneWidget);
      expect(find.text('Optimal Working Zone'), findsOneWidget);

      // Engine Load in 6-tile grid
      expect(find.byKey(const Key('cockpit_engine_load_card')), findsOneWidget);
      expect(find.text('38 %'), findsOneWidget);
      expect(find.text('Cruising / Closed Loop'), findsOneWidget);

      // Header Bar Portal Buttons
      final dashBtn = find.byKey(const Key('header_open_dashboard'));
      expect(dashBtn, findsOneWidget);
      await tester.tap(dashBtn);
      await tester.pump();
      expect(dashboardOpened, isTrue);

      final tripsBtn = find.byKey(const Key('header_open_trips'));
      expect(tripsBtn, findsOneWidget);
      await tester.tap(tripsBtn);
      await tester.pump();
      expect(tripsOpened, isTrue);

      // Also verify Header Bar Bluetooth badge opens connections
      connectionsOpened = false;
      final btBadge = find.byKey(const Key('bt_status_badge'));
      expect(btBadge, findsOneWidget);
      await tester.tap(btBadge);
      await tester.pump();
      expect(connectionsOpened, isTrue);
    });

    testWidgets('TactileLauncherDock one-tap launches TLINK5, Radio, DSP, and HD DVR',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      methodCalls.clear();

      // 1. TLINK5
      await tester.tap(find.byKey(const Key('dock_launch_tlink')));
      await tester.pump();
      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgTlink5),
        isTrue,
      );

      // 2. Radio
      await tester.tap(find.byKey(const Key('dock_launch_radio')));
      await tester.pump();
      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgRadio),
        isTrue,
      );

      // 3. DSP / EQ
      await tester.tap(find.byKey(const Key('dock_launch_dsp')));
      await tester.pump();
      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgDsp),
        isTrue,
      );

      // 4. HD DVR
      await tester.tap(find.byKey(const Key('dock_launch_dvr')));
      await tester.pump();
      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgDvr),
        isTrue,
      );
    });

    testWidgets('TactileLauncherDock opens App Drawer sheet and launches selected app',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // Tap All Apps
      await tester.tap(find.byKey(const Key('dock_launch_app_drawer')));
      await tester.pumpAndSettle();

      // Verify App Drawer sheet opened
      expect(find.byKey(const Key('app_drawer_sheet')), findsOneWidget);
      expect(find.text('INSTALLED APPLICATIONS'), findsOneWidget);

      // Verify discovered apps are shown
      expect(find.text('Spotify'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('app_drawer_sheet')),
          matching: find.text('Radio'),
        ),
        findsOneWidget,
      );
      expect(find.text('TLINK5'), findsWidgets);

      // Tap Spotify
      methodCalls.clear();
      await tester.tap(find.byKey(const Key('app_item_com.spotify.music')));
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == 'com.spotify.music'),
        isTrue,
      );

      // Sheet should be dismissed after selection
      expect(find.byKey(const Key('app_drawer_sheet')), findsNothing);
    });

    testWidgets('CockpitHeaderBar DVR badge tap launches DVR and settings button opens settings',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      bool settingsOpened = false;

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
          onOpenSettings: () => settingsOpened = true,
        ),
      );
      await tester.pumpAndSettle();

      methodCalls.clear();

      // Tap DVR badge
      await tester.tap(find.byKey(const Key('dvr_rec_badge')));
      await tester.pump();
      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgDvr),
        isTrue,
      );

      // Tap Settings button
      await tester.tap(find.byKey(const Key('cockpit_settings_button')));
      await tester.pump();
      expect(settingsOpened, isTrue);
    });

    testWidgets('EngineVitalsCard reflects all coolant temperature safety thresholds',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Warming Up (< 70°C)
      obdProvider.setDataForTesting(const ObdData(coolantTemp: 55));
      await tester.pumpAndSettle();
      expect(find.text('55 °C'), findsOneWidget);
      expect(find.text('Warming Up'), findsOneWidget);

      // 2. Optimal (70°C - 96°C)
      obdProvider.setDataForTesting(const ObdData(coolantTemp: 88));
      await tester.pumpAndSettle();
      expect(find.text('88 °C'), findsOneWidget);
      expect(find.text('Optimal Working Zone'), findsOneWidget);

      // 3. Elevated Temp (97°C - 101°C)
      obdProvider.setDataForTesting(const ObdData(coolantTemp: 99));
      await tester.pumpAndSettle();
      expect(find.text('99 °C'), findsOneWidget);
      expect(find.text('Elevated Temp'), findsOneWidget);

      // 4. Overheat Alert (>= 102°C)
      obdProvider.setDataForTesting(const ObdData(coolantTemp: 106));
      await tester.pumpAndSettle();
      expect(find.text('106 °C'), findsOneWidget);
      expect(find.text('OVERHEAT ALERT'), findsOneWidget);
    });

    testWidgets('EngineVitalsCard reflects engine load zones',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Idle / Decel (< 30%)
      obdProvider.setDataForTesting(const ObdData(engineLoad: 18.0));
      await tester.pumpAndSettle();
      expect(find.text('18 %'), findsOneWidget);
      expect(find.text('Idle / Decel'), findsOneWidget);

      // 2. Cruising / Closed Loop (30% - 65%)
      obdProvider.setDataForTesting(const ObdData(engineLoad: 52.0));
      await tester.pumpAndSettle();
      expect(find.text('52 %'), findsOneWidget);
      expect(find.text('Cruising / Closed Loop'), findsOneWidget);

      // 3. High Acceleration / Power (> 65%)
      obdProvider.setDataForTesting(const ObdData(engineLoad: 84.0));
      await tester.pumpAndSettle();
      expect(find.text('84 %'), findsOneWidget);
      expect(find.text('High Acceleration / Power'), findsOneWidget);
    });

    testWidgets('TripFlightComputerCard formats hours duration as hh:mm',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final themeEngine = ThemeEngine(inMemory: true);
      final obdProvider = ObdProvider();
      final tripProvider = FakeTripProvider(
        activeTrip: ActiveTripState(
          isActive: true,
          startTime: DateTime.now(),
          duration: const Duration(hours: 2, minutes: 15, seconds: 40),
          distanceKm: 165.4,
          fuelConsumedLiters: 10.25,
          avgFuelConsumption: 6.2,
          instantFuelL100km: 6.5,
          instantFuelLPerHour: 4.8,
          avgSpeed: 73.0,
          maxSpeed: 120.0,
          maxRpm: 3400,
          currentSpeed: 80,
          currentRpm: 2600,
        ),
      );
      final syncService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildLauncherHarness(
          tripProvider: tripProvider,
          obdProvider: obdProvider,
          themeEngine: themeEngine,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('02:15'), findsOneWidget);
      expect(find.text('165.4 km'), findsOneWidget);
      expect(find.text('10.25 L'), findsOneWidget);
    });
  });
}
