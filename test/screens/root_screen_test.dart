import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/core/app_flavor.dart';
import 'package:redrive/core/theme/theme_engine.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/bluetooth_provider.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/connection_screen.dart';
import 'package:redrive/screens/dashboard_screen.dart';
import 'package:redrive/screens/headunit_launcher_screen.dart';
import 'package:redrive/screens/home_screen.dart';
import 'package:redrive/screens/root_screen.dart';
import 'package:redrive/screens/trips_screen.dart';
import 'package:redrive/services/garage/garage_service.dart';
import 'package:redrive/services/gps/gps_location_service.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_anomaly_detector.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';
import 'package:redrive/widget/bottom_bar/custom_bottom_bar.dart';

class FakeTripProvider extends ChangeNotifier implements TripProvider {
  @override
  List<Trip> pastTrips;

  @override
  ActiveTripState activeTrip;

  @override
  VehicleProfile activeVehicleProfile;

  @override
  FuelCalculator fuelCalculator;

  @override
  double totalDistance;

  final GpsLocationService _gpsService = GpsLocationService();
  GpsFix? _latestFix;

  FakeTripProvider({
    this.pastTrips = const [],
    ActiveTripState? activeTrip,
    VehicleProfile? activeVehicleProfile,
    FuelCalculator? fuelCalculator,
    this.totalDistance = 0.0,
  })  : activeTrip = activeTrip ?? ActiveTripState.initial(),
        activeVehicleProfile = activeVehicleProfile ??
            VehicleProfile.defaultSuzukiSwiftM15A(),
        fuelCalculator = fuelCalculator ??
            FuelCalculator.fromVehicleProfile(
              activeVehicleProfile ?? VehicleProfile.defaultSuzukiSwiftM15A(),
            );

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
  double get effectiveOdometerKm =>
      activeVehicleProfile.effectiveOdometerKm(totalDistance);

  @override
  void applyVehicleProfile(VehicleProfile profile) {
    activeVehicleProfile = profile;
    fuelCalculator = FuelCalculator.fromVehicleProfile(profile);
    notifyListeners();
  }

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
  }) async =>
      [];

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
  }) async {
    final ids = tripIds.toSet();
    pastTrips = pastTrips
        .map((t) => ids.contains(t.id) ? t.copyWith(isSynced: true) : t)
        .toList();
    notifyListeners();
  }

  @override
  Future<void> ingestSyncedTrip(
    Trip trip, {
    List<String>? timeseriesLines,
  }) async {
    pastTrips = [trip.copyWith(isSynced: true), ...pastTrips];
    notifyListeners();
  }

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'startDvrService') return true;
      if (call.method == 'isDvrRunning') return true;
      if (call.method == 'getInstalledApps') return <Map<String, dynamic>>[];
      return null;
    });
  });

  tearDown(() {
    AppConfig.reset();
  });

  Widget buildRootWidget({
    required AppFlavor flavor,
  }) {
    AppConfig.initialize(flavor: flavor);
    final themeEngine = ThemeEngine(inMemory: true);
    final bluetoothProvider = BluetoothProvider();
    final obdProvider = ObdProvider();
    final tripProvider = FakeTripProvider();
    final garageProvider = GarageProvider(
      garageService: GarageService(inMemory: true),
    );
    final syncProvider = SyncProvider(
      syncService: BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: flavor.name,
      ),
      themeEngine: themeEngine,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeEngine>.value(value: themeEngine),
        ChangeNotifierProvider<BluetoothProvider>.value(value: bluetoothProvider),
        ChangeNotifierProvider<ObdProvider>.value(value: obdProvider),
        ChangeNotifierProvider<TripProvider>.value(value: tripProvider),
        ChangeNotifierProvider<GarageProvider>.value(value: garageProvider),
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
      ],
      child: const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RootScreen(),
      ),
    );
  }

  testWidgets('Headunit flavor mounts HeadunitLauncherScreen as index 0 without bottom bar',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildRootWidget(flavor: AppFlavor.headunit));
    await tester.pump();

    // Verify HeadunitLauncherScreen is present
    expect(find.byType(HeadunitLauncherScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    // Verify bottom navigation bar is hidden on launcher home (index 0)
    expect(find.byType(CustomBottomBar), findsNothing);

    // Verify tactile launcher dock is visible
    expect(find.text('TLINK5'), findsOneWidget);
    expect(find.text('RADIO'), findsOneWidget);
    expect(find.text('ALL APPS'), findsOneWidget);
  });

  testWidgets('Headunit navigation: opening Dashboard shows CustomBottomBar',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildRootWidget(flavor: AppFlavor.headunit));
    await tester.pump();

    // Tap on Full Dashboard button
    final dashboardBtn = find.text('Full Dashboard');
    expect(dashboardBtn, findsOneWidget);
    await tester.tap(dashboardBtn);
    await tester.pump();

    // Verify DashboardScreen is mounted and CustomBottomBar is now visible
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(CustomBottomBar), findsOneWidget);

    // Tapping Home in CustomBottomBar should return to HeadunitLauncherScreen
    final homeIcon = find.text('Home');
    expect(homeIcon, findsOneWidget);
    await tester.tap(homeIcon);
    await tester.pump();

    expect(find.byType(CustomBottomBar), findsNothing);
    expect(find.byType(HeadunitLauncherScreen), findsOneWidget);
  });

  testWidgets('Headunit navigation: opening Trip History shows TripsScreen',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildRootWidget(flavor: AppFlavor.headunit));
    await tester.pump();

    final tripsBtn = find.text('Trip History');
    expect(tripsBtn, findsOneWidget);
    await tester.tap(tripsBtn);
    await tester.pump();

    expect(find.byType(TripsScreen), findsOneWidget);
    expect(find.byType(CustomBottomBar), findsOneWidget);
  });

  testWidgets('Headunit navigation: opening Connections shows ConnectionScreen',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildRootWidget(flavor: AppFlavor.headunit));
    await tester.pump();

    final connBtn = find.byKey(const Key('open_connections_button'));
    expect(connBtn, findsOneWidget);
    await tester.tap(connBtn);
    await tester.pump();

    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.byType(CustomBottomBar), findsOneWidget);
  });

  testWidgets('Phone flavor mounts HomeScreen as index 0 with bottom bar',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildRootWidget(flavor: AppFlavor.phone));
    await tester.pump();

    // Verify HomeScreen is present and HeadunitLauncherScreen is not
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(HeadunitLauncherScreen), findsNothing);

    // Verify CustomBottomBar is visible on phone home
    expect(find.byType(CustomBottomBar), findsOneWidget);
  });
}
