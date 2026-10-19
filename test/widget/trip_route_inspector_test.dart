import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/screens/trips_screen.dart';
import 'package:redrive/services/gps/gps_location_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_anomaly_detector.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';
import 'package:redrive/widget/trips/trip_route_inspector.dart';

/// Test double implementing [TripProvider] for widget testing without disk I/O.
class _MockTripProvider extends ChangeNotifier implements TripProvider {
  @override
  List<Trip> pastTrips;

  @override
  ActiveTripState activeTrip;

  _MockTripProvider({
    this.pastTrips = const [],
    ActiveTripState? activeTrip,
  }) : activeTrip = activeTrip ?? ActiveTripState.initial();

  final VehicleProfile _profile = VehicleProfile.defaultSuzukiSwiftM15A();
  final GpsLocationService _gpsService = GpsLocationService();

  @override
  Future<void> Function(Trip trip)? onTripFinished;

  @override
  Future<void> Function()? onSpeedZeroStandstill;

  @override
  VehicleProfile get activeVehicleProfile => _profile;

  @override
  FuelCalculator get fuelCalculator =>
      FuelCalculator.fromVehicleProfile(_profile);

  @override
  GpsLocationService get gpsService => _gpsService;

  @override
  GpsFix? get latestGpsFix => null;

  @override
  List<TripRoutePoint> get activeRoutePoints => activeTrip.routePoints;

  @override
  void updateGpsFix(GpsFix fix) {}

  @override
  void applyVehicleProfile(VehicleProfile profile) {}

  @override
  TripTimeseriesService get timeseriesService => throw UnimplementedError();

  @override
  TripAnomalyDetector get anomalyDetector => throw UnimplementedError();

  @override
  double get minTripDistanceKm => 0.1;

  @override
  bool get autoTripEnabled => true;

  @override
  Future<void> get initialized => Future.value();

  @override
  void bindToObd(ObdProvider obdProvider) {}

  @override
  Future<void> setAutoTripEnabled(bool enabled) async {}

  @override
  Future<void> setMinTripDistanceKm(double km) async {}

  @override
  double get totalDistance =>
      pastTrips.fold(0.0, (acc, t) => acc + t.distanceKm);

  @override
  double get effectiveOdometerKm => totalDistance;

  @override
  double get totalFuelConsumed =>
      pastTrips.fold(0.0, (acc, t) => acc + t.fuelConsumedLiters);

  @override
  double get overallAvgFuel => 6.5;

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
  Future<List<String>> exportTripTimeseries(
    Trip trip, {
    TimeseriesExportFormat format = TimeseriesExportFormat.both,
  }) async {
    return [];
  }

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
  Future<void> clearHistory() async {
    pastTrips = [];
    notifyListeners();
  }

  @override
  Future<void> ingestSyncedTrip(
    Trip trip, {
    List<String>? timeseriesLines,
  }) async {
    pastTrips = [trip, ...pastTrips];
    notifyListeners();
  }

  @override
  Future<void> markTripsAsSynced(
    Iterable<String> tripIds, {
    int maxUnsyncedTrips = 35,
    int maxSyncedTrips = 5,
  }) async {
    final idSet = tripIds.toSet();
    pastTrips = pastTrips
        .map((t) => idSet.contains(t.id) ? t.copyWith(isSynced: true) : t)
        .toList();
    notifyListeners();
  }
}

