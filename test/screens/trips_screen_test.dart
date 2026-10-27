import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/trip_route_point.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/screens/trips_screen.dart';
import 'package:obdrive/services/gps/gps_location_service.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';
import 'package:obdrive/services/trip/trip_anomaly_detector.dart';
import 'package:obdrive/services/trip/trip_timeseries_service.dart';

/// Test double implementing [TripProvider] for deterministic widget testing of [TripsScreen].
class FakeTripProvider extends ChangeNotifier implements TripProvider {
  @override
  List<Trip> pastTrips;

  @override
  ActiveTripState activeTrip;

  bool exportCalled = false;
  Trip? exportedTrip;
  TimeseriesExportFormat? exportedFormat;
  List<String> exportResult;

  FakeTripProvider({
    this.pastTrips = const [],
    ActiveTripState? activeTrip,
    this.exportResult = const [
      '/storage/emulated/0/Download/OBDrive/obdrive_trip.csv',
      '/storage/emulated/0/Download/OBDrive/obdrive_trip.json',
    ],
  }) : activeTrip = activeTrip ?? ActiveTripState.initial();

  VehicleProfile _profile = VehicleProfile.defaultSuzukiSwiftM15A();
  final GpsLocationService _gpsService = GpsLocationService();
  GpsFix? _latestFix;

  @override
  VehicleProfile get activeVehicleProfile => _profile;

