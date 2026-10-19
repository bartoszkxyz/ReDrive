import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/core/theme/theme_engine.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/car_screen.dart';
import 'package:redrive/screens/companion/companion_settings_sheet.dart';
import 'package:redrive/screens/companion/companion_status_tab.dart';
import 'package:redrive/screens/diagnostics_screen.dart';
import 'package:redrive/screens/phone_companion_screen.dart';
import 'package:redrive/screens/trips_screen.dart';
import 'package:redrive/services/garage/garage_service.dart';
import 'package:redrive/services/gps/gps_location_service.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_anomaly_detector.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';

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

  final testSnapshot = ParkedCarSnapshot(
    timestamp: DateTime(2026, 10, 19, 14, 30),
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

  Widget createPhoneCompanionWidget({
    required SyncProvider syncProvider,
    required GarageProvider garageProvider,
    required TripProvider tripProvider,
    required ObdProvider obdProvider,
    required ThemeEngine themeEngine,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
        ChangeNotifierProvider<GarageProvider>.value(value: garageProvider),
        ChangeNotifierProvider<TripProvider>.value(value: tripProvider),
        ChangeNotifierProvider<ObdProvider>.value(value: obdProvider),
        ChangeNotifierProvider<ThemeEngine>.value(value: themeEngine),
      ],
      child: const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PhoneCompanionScreen(),
      ),
    );
  }

  group('PhoneCompanionScreen', () {
    late BluetoothSyncService syncService;
    late SyncProvider syncProvider;
    late GarageProvider garageProvider;
    late _FakeTripProvider tripProvider;
    late ObdProvider obdProvider;
    late ThemeEngine themeEngine;

    setUp(() async {
      syncService = BluetoothSyncService(
        deviceId: 'phone_test_01',
        deviceRole: 'phone',
        inMemory: true,
      );
      await syncService.updateParkedSnapshot(testSnapshot);

      themeEngine = ThemeEngine(inMemory: true);
      syncProvider = SyncProvider(syncService: syncService, themeEngine: themeEngine);
      garageProvider = GarageProvider(
        garageService: GarageService(inMemory: true),
      );
      tripProvider =
          _FakeTripProvider(pastTrips: const [], totalDistance: 50.0);
      obdProvider = ObdProvider();

      syncProvider.bindProviders(
        tripProvider: tripProvider,
        garageProvider: garageProvider,
        obdProvider: obdProvider,
        themeEngine: themeEngine,
      );
    });

    tearDown(() {
      syncProvider.dispose();
      garageProvider.dispose();
      tripProvider.dispose();
      obdProvider.dispose();
      themeEngine.dispose();
    });

    testWidgets('renders top bar with vehicle switcher, sync pill, and settings button',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createPhoneCompanionWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
        obdProvider: obdProvider,
        themeEngine: themeEngine,
      ));
      await tester.pumpAndSettle();

      // Top bar elements
      expect(find.byKey(const Key('vehicle_switcher_button')), findsOneWidget);
      expect(find.byKey(const Key('companion_sync_pill')), findsOneWidget);
      expect(find.byKey(const Key('companion_settings_button')), findsOneWidget);

      // Default active vehicle name
      expect(find.text(garageProvider.activeProfile.name), findsOneWidget);

      // 4 Bottom Navigation items
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Garage'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);

      // Status tab is mounted initially
      expect(find.byType(CompanionStatusTab), findsOneWidget);
    });

    testWidgets('switching bottom navigation tabs mounts Trips, Garage, and Diagnostics',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createPhoneCompanionWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
        obdProvider: obdProvider,
        themeEngine: themeEngine,
      ));
      await tester.pumpAndSettle();

      // Tap Trips tab
      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();
      expect(find.byType(TripsScreen), findsOneWidget);

      // Tap Garage tab
      await tester.tap(find.text('Garage'));
      await tester.pumpAndSettle();
      expect(find.byType(CarScreen), findsOneWidget);

      // Tap Diagnostics tab
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsScreen), findsOneWidget);

      // Tap Status tab to return
      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionStatusTab), findsOneWidget);
    });

    testWidgets('tapping settings gear opens CompanionSettingsSheet',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createPhoneCompanionWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
        obdProvider: obdProvider,
        themeEngine: themeEngine,
      ));
      await tester.pumpAndSettle();

      final settingsBtn = find.byKey(const Key('companion_settings_button'));
      expect(settingsBtn, findsOneWidget);
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();

      // CompanionSettingsSheet is visible
      expect(find.byType(CompanionSettingsSheet), findsOneWidget);
      expect(find.text('Headunit Sync & Settings'), findsOneWidget);
      expect(find.byKey(const Key('companion_sync_now_button')), findsOneWidget);

      // Theme sideloading section
      expect(find.text('Amber Glow'), findsOneWidget);
      expect(find.text('Cyan Cyber'), findsOneWidget);
      expect(find.text('Emerald Drive'), findsOneWidget);
      expect(find.text('Monochrome Dark'), findsOneWidget);
      expect(find.byKey(const Key('send_theme_button')), findsOneWidget);

      // Diagnostics mechanic report button
      expect(find.byKey(const Key('open_mechanic_report_button')), findsOneWidget);
    });

    testWidgets('tapping vehicle switcher button opens profile selection popup',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Add a second vehicle profile to garage
      final secondCar = const VehicleProfile(
        id: 'miata_nd',
        name: 'Mazda MX-5 Miata',
        displacementLiters: 2.0,
      );
      await garageProvider.saveProfile(secondCar);

      await tester.pumpWidget(createPhoneCompanionWidget(
        syncProvider: syncProvider,
        garageProvider: garageProvider,
        tripProvider: tripProvider,
        obdProvider: obdProvider,
        themeEngine: themeEngine,
      ));
      await tester.pumpAndSettle();

      final switcherBtn = find.byKey(const Key('vehicle_switcher_button'));
      expect(switcherBtn, findsOneWidget);
      await tester.tap(switcherBtn);
      await tester.pumpAndSettle();

      // Popup shows both cars
      expect(find.text('Mazda MX-5 Miata'), findsOneWidget);

      // Select second car
      await tester.tap(find.text('Mazda MX-5 Miata'));
      await tester.pumpAndSettle();

      expect(garageProvider.activeProfile.id, equals('miata_nd'));
    });
  });
}
