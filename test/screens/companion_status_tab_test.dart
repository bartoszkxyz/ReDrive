import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/sync_models.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/trip_route_point.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/garage_provider.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/screens/companion/companion_status_tab.dart';
import 'package:obdrive/services/garage/garage_service.dart';
import 'package:obdrive/services/gps/gps_location_service.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';
import 'package:obdrive/services/trip/trip_anomaly_detector.dart';
import 'package:obdrive/services/trip/trip_timeseries_service.dart';
import 'package:obdrive/widget/companion/parked_car_map_card.dart';

class _FakeTripProvider extends ChangeNotifier implements TripProvider {
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

  _FakeTripProvider({
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
  }) async {}

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

  final fixedTime = DateTime(2026, 10, 19, 14, 30);

  final testTrip = Trip(
    id: 'trip_latest_01',
    startTime: fixedTime.subtract(const Duration(hours: 1)),
    endTime: fixedTime,
    duration: const Duration(minutes: 42),
    distanceKm: 32.5,
    fuelConsumedLiters: 2.1,
    avgFuelConsumption: 6.5,
    avgSpeed: 46.4,
    maxSpeed: 95.0,
    maxRpm: 4200,
    avgRpm: 2100,
    problemCount: 2,
  );

  final testSnapshot = ParkedCarSnapshot(
    timestamp: fixedTime,
    vehicleId: 'swift_07',
    vehicleName: 'Suzuki Swift Sport',
    latitude: 42.6977,
    longitude: 23.3219,
    remainingFuelLiters: 35.0,
    fuelLevelPercent: 78.0,
    estimatedRangeKm: 514.0,
    batteryVoltage: 12.6,
    coolantTempC: 85.0,
    odometerKm: 154200.0,
  );

  Widget createStatusTabWidget({
    required SyncProvider syncProvider,
    required GarageProvider garageProvider,
    required TripProvider tripProvider,
    void Function(int)? onNavigateTab,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
        ChangeNotifierProvider<GarageProvider>.value(value: garageProvider),
        ChangeNotifierProvider<TripProvider>.value(value: tripProvider),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: CompanionStatusTab(onNavigateTab: onNavigateTab),
        ),
      ),
    );
  }

  group('CompanionStatusTab', () {
    testWidgets('renders ParkedCarMapCard, LatestDriveCard, and UpcomingServiceBanner',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final syncService = BluetoothSyncService(
        deviceId: 'phone_test',
        deviceRole: 'phone',
        inMemory: true,
      );
      await syncService.updateParkedSnapshot(testSnapshot);

      final syncProvider = SyncProvider(syncService: syncService);
      final garageProvider = GarageProvider(
        garageService: GarageService(inMemory: true),
      );
      final tripProvider = _FakeTripProvider(
        pastTrips: [testTrip],
        totalDistance: 100.0,
      );

      await tester.pumpWidget(createStatusTabWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
      ));
      await tester.pumpAndSettle();

      // Top: ParkedCarMapCard
      expect(find.byType(ParkedCarMapCard), findsOneWidget);
      expect(find.text('Suzuki Swift Sport'), findsOneWidget);

      // Middle: LatestDriveCard
      expect(find.byKey(const Key('latest_drive_card')), findsOneWidget);
      expect(find.text('Latest Drive'), findsOneWidget);
      expect(find.text('32.5 km'), findsOneWidget);
      expect(find.text('42 min'), findsOneWidget);
      expect(find.text('6.5 L/100km'), findsOneWidget);
      expect(find.text('2 problems'), findsOneWidget);

      // Bottom: UpcomingServiceBanner (clean default maintenance items)
      expect(find.byKey(const Key('upcoming_service_banner')), findsOneWidget);
      expect(find.text('All scheduled maintenance up to date'), findsOneWidget);

      syncProvider.dispose();
      garageProvider.dispose();
      tripProvider.dispose();
    });

    testWidgets('LatestDriveCard displays empty state when no trips exist',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final syncService = BluetoothSyncService(
        deviceId: 'phone_test',
        deviceRole: 'phone',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);
      final garageProvider = GarageProvider(
        garageService: GarageService(inMemory: true),
      );
      final tripProvider = _FakeTripProvider(pastTrips: []);

      await tester.pumpWidget(createStatusTabWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('latest_drive_card')), findsOneWidget);
      expect(
        find.text(
          'No trips recorded yet. Complete a drive with OBDrive Headunit to see trip summaries and GPS telemetry here.',
        ),
        findsOneWidget,
      );

      syncProvider.dispose();
      garageProvider.dispose();
      tripProvider.dispose();
    });

    testWidgets('tapping View Trip on LatestDriveCard triggers navigation callback to tab 1',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final syncService = BluetoothSyncService(
        deviceId: 'phone_test',
        deviceRole: 'phone',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);
      final garageProvider = GarageProvider(
        garageService: GarageService(inMemory: true),
      );
      final tripProvider = _FakeTripProvider(pastTrips: [testTrip]);

      int? navigatedIndex;
      await tester.pumpWidget(createStatusTabWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
        onNavigateTab: (idx) => navigatedIndex = idx,
      ));
      await tester.pumpAndSettle();

      final viewTripBtn = find.text('View Trip');
      expect(viewTripBtn, findsOneWidget);
      await tester.tap(viewTripBtn);
      await tester.pumpAndSettle();

      expect(navigatedIndex, equals(1));

      syncProvider.dispose();
      garageProvider.dispose();
      tripProvider.dispose();
    });

    testWidgets('UpcomingServiceBanner shows alert card and triggers navigation to tab 2 when service is due',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final syncService = BluetoothSyncService(
        deviceId: 'phone_test',
        deviceRole: 'phone',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);
      final garageProvider = GarageProvider(
        garageService: GarageService(inMemory: true),
      );

      // Create a profile with an overdue maintenance item
      final profileWithDue = VehicleProfile.defaultSuzukiSwiftM15A().copyWith(
        baseOdometerKm: 160000.0,
        maintenanceItems: [
          const MaintenanceItem(
            id: 'oil_change',
            name: 'Engine Oil & Filter',
            intervalKm: 10000.0,
            lastServiceOdometerKm: 149500.0, // next due at 159500, odo is 160000 -> overdue by 500 km
          ),
        ],
      );
      await garageProvider.saveProfile(profileWithDue, setAsActive: true);

      final tripProvider = _FakeTripProvider(
        activeVehicleProfile: profileWithDue,
        totalDistance: 0.0,
      );

      int? navigatedIndex;
      await tester.pumpWidget(createStatusTabWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
        onNavigateTab: (idx) => navigatedIndex = idx,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Engine Oil & Filter'), findsOneWidget);
      expect(find.text('Overdue by 500 km'), findsOneWidget);

      final viewGarageBtn = find.text('View Garage');
      expect(viewGarageBtn, findsOneWidget);
      await tester.tap(viewGarageBtn);
      await tester.pumpAndSettle();

      expect(navigatedIndex, equals(2));

      syncProvider.dispose();
      garageProvider.dispose();
      tripProvider.dispose();
    });
  });
}
