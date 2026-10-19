import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/car_screen.dart';
import 'package:redrive/services/garage/auto_data_spec_parser.dart';
import 'package:redrive/services/garage/garage_service.dart';
import 'package:redrive/services/gps/gps_location_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_anomaly_detector.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';

/// Test double implementing [TripProvider] without background periodic ticker
/// to allow deterministic widget testing and instantaneous settle.
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

  const mockAutoDataHtml = '''
<!DOCTYPE html>
<html>
<body>
  <table>
    <tbody>
      <tr><th scope="row">Brand</th><td>Mazda</td></tr>
      <tr><th scope="row">Model</th><td>MX-5</td></tr>
      <tr><th scope="row">Generation</th><td>MX-5 IV (ND)</td></tr>
      <tr><th scope="row">Modification (Engine)</th><td>2.0 SKYACTIV-G (160 Hp)</td></tr>
      <tr><th scope="row">Start of production</th><td>2015 year</td></tr>
      <tr><th scope="row">Fuel Type</th><td>Petrol (Gasoline)</td></tr>
      <tr><th scope="row">Power</th><td>160 Hp @ 6000 rpm.</td></tr>
      <tr><th scope="row">Engine displacement</th><td>1998 cm<sup>3</sup></td></tr>
      <tr><th scope="row">Fuel tank capacity</th><td>45 l</td></tr>
      <tr><th scope="row">Kerb Weight</th><td>1000 kg</td></tr>
      <tr><th scope="row">Redline RPM</th><td>6800 rpm</td></tr>
    </tbody>
  </table>
</body>
</html>
''';

  late GarageService garageService;
  late AutoDataSpecParser specParser;
  late GarageProvider garageProvider;
  late ObdProvider obdProvider;
  late FakeTripProvider tripProvider;

  setUp(() async {
    garageService = GarageService(inMemory: true);
    specParser = AutoDataSpecParser(
      httpFetcher: (_) async => mockAutoDataHtml,
    );
    garageProvider = GarageProvider(
      garageService: garageService,
      specParser: specParser,
    );
    obdProvider = ObdProvider();
    tripProvider = FakeTripProvider();

    garageProvider.bindProviders(
      obdProvider: obdProvider,
      tripProvider: tripProvider,
    );

    await garageProvider.initialized;
  });

  tearDown(() {
    obdProvider.dispose();
    tripProvider.dispose();
    garageProvider.dispose();
  });

  Widget buildTestWidget({
    GarageProvider? gProvider,
    TripProvider? tProvider,
    ObdProvider? oProvider,
  }) {
    return MultiProvider(
      providers: [
        if (gProvider != null)
          ChangeNotifierProvider<GarageProvider>.value(value: gProvider),
        if (tProvider != null)
          ChangeNotifierProvider<TripProvider>.value(value: tProvider),
        if (oProvider != null)
          ChangeNotifierProvider<ObdProvider>.value(value: oProvider),
      ],
      child: const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CarScreen(),
      ),
    );
  }

  testWidgets('renders header, default Suzuki Swift card and maintenance items',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget(
      gProvider: garageProvider,
      tProvider: tripProvider,
      oProvider: obdProvider,
    ));
    await tester.pumpAndSettle();

    // Verify Header (AppLocalizations.garageTitle is 'My Garage')
    expect(find.text('My Garage'), findsOneWidget);
    expect(find.text('VEHICLE PROFILES & MAINTENANCE'), findsOneWidget);
    expect(find.byKey(const Key('garage_add_vehicle_button')), findsOneWidget);

    // Verify Active Profile Card
    expect(
      find.byKey(const Key('vehicle_card_default_swift_m15a')),
      findsOneWidget,
    );
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Suzuki Swift 3 (M15A 1.5L) • 2007'), findsOneWidget);

    // Verify Core Specs
    expect(find.text('1.5L'), findsOneWidget);
    expect(find.text('Gasoline'), findsOneWidget);
    expect(find.text('45L'), findsOneWidget);
    expect(find.text('102 HP'), findsOneWidget);
    expect(find.text('6500 RPM'), findsOneWidget);
    expect(find.text('102°C'), findsOneWidget);
    expect(find.text('150000 km'), findsOneWidget);

    // Verify Maintenance Tracker Section
    expect(find.text('MAINTENANCE TRACKER'), findsOneWidget);
    expect(find.text('Engine Oil & Filter'), findsOneWidget);
    expect(find.text('Air & Cabin Filters'), findsOneWidget);
    expect(find.text('Spark Plugs'), findsOneWidget);
    expect(find.text('Valve Clearance Check'), findsOneWidget);
    expect(find.text('Every 10,000 km'), findsOneWidget);
    expect(find.text('10000 km remaining'), findsOneWidget);
    expect(find.text('OK'), findsNWidgets(4));
    expect(find.byKey(const Key('service_done_oil_filter')), findsOneWidget);
  });

  testWidgets('tapping Service Done updates maintenance record',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget(
      gProvider: garageProvider,
      tProvider: tripProvider,
      oProvider: obdProvider,
    ));
    await tester.pumpAndSettle();

    final serviceBtn = find.byKey(const Key('service_done_oil_filter'));
    await tester.ensureVisible(serviceBtn);
    await tester.tap(serviceBtn);
    await tester.pumpAndSettle();

    final active = garageProvider.activeProfile;
    final item =
        active.maintenanceItems.firstWhere((i) => i.id == 'oil_filter');
    expect(item.lastServiceOdometerKm, equals(150000.0));
    expect(item.lastServiceDate, isNotNull);
  });

  testWidgets(
      'add vehicle modal with auto-data URL auto-fill and manual save',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget(
      gProvider: garageProvider,
      tProvider: tripProvider,
      oProvider: obdProvider,
    ));
    await tester.pumpAndSettle();

    // Tap + Add Vehicle button
    await tester.tap(find.byKey(const Key('garage_add_vehicle_button')));
    await tester.pumpAndSettle();

    // Modal sheet should be visible
    expect(find.text('Add New Vehicle'), findsOneWidget);
    expect(find.byKey(const Key('autodata_url_input')), findsOneWidget);
    expect(find.byKey(const Key('autodata_fetch_button')), findsOneWidget);

    // Paste auto-data URL and click Auto-Fill
    await tester.enterText(
      find.byKey(const Key('autodata_url_input')),
      'https://www.auto-data.net/en/mazda-mx-5-iv-nd-2.0-160hp-21950',
    );
    await tester.tap(find.byKey(const Key('autodata_fetch_button')));
    await tester.pumpAndSettle();

    // Verify auto-filled specs
    expect(find.text('2.0'), findsOneWidget);
    expect(find.text('160'), findsOneWidget);
    expect(find.text('6800'), findsOneWidget);

    // Edit fields manually
    await tester.enterText(
      find.byKey(const Key('vehicle_name_input')),
      'Mazda MX-5 ND 2.0',
    );
    await tester.enterText(
      find.byKey(const Key('vehicle_odometer_input')),
      '30000',
    );

    // Save vehicle
    final saveBtn = find.byKey(const Key('save_vehicle_button'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Modal is closed and 2 vehicles exist in garage
    expect(garageProvider.profiles.length, equals(2));
    final newProfile = garageProvider.activeProfile;
    expect(newProfile.name, equals('Mazda MX-5 ND 2.0'));
    expect(newProfile.displacementLiters, equals(2.0));
    expect(newProfile.baseOdometerKm, equals(30000.0));

    // Card should appear and be active
    expect(find.text('Mazda MX-5 ND 2.0 • 2015'), findsOneWidget);
    expect(find.byKey(Key('vehicle_card_${newProfile.id}')), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);

    // Providers updated to new vehicle
    expect(obdProvider.vehicleProfile.name, equals('Mazda MX-5 ND 2.0'));
    expect(tripProvider.activeVehicleProfile.name, equals('Mazda MX-5 ND 2.0'));
    expect(tripProvider.fuelCalculator.displacementLiters, equals(2.0));
    expect(tripProvider.effectiveOdometerKm, equals(30000.0));
  });

  testWidgets('switching active vehicle updates ObdProvider and TripProvider',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Add second profile
    final hondaCivic = VehicleProfile(
      id: 'honda_civic_profile',
      name: 'Honda Civic Type R',
      year: 2018,
      displacementLiters: 2.0,
      fuelType: FuelType.gasoline,
      fuelTankCapacityLiters: 47.0,
      coolantOverheatTempC: 104,
      maxHorsepower: 320,
      baseOdometerKm: 45000.0,
    );
    await garageProvider.saveProfile(hondaCivic, setAsActive: false);

    await tester.pumpWidget(buildTestWidget(
      gProvider: garageProvider,
      tProvider: tripProvider,
      oProvider: obdProvider,
    ));
    await tester.pumpAndSettle();

    // Active vehicle is currently Suzuki Swift
    expect(garageProvider.activeProfileId, equals('default_swift_m15a'));
    expect(obdProvider.vehicleProfile.id, equals('default_swift_m15a'));

    // Select Honda Civic
    final selectBtn =
        find.byKey(const Key('select_vehicle_honda_civic_profile'));
    await tester.ensureVisible(selectBtn);
    await tester.tap(selectBtn);
    await tester.pumpAndSettle();

    // Verify Honda Civic is now active
    expect(garageProvider.activeProfileId, equals('honda_civic_profile'));
    expect(obdProvider.vehicleProfile.id, equals('honda_civic_profile'));
    expect(obdProvider.vehicleProfile.fuelTankCapacityLiters, equals(47.0));
    expect(tripProvider.activeVehicleProfile.id, equals('honda_civic_profile'));
    expect(tripProvider.fuelCalculator.displacementLiters, equals(2.0));
    expect(tripProvider.effectiveOdometerKm, equals(45000.0));
  });

  testWidgets('editing existing vehicle updates its profile', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget(
      gProvider: garageProvider,
      tProvider: tripProvider,
      oProvider: obdProvider,
    ));
    await tester.pumpAndSettle();

    // Tap edit button on Suzuki Swift
    final editBtn = find.byKey(const Key('edit_vehicle_default_swift_m15a'));
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    expect(find.text('Edit Vehicle Profile'), findsOneWidget);

    // Change vehicle name
    await tester.enterText(
      find.byKey(const Key('vehicle_name_input')),
      'Suzuki Swift Sport (Tuned)',
    );

    // Save changes
    final saveBtn = find.byKey(const Key('save_vehicle_button'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Verify updated name renders
    expect(find.text('Suzuki Swift Sport (Tuned) • 2007'), findsOneWidget);
    expect(
      garageProvider.activeProfile.name,
      equals('Suzuki Swift Sport (Tuned)'),
    );
  });

  testWidgets('deleting vehicle removes it from list and state',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final secondaryVehicle = VehicleProfile(
      id: 'secondary_car',
      name: 'Secondary Car',
      year: 2012,
    );
    await garageProvider.saveProfile(secondaryVehicle, setAsActive: false);

    await tester.pumpWidget(buildTestWidget(
      gProvider: garageProvider,
      tProvider: tripProvider,
      oProvider: obdProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vehicle_card_secondary_car')), findsOneWidget);
    expect(
      find.byKey(const Key('delete_vehicle_secondary_car')),
      findsOneWidget,
    );

    // Delete secondary car
    await tester.tap(find.byKey(const Key('delete_vehicle_secondary_car')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vehicle_card_secondary_car')), findsNothing);
    expect(garageProvider.profiles.length, equals(1));
  });

  testWidgets('renders standalone cleanly without GarageProvider ancestor',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(
      home: CarScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Garage'), findsOneWidget);
    expect(
      find.byKey(const Key('vehicle_card_default_swift_m15a')),
      findsOneWidget,
    );
    expect(find.text('ACTIVE'), findsOneWidget);
  });
}