Trip _createSampleTrip() {
  final now = DateTime(2026, 6, 1, 14, 0, 0);
  final points = [
    const TripRoutePoint(
      latitude: 42.6977,
      longitude: 23.3219,
      speedKmh: 25.0,
      rpm: 1800,
      fuelRateLph: 2.2,
      fuelL100km: 4.8,
      engineLoadPercent: 28.0,
      coolantTempC: 88,
      shortTermFuelTrim: 1.2,
      longTermFuelTrim: 2.5,
      elapsedSeconds: 0.0,
    ),
    const TripRoutePoint(
      latitude: 42.6990,
      longitude: 23.3235,
      speedKmh: 55.0,
      rpm: 2800,
      fuelRateLph: 4.5,
      fuelL100km: 7.2,
      engineLoadPercent: 58.0,
      coolantTempC: 92,
      shortTermFuelTrim: -1.5,
      longTermFuelTrim: 3.0,
      elapsedSeconds: 15.0,
    ),
    const TripRoutePoint(
      latitude: 42.7020,
      longitude: 23.3270,
      speedKmh: 95.0,
      rpm: 4200,
      fuelRateLph: 9.8,
      fuelL100km: 11.5,
      engineLoadPercent: 88.0,
      coolantTempC: 104,
      shortTermFuelTrim: 4.2,
      longTermFuelTrim: 5.1,
      elapsedSeconds: 35.0,
    ),
  ];

  final episode = TripAnomalyEpisode(
    id: 'episode_overheat_42',
    severity: AnomalySeverity.problem,
    category: AnomalyCategory.thermal,
    title: 'Engine Overheating (104°C)',
    description: 'Coolant temperature exceeded critical threshold (>105°C).',
    startTime: now.add(const Duration(seconds: 35)),
    endTime: now.add(const Duration(seconds: 35)),
    latitude: 42.7020,
    longitude: 23.3270,
    elapsedSeconds: 35.0,
  );

  return Trip(
    id: 'trip_inspector_test_1',
    startTime: now,
    endTime: now.add(const Duration(seconds: 35)),
    duration: const Duration(seconds: 35),
    distanceKm: 0.65,
    fuelConsumedLiters: 0.06,
    avgFuelConsumption: 6.8,
    avgSpeed: 58.0,
    maxSpeed: 95.0,
    maxRpm: 4200,
    avgRpm: 2900,
    problemCount: 1,
    suspicionCount: 0,
    anomalies: [episode],
    routePoints: points,
    hasTimeseries: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TripRouteInspector Widget Tests (M3.3)', () {
    testWidgets(
      'renders canvas, mode selector, scrubber slider, and initial telemetry readout',
      (tester) async {
        final trip = _createSampleTrip();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TripRouteInspector(trip: trip),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Vector canvas
        expect(find.byKey(const Key('trip_route_canvas')), findsOneWidget);

        // 2. Color mode toggle buttons
        expect(
          find.byKey(const Key('route_color_mode_speed')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('route_color_mode_rpm')), findsOneWidget);
        expect(
          find.byKey(const Key('route_color_mode_fuel')),
          findsOneWidget,
        );

        // 3. Scrubber slider
        expect(
          find.byKey(const Key('trip_route_scrubber_slider')),
          findsOneWidget,
        );

        // 4. Initial telemetry readout card at point 0
        expect(find.byKey(const Key('scrubber_telemetry_card')), findsOneWidget);
        expect(find.text('25 km/h'), findsOneWidget);
        expect(find.text('1800 RPM'), findsOneWidget);
        expect(find.text('4.8 L/100km'), findsOneWidget);
        expect(find.text('2.2 L/h'), findsOneWidget);
        expect(find.text('28%'), findsOneWidget);
        expect(find.text('88°C'), findsOneWidget);
        expect(find.text('1.2% / 2.5%'), findsOneWidget);
      },
    );

    testWidgets(
      'toggling between Speed, Engine RPM, and Fuel mode buttons updates active color mode cleanly',
      (tester) async {
        final trip = _createSampleTrip();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TripRouteInspector(trip: trip),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mode labels
        expect(find.text('Speed (km/h)'), findsOneWidget);
        expect(find.text('Engine RPM'), findsOneWidget);
        expect(find.text('Fuel (L/100km)'), findsOneWidget);

        // Switch to RPM mode
        await tester.tap(find.byKey(const Key('route_color_mode_rpm')));
        await tester.pumpAndSettle();

        // Switch to Fuel mode
        await tester.tap(find.byKey(const Key('route_color_mode_fuel')));
        await tester.pumpAndSettle();

        // Switch back to Speed mode
        await tester.tap(find.byKey(const Key('route_color_mode_speed')));
        await tester.pumpAndSettle();

        // Still renders without errors
        expect(find.byKey(const Key('trip_route_canvas')), findsOneWidget);
      },
    );

    testWidgets(
      'changing scrubber slider updates displayed Speed, RPM, Coolant, Load, and STFT / LTFT values',
      (tester) async {
        final trip = _createSampleTrip();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TripRouteInspector(trip: trip),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially at index 0
        expect(find.text('25 km/h'), findsOneWidget);
        expect(find.text('88°C'), findsOneWidget);

        // Scrub to point 1 (index 1.0)
        final sliderFinder = find.byKey(const Key('trip_route_scrubber_slider'));
        final slider = tester.widget<Slider>(sliderFinder);
        slider.onChanged?.call(1.0);
        await tester.pumpAndSettle();

        // Point 1 telemetry values
        expect(find.text('55 km/h'), findsOneWidget);
        expect(find.text('2800 RPM'), findsOneWidget);
        expect(find.text('7.2 L/100km'), findsOneWidget);
        expect(find.text('4.5 L/h'), findsOneWidget);
        expect(find.text('58%'), findsOneWidget);
        expect(find.text('92°C'), findsOneWidget);
        expect(find.text('-1.5% / 3.0%'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping anomaly pin chip jumps scrubber to anomaly timestamp and displays details banner',
      (tester) async {
        final trip = _createSampleTrip();
        final episode = trip.anomalies.first;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TripRouteInspector(trip: trip),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final anomalyChipFinder =
            find.byKey(Key('anomaly_pin_${episode.id}'));
        expect(anomalyChipFinder, findsOneWidget);

        // Tap anomaly chip
        await tester.tap(anomalyChipFinder);
        await tester.pumpAndSettle();

        // Scrubber jumped to point 2 (elapsedSeconds 35.0)
        expect(find.text('95 km/h'), findsOneWidget);
        expect(find.text('4200 RPM'), findsOneWidget);
        expect(find.text('104°C'), findsOneWidget);
        expect(find.text('88%'), findsOneWidget);
        expect(find.text('4.2% / 5.1%'), findsOneWidget);

        // Anomaly details banner is displayed
        expect(find.text(episode.title), findsAtLeastNWidgets(1));
        expect(find.text(episode.description), findsOneWidget);

        // Tapping the close icon on the banner dismisses the banner
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.text(episode.description), findsNothing);
      },
    );

    testWidgets(
      'expanding a _PastTripCard with routePoints in TripsScreen displays embedded TripRouteInspector',
      (tester) async {
        final trip = _createSampleTrip();
        final mockProvider = _MockTripProvider(pastTrips: [trip]);

        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<TripProvider>.value(
              value: mockProvider,
              child: const TripsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Route badge is visible
        expect(find.text('GPS Route (3 pts)'), findsOneWidget);

        // Route inspector is not yet expanded
        expect(find.byType(TripRouteInspector), findsNothing);

        // Tap the card to expand it
        await tester.tap(find.text('GPS Route (3 pts)'));
        await tester.pumpAndSettle();

        // Route inspector is now visible inside the card
        expect(find.byType(TripRouteInspector), findsOneWidget);
        expect(find.byKey(const Key('trip_route_canvas')), findsOneWidget);
      },
    );

    testWidgets(
      'TripRouteInspectorSheet.show opens route inspector in modal bottom sheet',
      (tester) async {
        final trip = _createSampleTrip();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => TripRouteInspectorSheet.show(
                    context,
                    trip: trip,
                  ),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.byType(TripRouteInspectorSheet), findsOneWidget);
        expect(find.byKey(const Key('trip_route_canvas')), findsOneWidget);
      },
    );
  });
}