  @override
  FuelCalculator get fuelCalculator =>
      FuelCalculator.fromVehicleProfile(_profile);

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
  }) async {
    exportCalled = true;
    exportedTrip = trip;
    exportedFormat = format;
    return exportResult;
  }

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
  Widget createTripsScreen(TripProvider provider) {
    return ChangeNotifierProvider<TripProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: TripsScreen(),
      ),
    );
  }

  group('TripsScreen Milestone 4 Widget Tests', () {
    testWidgets('clean trip renders "0 problems, 0 suspicions"', (tester) async {
      final cleanTrip = Trip(
        id: 'clean-trip-1',
        startTime: DateTime(2026, 10, 17, 10, 0),
        endTime: DateTime(2026, 10, 17, 10, 30),
        duration: const Duration(minutes: 30),
        distanceKm: 18.5,
        fuelConsumedLiters: 1.25,
        avgFuelConsumption: 6.75,
        avgSpeed: 37.0,
        maxSpeed: 75.0,
        maxRpm: 2800,
        avgRpm: 1900,
        problemCount: 0,
        suspicionCount: 0,
        anomalies: const [],
      );

      final provider = FakeTripProvider(pastTrips: [cleanTrip]);

      await tester.pumpWidget(createTripsScreen(provider));
      await tester.pumpAndSettle();

      expect(find.text('0 problems, 0 suspicions'), findsOneWidget);
      expect(find.text('18.50 km'), findsOneWidget);
      expect(find.text('6.8 L/100'), findsNWidgets(2));
    });

    testWidgets(
      'trip with anomalies renders "1 problem occurred, 2 suspicious behaviours" and expands on tap to show episode titles',
      (tester) async {
        final now = DateTime(2026, 10, 17, 14, 0);
        final anomalyTrip = Trip(
          id: 'anomaly-trip-1',
          startTime: now.subtract(const Duration(minutes: 45)),
          endTime: now,
          duration: const Duration(minutes: 45),
          distanceKm: 32.0,
          fuelConsumedLiters: 2.4,
          avgFuelConsumption: 7.5,
          avgSpeed: 42.6,
          maxSpeed: 95.0,
          maxRpm: 4200,
          avgRpm: 2300,
          problemCount: 1,
          suspicionCount: 2,
          recordedDtcs: const ['P0300'],
          anomalies: [
            TripAnomalyEpisode(
              id: 'ep-1',
              severity: AnomalySeverity.problem,
              category: AnomalyCategory.powerLoss,
              title: 'High RPM Power Loss',
              description: 'Engine load shortfall under hard acceleration',
              startTime: now.subtract(const Duration(minutes: 20)),
              endTime: now.subtract(const Duration(minutes: 19, seconds: 50)),
              peakMetrics: {'rpm': 3800, 'load': 38.5},
            ),
            TripAnomalyEpisode(
              id: 'ep-2',
              severity: AnomalySeverity.suspicion,
              category: AnomalyCategory.fuelTrim,
              title: 'STFT Lean Spike',
              description: 'Fuel trim exceeded +10% threshold',
              startTime: now.subtract(const Duration(minutes: 15)),
              endTime: now.subtract(const Duration(minutes: 14, seconds: 45)),
              peakMetrics: {'stft': 12.5},
            ),
            TripAnomalyEpisode(
              id: 'ep-3',
              severity: AnomalySeverity.suspicion,
              category: AnomalyCategory.thermal,
              title: 'Coolant Temp Elevation',
              description: 'Coolant reached 101°C',
              startTime: now.subtract(const Duration(minutes: 5)),
              endTime: now.subtract(const Duration(minutes: 4)),
              peakMetrics: {'coolantTemp': 101},
            ),
          ],
        );

        final provider = FakeTripProvider(pastTrips: [anomalyTrip]);

        await tester.pumpWidget(createTripsScreen(provider));
        await tester.pumpAndSettle();

        // Check health summary badge text
        expect(
          find.text('1 problem occurred, 2 suspicious behaviours'),
          findsOneWidget,
        );

        // Episode details should NOT be visible before expanding
        expect(find.text('High RPM Power Loss'), findsNothing);
        expect(find.text('STFT Lean Spike'), findsNothing);
        expect(find.text('Coolant Temp Elevation'), findsNothing);
        expect(find.text('Recorded DTCs: P0300'), findsNothing);

        // Tap to expand
        await tester.tap(find.text('1 problem occurred, 2 suspicious behaviours'));
        await tester.pumpAndSettle();

        // Episode details should now be visible
        expect(find.text('High RPM Power Loss'), findsOneWidget);
        expect(find.text('STFT Lean Spike'), findsOneWidget);
        expect(find.text('Coolant Temp Elevation'), findsOneWidget);
        expect(find.text('Recorded DTCs: P0300'), findsOneWidget);
        expect(
          find.text('Engine load shortfall under hard acceleration'),
          findsOneWidget,
        );

        // Tap again to collapse
        await tester.tap(find.text('1 problem occurred, 2 suspicious behaviours'));
        await tester.pumpAndSettle();

        expect(find.text('High RPM Power Loss'), findsNothing);
      },
    );

    testWidgets(
      'trip with hasTimeseries: true shows "Timeseries Recorded" and "Export Timeseries" button, while an older trip with hasTimeseries: false hides the export button',
      (tester) async {
        final recentTrip = Trip(
          id: 'recent-trip',
          startTime: DateTime(2026, 10, 17, 12, 0),
          endTime: DateTime(2026, 10, 17, 12, 25),
          duration: const Duration(minutes: 25),
          distanceKm: 15.0,
          fuelConsumedLiters: 1.1,
          avgFuelConsumption: 7.3,
          avgSpeed: 36.0,
          maxSpeed: 70.0,
          maxRpm: 2600,
          avgRpm: 1800,
          hasTimeseries: true,
          isExported: false,
        );

        final olderTrip = Trip(
          id: 'older-trip',
          startTime: DateTime(2026, 10, 16, 8, 0),
          endTime: DateTime(2026, 10, 16, 8, 40),
          duration: const Duration(minutes: 40),
          distanceKm: 25.0,
          fuelConsumedLiters: 1.8,
          avgFuelConsumption: 7.2,
          avgSpeed: 37.5,
          maxSpeed: 80.0,
          maxRpm: 2900,
          avgRpm: 1950,
          hasTimeseries: false,
          isExported: false,
        );

        final provider = FakeTripProvider(pastTrips: [recentTrip, olderTrip]);

        await tester.pumpWidget(createTripsScreen(provider));
        await tester.pumpAndSettle();

        // "Timeseries Recorded" badge should appear only on recentTrip
        expect(find.text('Timeseries Recorded'), findsOneWidget);

        // "Export Timeseries" button should appear only on recentTrip
        expect(find.text('Export Timeseries'), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'triggers timeseries export on button tap and displays SnackBar with "Copy Path"',
      (tester) async {
        final trip = Trip(
          id: 'exportable-trip',
          startTime: DateTime(2026, 10, 17, 9, 0),
          endTime: DateTime(2026, 10, 17, 9, 20),
          duration: const Duration(minutes: 20),
          distanceKm: 10.0,
          fuelConsumedLiters: 0.8,
          avgFuelConsumption: 8.0,
          avgSpeed: 30.0,
          maxSpeed: 60.0,
          maxRpm: 2400,
          avgRpm: 1700,
          hasTimeseries: true,
        );

        final provider = FakeTripProvider(
          pastTrips: [trip],
          exportResult: [
            '/storage/emulated/0/Download/OBDrive/obdrive_trip_1.csv',
            '/storage/emulated/0/Download/OBDrive/obdrive_trip_1.json',
          ],
        );

        await tester.pumpWidget(createTripsScreen(provider));
        await tester.pumpAndSettle();

        final exportButton = find.text('Export Timeseries');
        expect(exportButton, findsOneWidget);

        await tester.tap(exportButton);
        await tester.pumpAndSettle();

        expect(provider.exportCalled, isTrue);
        expect(provider.exportedTrip?.id, 'exportable-trip');
        expect(provider.exportedFormat, TimeseriesExportFormat.both);

        // SnackBar with path and Copy Path action should be visible
        expect(find.textContaining('Exported timeseries:'), findsOneWidget);
        expect(find.text('Copy Path'), findsOneWidget);

        // Tap "Copy Path" action
        await tester.tap(find.text('Copy Path'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('shows "Exported ✓" badge when trip isExported is true', (tester) async {
      final exportedTrip = Trip(
        id: 'already-exported-trip',
        startTime: DateTime(2026, 10, 17, 11, 0),
        endTime: DateTime(2026, 10, 17, 11, 15),
        duration: const Duration(minutes: 15),
        distanceKm: 8.0,
        fuelConsumedLiters: 0.6,
        avgFuelConsumption: 7.5,
        avgSpeed: 32.0,
        maxSpeed: 55.0,
        maxRpm: 2200,
        avgRpm: 1600,
        hasTimeseries: true,
        isExported: true,
      );

      final provider = FakeTripProvider(pastTrips: [exportedTrip]);

      await tester.pumpWidget(createTripsScreen(provider));
      await tester.pumpAndSettle();

      expect(find.text('Timeseries Recorded'), findsOneWidget);
      expect(find.text('Exported ✓'), findsOneWidget);
    });

    testWidgets('active trip card displays live health summary badge', (tester) async {
      final activeState = ActiveTripState(
        isActive: true,
        startTime: DateTime(2026, 10, 17, 15, 0),
        duration: const Duration(minutes: 12),
        distanceKm: 7.5,
        fuelConsumedLiters: 0.55,
        avgFuelConsumption: 7.3,
        instantFuelL100km: 6.8,
        instantFuelLPerHour: 3.2,
        avgSpeed: 37.5,
        maxSpeed: 65.0,
        maxRpm: 2900,
        currentSpeed: 45,
        currentRpm: 2100,
        problemCount: 2,
        suspicionCount: 1,
      );

      final provider = FakeTripProvider(
        activeTrip: activeState,
        pastTrips: const [],
      );

      await tester.pumpWidget(createTripsScreen(provider));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE TRIP'), findsOneWidget);
      expect(find.text('2 problems, 1 suspicion'), findsOneWidget);
    });

    testWidgets('shows empty state when no trips are recorded', (tester) async {
      final provider = FakeTripProvider(pastTrips: const []);

      await tester.pumpWidget(createTripsScreen(provider));
      await tester.pumpAndSettle();

      expect(find.text('No Trips Recorded Yet'), findsOneWidget);
    });
  });
}
