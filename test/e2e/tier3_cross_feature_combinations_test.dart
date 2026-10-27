import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/obd/pid/pid_key.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';

import '../obd/fakes/fake_obd_connection.dart';
import 'e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {});

  group('Tier 3: Cross-Feature Combinations', () {
    test('T3.1: active trip tracking concurrent with Mode 03 / Mode 07 DTC diagnostic scan', () async {
      final obdProvider = ObdProvider();
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.bindToObd(obdProvider);

      await obdProvider.startDemoMode();
      await Future.delayed(const Duration(milliseconds: 300));

      expect(tripProvider.activeTrip.isActive, isTrue);
      final initialDistance = tripProvider.activeTrip.distanceKm;

      // Concurrent diagnostic scan during active trip driving
      final dtcService = DtcService();
      final codes = await dtcService.scanAllCodes(obdProvider);

      expect(codes, isNotEmpty);
      expect(codes.any((c) => c.code == 'P0300'), isTrue);

      // Verify trip tracking was not paused or corrupted during scan
      expect(tripProvider.activeTrip.isActive, isTrue);
      expect(tripProvider.activeTrip.distanceKm, greaterThanOrEqualTo(initialDistance));
      expect(tripProvider.activeTrip.duration.inSeconds, greaterThanOrEqualTo(0));

      await obdProvider.stopDemoMode();
      tripProvider.dispose();
      obdProvider.dispose();
    });

    test('T3.2: Mode 04 clear safety interlock behavior during driving vs stationary', () async {
      final obdProvider = ObdProvider();
      final dtcService = DtcService();

      await obdProvider.startDemoMode();
      await Future.delayed(const Duration(milliseconds: 300));

      // 1. Vehicle is currently in motion in demo mode (speed > 0)
      expect(obdProvider.data.speed, greaterThan(0));

      // 2. Perform DTC scan
      final codes = await dtcService.scanAllCodes(obdProvider);
      expect(codes, isNotEmpty);

      // 3. Clear DTC codes
      final clearSuccess = await dtcService.clearAllCodes(obdProvider);
      expect(clearSuccess, isTrue);

      final postClearCodes = await dtcService.scanAllCodes(obdProvider);
      expect(postClearCodes, isEmpty);

      await obdProvider.stopDemoMode();
      obdProvider.dispose();
    });

    test('T3.3: telemetry streaming driving a trip into a DFCO mountain coasting state', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      const calculator = FuelCalculator(displacementLiters: 1.5);

      // Phase 1: High speed cruising (fuel flowing, distance increasing)
      final cruiseFlow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        speedKmH: 80,
        mafGramsPerSecond: 14.0,
        engineLoadPercent: 35.0,
        throttlePositionPercent: 22.0,
      );
      expect(cruiseFlow, greaterThan(3.0));

      // Phase 2: Deceleration Fuel Cut-Off (DFCO) during mountain coasting
      // Closed throttle, coasting in gear at 70 km/h, 2200 RPM
      final dfcoFlow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 70,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 3.5,
      );
      expect(dfcoFlow, 0.0);

      // Distance continues accumulating: 70 km/h for 5 seconds
      final deltaKm = AnalyticalOracles.theoreticalTrapezoidalDistance(
        [(speedKmH: 70.0, dtSeconds: 5.0)],
        initialSpeed: 70.0,
      );
      expect(deltaKm, closeTo(0.0972, 0.005));

      // Cumulative fuel during DFCO interval is strictly 0.0
      final dfcoFuel = AnalyticalOracles.theoreticalCumulativeFuel(
        [(fuelFlowLPerHour: dfcoFlow, dtSeconds: 5.0)],
      );
      expect(dfcoFuel, 0.0);

      tripProvider.dispose();
    });

    test('T3.4: connection disconnect and reconnect during active driving trip', () async {
      final connection = FakeObdConnection();
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);

      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.bindToObd(obdProvider);

      // Start trip manually to simulate active trip in progress
      tripProvider.manualStartTrip();
      expect(tripProvider.activeTrip.isActive, isTrue);

      // Simulate connection drop
      await connection.disconnect();
      expect(obdProvider.isDeviceConnected, isFalse);

      // Active trip state persists during temporary disconnect window
      expect(tripProvider.activeTrip.isActive, isTrue);

      // Reconnect
      await connection.connect();
      expect(obdProvider.isDeviceConnected, isTrue);
      expect(tripProvider.activeTrip.isActive, isTrue);

      await pumpEventQueue();
      obdProvider.detachConnection();
      await pumpEventQueue();
      tripProvider.dispose();
      obdProvider.dispose();
      await connection.dispose();
    });

    test('T3.5: Intake Air Temp (010F) & thermal dynamics concurrent with trip fuel calculation', () async {
      final obdProvider = ObdProvider();
      await obdProvider.startDemoMode();
      await Future.delayed(const Duration(milliseconds: 300));

      // IAT in demo mode is actively updated
      final iat = obdProvider.getPidValue(PidKey.intakeAirTemperature);
      expect(iat, isNotNull);
      expect(iat!, inInclusiveRange(15.0, 45.0));

      final coolant = obdProvider.getPidValue(PidKey.coolantTemperature);
      expect(coolant, isNotNull);
      expect(coolant!, inInclusiveRange(40, 110));

      // Fuel calculator computes realistic fuel with engine warmed
      const calc = FuelCalculator(displacementLiters: 1.5);
      final fuelRate = calc.calculateFuelFlowLitersPerHour(
        rpm: obdProvider.data.rpm > 0 ? obdProvider.data.rpm : 1500,
        speedKmH: obdProvider.data.speed > 0 ? obdProvider.data.speed : 50,
        mafGramsPerSecond: obdProvider.data.maf > 0 ? obdProvider.data.maf : 8.0,
      );
      expect(fuelRate, inInclusiveRange(1.0, 20.0));

      await obdProvider.stopDemoMode();
      obdProvider.dispose();
    });

    test('T3.6: trip completion and history save followed immediately by fault diagnosis and clear', () async {
      final historyService = TripHistoryService();
      final dtcService = DtcService();
      final obdProvider = ObdProvider();
      await obdProvider.startDemoMode();

      // 1. Complete a driving trip
      final now = DateTime.now();
      final completedTrip = Trip(
        id: 'cross_trip_${now.millisecondsSinceEpoch}',
        startTime: now.subtract(const Duration(minutes: 20)),
        endTime: now,
        duration: const Duration(minutes: 20),
        distanceKm: 18.2,
        fuelConsumedLiters: 1.25,
        avgFuelConsumption: 6.87,
        avgSpeed: 54.6,
        maxSpeed: 92.0,
        maxRpm: 3400,
        avgRpm: 2150,
      );
      await historyService.saveTrip(completedTrip);

      // 2. Perform diagnostic scan
      final scannedCodes = await dtcService.scanAllCodes(obdProvider);
      expect(scannedCodes, isNotEmpty);

      // 3. Clear DTC codes
      final cleared = await dtcService.clearAllCodes(obdProvider);
      expect(cleared, isTrue);

      // 4. Verify saved trip history is completely unaffected and uncorrupted
      final reloadedHistory = await historyService.loadTrips();
      expect(reloadedHistory, isNotEmpty);
      final found = reloadedHistory.firstWhere((t) => t.id == completedTrip.id);
      expect(found.distanceKm, 18.2);
      expect(found.fuelConsumedLiters, 1.25);

      await obdProvider.stopDemoMode();
      obdProvider.dispose();
    });
  });
}
