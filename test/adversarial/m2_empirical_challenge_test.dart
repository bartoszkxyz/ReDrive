import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('m2_adversarial_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  /// Mathematical assertion helper: verifies relative error strictly < tolerancePercent
  void assertRelativeTolerance({
    required double actual,
    required double expected,
    required String metric,
    double tolerancePercent = 1.0,
  }) {
    if (expected.abs() < 1e-7) {
      expect(
        actual.abs(),
        lessThan(1e-4),
        reason: '$metric: Expected near-zero ($expected), but got $actual',
      );
      return;
    }
    final relativeErrorPercent = ((actual - expected).abs() / expected) * 100.0;
    expect(
      relativeErrorPercent,
      lessThan(tolerancePercent),
      reason: '$metric relative error exceeded tolerance! actual=$actual, '
          'expected=$expected, error=${relativeErrorPercent.toStringAsFixed(4)}% (limit: $tolerancePercent%)',
    );
  }

  group('M2 Challenge Area 1: Exact Analytical Calculus Oracles (< 1.0% Tolerance)', () {
    test('1.1: Polynomial quadratic acceleration profile compared against exact calculus integrals', () async {
      // v(t) = a*t^2 + b*t + c
      // Let t in [0, 60] seconds
      // v(0) = 0 km/h, v(60) = 100 km/h
      // v(t) = (100 / 3600) * t^2 = (1/36) * t^2  (quadratic ramp)
      // Exact analytical distance integral:
      // D = int_0^60 v(t)/3600 dt = (1/3600) * int_0^60 (1/36) * t^2 dt
      //   = (1 / (3600 * 36)) * [t^3 / 3]_0^60
      //   = (1 / 129600) * (216000 / 3) = 72000 / 129600 = 5/9 km ~ 0.55555555 km
      //
      // Fuel flow: f(t) = 1.0 + (12.0 - 1.0) * (t / 60)^2 = 1.0 + (11.0 / 3600) * t^2
      // Exact analytical fuel integral:
      // F = int_0^60 f(t)/3600 dt = (1/3600) * [1.0*t + (11.0/10800)*t^3]_0^60
      //   = (1/3600) * [60.0 + (11.0 * 216000 / 10800)]
      //   = (1/3600) * [60.0 + 220.0] = 280.0 / 3600 ~ 0.07777777 L
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 12, 0, 0);
      const totalSeconds = 60;

      const exactAnalyticalDistanceKm = 5.0 / 9.0;
      const exactAnalyticalFuelLiters = 280.0 / 3600.0;
      const exactAnalyticalAvgSpeedKmH = exactAnalyticalDistanceKm / (totalSeconds / 3600.0);

      // Feed initial t=0 sample
      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 800, engineFuelRate: 1.0),
        timestamp: startTime,
      );

      // Feed samples at 1-second intervals
      for (int t = 1; t <= totalSeconds; t++) {
        final timestamp = startTime.add(Duration(seconds: t));
        final speed = (1.0 / 36.0) * (t * t);
        final fuel = 1.0 + (11.0 / 3600.0) * (t * t);

        tripProvider.processDataPoint(
          ObdData(
            speed: speed.round(),
            rpm: 1000 + (t * 50),
            engineFuelRate: fuel,
            throttlePosition: 10.0 + (t * 0.8),
          ),
          timestamp: timestamp,
        );
      }

      final active = tripProvider.activeTrip;

      // Note: discrete integer rounding of speed produces small discretization,
      // but relative error must still strictly satisfy < 1.0%
      assertRelativeTolerance(
        actual: active.distanceKm,
        expected: exactAnalyticalDistanceKm,
        metric: 'Quadratic Profile Distance',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.fuelConsumedLiters,
        expected: exactAnalyticalFuelLiters,
        metric: 'Quadratic Profile Fuel',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.avgSpeed,
        expected: exactAnalyticalAvgSpeedKmH,
        metric: 'Quadratic Profile Average Speed',
        tolerancePercent: 1.0,
      );

      tripProvider.dispose();
    });

    test('1.2: Harmonic sine wave speed and fuel profile compared against calculus integral', () async {
      // Periodic cycle over T = 60s:
      // v(t) = 60.0 + 20.0 * sin(2*pi*t / 60)
      // f(t) = 5.0 + 2.0 * sin(2*pi*t / 60)
      // Since sin integrates to 0 over full period:
      // Exact analytical distance = 60.0 * 60.0 / 3600 = 1.00000 km
      // Exact analytical fuel = 5.0 * 60.0 / 3600 = 0.0833333 L
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 12, 0, 0);
      const totalSeconds = 60;
      const exactDistanceKm = 1.00000;
      const exactFuelLiters = 5.0 * 60.0 / 3600.0;

      tripProvider.processDataPoint(
        const ObdData(speed: 60, rpm: 2000, engineFuelRate: 5.0),
        timestamp: startTime,
      );

      for (int t = 1; t <= totalSeconds; t++) {
        final timestamp = startTime.add(Duration(seconds: t));
        final angle = (2.0 * pi * t) / 60.0;
        final speed = 60.0 + 20.0 * sin(angle);
        final fuel = 5.0 + 2.0 * sin(angle);

        tripProvider.processDataPoint(
          ObdData(
            speed: speed.round(),
            rpm: (2000 + 500 * sin(angle)).round(),
            engineFuelRate: fuel,
          ),
          timestamp: timestamp,
        );
      }

      final active = tripProvider.activeTrip;

      assertRelativeTolerance(
        actual: active.distanceKm,
        expected: exactDistanceKm,
        metric: 'Harmonic Distance',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.fuelConsumedLiters,
        expected: exactFuelLiters,
        metric: 'Harmonic Fuel',
        tolerancePercent: 1.0,
      );

      tripProvider.dispose();
    });
  });

  group('M2 Challenge Area 2: Non-uniform Time Deltas, Sub-second Jitter & Boundary Slices', () {
    test('2.1: High frequency (20 Hz / 50ms) sub-second telemetry sampling with rapid jitter', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 12, 0, 0);
      DateTime currentTime = startTime;

      // 400 steps of varying sub-second deltas: 50ms to 250ms
      final stepDeltasMs = [50, 75, 100, 50, 150, 200, 50, 80, 120, 250];
      int totalMs = 0;
      double theoreticalDistanceKm = 0.0;
      double theoreticalFuelLiters = 0.0;

      double lastSpeed = 50.0;
      double lastFuel = 4.0;

      tripProvider.processDataPoint(
        const ObdData(speed: 50, rpm: 2000, engineFuelRate: 4.0),
        timestamp: currentTime,
      );

      for (int i = 0; i < 200; i++) {
        final dtMs = stepDeltasMs[i % stepDeltasMs.length];
        totalMs += dtMs;
        currentTime = startTime.add(Duration(milliseconds: totalMs));

        final speed = 50.0 + 15.0 * sin(i * 0.1);
        final fuel = 4.0 + 1.2 * sin(i * 0.1);
        final dtSec = dtMs / 1000.0;

        theoreticalDistanceKm += ((lastSpeed + speed.roundToDouble()) / 2.0) * (dtSec / 3600.0);
        theoreticalFuelLiters += ((lastFuel + fuel) / 2.0) * (dtSec / 3600.0);
        lastSpeed = speed.roundToDouble();
        lastFuel = fuel;

        tripProvider.processDataPoint(
          ObdData(speed: speed.round(), rpm: 2200, engineFuelRate: fuel),
          timestamp: currentTime,
        );
      }

      final active = tripProvider.activeTrip;
      final expectedDurationSec = totalMs / 1000.0;
      final theoreticalAvgSpeed = theoreticalDistanceKm / (expectedDurationSec / 3600.0);

      assertRelativeTolerance(
        actual: active.distanceKm,
        expected: theoreticalDistanceKm,
        metric: 'Sub-second Jitter Distance',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.fuelConsumedLiters,
        expected: theoreticalFuelLiters,
        metric: 'Sub-second Jitter Fuel',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.duration.inMilliseconds / 1000.0,
        expected: expectedDurationSec,
        metric: 'Sub-second Duration',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.avgSpeed,
        expected: theoreticalAvgSpeed,
        metric: 'Sub-second Average Speed',
        tolerancePercent: 1.0,
      );

      tripProvider.dispose();
    });

    test('2.2: Boundary clamp test: telemetry gap > 15s is safely clamped to 15s', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      tripProvider.processDataPoint(
        const ObdData(speed: 60, rpm: 2000, engineFuelRate: 6.0),
        timestamp: t0,
      );

      // Telemetry blackout for 40 seconds (gap > 15s clamp threshold)
      final t1 = t0.add(const Duration(seconds: 40));
      tripProvider.processDataPoint(
        const ObdData(speed: 60, rpm: 2000, engineFuelRate: 6.0),
        timestamp: t1,
      );

      final active = tripProvider.activeTrip;

      // dt must be clamped to 15.0s, so distance should be:
      // (60 km/h * 15s) / 3600 = 0.25 km (not 40s = 0.666 km)
      const expectedClampedDist = (60.0 * 15.0) / 3600.0;
      const expectedClampedFuel = (6.0 * 15.0) / 3600.0;

      expect(active.distanceKm, closeTo(expectedClampedDist, 0.0001));
      expect(active.fuelConsumedLiters, closeTo(expectedClampedFuel, 0.00001));

      tripProvider.dispose();
    });

    test('2.3: Zero time delta boundary: identical back-to-back timestamps accumulate zero metrics', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      tripProvider.processDataPoint(
        const ObdData(speed: 80, rpm: 2500, engineFuelRate: 8.0),
        timestamp: t0,
      );

      // Feed multiple points with EXACT same timestamp t0
      for (int i = 0; i < 5; i++) {
        tripProvider.processDataPoint(
          const ObdData(speed: 80, rpm: 2500, engineFuelRate: 8.0),
          timestamp: t0,
        );
      }

      final active = tripProvider.activeTrip;
      expect(active.distanceKm, 0.0);
      expect(active.fuelConsumedLiters, 0.0);
      expect(active.avgSpeed.isNaN, isFalse);

      tripProvider.dispose();
    });
  });

  group('M2 Challenge Area 3: Pure DFCO Phases & Transition Boundaries', () {
    test('3.1: Sustained pure DFCO phase accumulates strictly 0.0 fuel over 120 seconds', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      const dfcoDuration = 120;
      const speedKmH = 85;

      // Feed initial sample in DFCO: speed > 20, rpm > 1300, throttle = 0, load < 18, maf = 0
      tripProvider.processDataPoint(
        const ObdData(
          speed: speedKmH,
          rpm: 2600,
          throttlePosition: 0.0,
          engineLoad: 12.0,
          maf: 0.0,
          engineFuelRate: 0.0,
        ),
        timestamp: t0,
      );

      for (int s = 1; s <= dfcoDuration; s++) {
        tripProvider.processDataPoint(
          const ObdData(
            speed: speedKmH,
            rpm: 2600,
            throttlePosition: 0.0,
            engineLoad: 12.0,
            maf: 0.0,
            engineFuelRate: 0.0,
          ),
          timestamp: t0.add(Duration(seconds: s)),
        );
      }

      final active = tripProvider.activeTrip;
      const expectedDistKm = (speedKmH * dfcoDuration) / 3600.0;

      assertRelativeTolerance(
        actual: active.distanceKm,
        expected: expectedDistKm,
        metric: 'DFCO Distance',
        tolerancePercent: 1.0,
      );

      // MUST be exactly 0.0 fuel
      expect(active.fuelConsumedLiters, 0.0,
          reason: 'Pure DFCO must accumulate strictly 0.0 liters of fuel');
      expect(active.instantFuelLPerHour, 0.0);
      expect(active.instantFuelL100km, 0.0);
      expect(active.avgFuelConsumption, 0.0);

      tripProvider.dispose();
    });

    test('3.2: Cruise -> DFCO -> Re-acceleration transitions integrate cleanly without negative fuel', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime t = t0;

      // Phase 1: 10s cruise at 70 km/h, 5.0 L/h
      tripProvider.processDataPoint(
        const ObdData(speed: 70, rpm: 2200, engineFuelRate: 5.0),
        timestamp: t,
      );
      for (int i = 1; i <= 10; i++) {
        t = t0.add(Duration(seconds: i));
        tripProvider.processDataPoint(
          const ObdData(speed: 70, rpm: 2200, engineFuelRate: 5.0),
          timestamp: t,
        );
      }

      final fuelAfterCruise = tripProvider.activeTrip.fuelConsumedLiters;
      expect(fuelAfterCruise, closeTo((5.0 * 10) / 3600.0, 0.0001));

      // Phase 2: 30s DFCO at 0.0 L/h (70 -> 40 km/h)
      for (int i = 1; i <= 30; i++) {
        t = t.add(const Duration(seconds: 1));
        final spd = 70.0 - (30.0 / 30.0) * i;
        tripProvider.processDataPoint(
          ObdData(
            speed: spd.round(),
            rpm: 2000,
            throttlePosition: 0.0,
            engineLoad: 12.0,
            engineFuelRate: 0.0,
          ),
          timestamp: t,
        );
      }

      final fuelAfterDfco = tripProvider.activeTrip.fuelConsumedLiters;
      // Transition slice is (5.0 + 0.0)/2 * 1s / 3600 = 2.5 / 3600 = 0.000694 L
      // Then next 29s is strictly 0.0
      final expectedDfcoFuel = fuelAfterCruise + (2.5 / 3600.0);
      expect(fuelAfterDfco, closeTo(expectedDfcoFuel, 0.0001));

      // Phase 3: Tip-in throttle back to 6.0 L/h
      for (int i = 1; i <= 10; i++) {
        t = t.add(const Duration(seconds: 1));
        tripProvider.processDataPoint(
          const ObdData(speed: 60, rpm: 2100, engineFuelRate: 6.0),
          timestamp: t,
        );
      }

      final fuelAfterTipIn = tripProvider.activeTrip.fuelConsumedLiters;
      expect(fuelAfterTipIn, greaterThan(fuelAfterDfco));

      tripProvider.dispose();
    });
  });

  group('M2 Challenge Area 4: Extreme Rapid Acceleration Spikes & Fuzzing', () {
    test('4.1: Drag launch (0->100 km/h in 3s) and emergency stop (100->0 km/h in 2s)', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime t = t0;

      double theoreticalDistKm = 0.0;
      double theoreticalFuelL = 0.0;
      double lastSpeed = 0.0;
      double lastFuel = 0.8;

      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 750, engineFuelRate: 0.8),
        timestamp: t,
      );

      // Launch: 0 -> 100 km/h in 3s, fuel 0.8 -> 35.0 L/h
      for (int i = 1; i <= 3; i++) {
        t = t.add(const Duration(seconds: 1));
        final speed = (100.0 / 3.0) * i;
        final fuel = 0.8 + ((35.0 - 0.8) / 3.0) * i;

        theoreticalDistKm += ((lastSpeed + speed) / 2.0) * (1.0 / 3600.0);
        theoreticalFuelL += ((lastFuel + fuel) / 2.0) * (1.0 / 3600.0);
        lastSpeed = speed;
        lastFuel = fuel;

        tripProvider.processDataPoint(
          ObdData(speed: speed.round(), rpm: (1000 + i * 1600), engineFuelRate: fuel),
          timestamp: t,
        );
      }

      // Emergency stop: 100 -> 0 km/h in 2s, fuel 35.0 -> 0.8 L/h
      for (int i = 1; i <= 2; i++) {
        t = t.add(const Duration(seconds: 1));
        final speed = 100.0 - (100.0 / 2.0) * i;
        final fuel = 35.0 - ((35.0 - 0.8) / 2.0) * i;

        theoreticalDistKm += ((lastSpeed + speed) / 2.0) * (1.0 / 3600.0);
        theoreticalFuelL += ((lastFuel + fuel) / 2.0) * (1.0 / 3600.0);
        lastSpeed = speed;
        lastFuel = fuel;

        tripProvider.processDataPoint(
          ObdData(speed: speed.round(), rpm: (5800 - i * 2500), engineFuelRate: fuel),
          timestamp: t,
        );
      }

      final active = tripProvider.activeTrip;

      assertRelativeTolerance(
        actual: active.distanceKm,
        expected: theoreticalDistKm,
        metric: 'Violent Spike Distance',
        tolerancePercent: 1.0,
      );

      assertRelativeTolerance(
        actual: active.fuelConsumedLiters,
        expected: theoreticalFuelL,
        metric: 'Violent Spike Fuel',
        tolerancePercent: 1.0,
      );

      expect(active.maxSpeed, 100.0);
      expect(active.maxRpm, 5800);

      tripProvider.dispose();
    });

    test('4.2: 1,000 randomized telemetry iterations: zero NaN, zero Infinities, non-negative bounds', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final rng = Random(42);
      var currentT = DateTime(2026, 1, 1, 10, 0, 0);

      for (int step = 0; step < 1000; step++) {
        final dtMs = rng.nextInt(3000) + 10; // 10ms to 3010ms
        currentT = currentT.add(Duration(milliseconds: dtMs));

        final speed = rng.nextInt(180); // 0 to 180 km/h
        final rpm = rng.nextInt(6500);  // 0 to 6500 RPM
        final fuel = rng.nextDouble() * 45.0; // 0 to 45 L/h

        tripProvider.processDataPoint(
          ObdData(
            speed: speed,
            rpm: rpm,
            engineFuelRate: fuel,
            throttlePosition: rng.nextDouble() * 100.0,
            engineLoad: rng.nextDouble() * 100.0,
          ),
          timestamp: currentT,
        );

        final active = tripProvider.activeTrip;
        expect(active.distanceKm.isNaN, isFalse);
        expect(active.distanceKm.isInfinite, isFalse);
        expect(active.distanceKm, greaterThanOrEqualTo(0.0));

        expect(active.fuelConsumedLiters.isNaN, isFalse);
        expect(active.fuelConsumedLiters.isInfinite, isFalse);
        expect(active.fuelConsumedLiters, greaterThanOrEqualTo(0.0));

        expect(active.avgSpeed.isNaN, isFalse);
        expect(active.avgSpeed.isInfinite, isFalse);
        expect(active.avgSpeed, greaterThanOrEqualTo(0.0));

        expect(active.avgFuelConsumption.isNaN, isFalse);
        expect(active.avgFuelConsumption.isInfinite, isFalse);
        expect(active.avgFuelConsumption, greaterThanOrEqualTo(0.0));
      }

      tripProvider.dispose();
    });
  });

  group('M2 Challenge Area 5: Edge Conditions (Stationary Idle, Disconnect & Engine-Off)', () {
    test('5.1: 600s stationary idling engine accumulates zero distance and non-zero fuel without NaN', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      const idleDuration = 600; // 10 minutes
      const idleFuelRate = 0.819; // L/h

      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 750, engineFuelRate: idleFuelRate),
        timestamp: t0,
      );

      for (int s = 1; s <= idleDuration; s++) {
        tripProvider.processDataPoint(
          const ObdData(speed: 0, rpm: 750, engineFuelRate: idleFuelRate),
          timestamp: t0.add(Duration(seconds: s)),
        );
      }

      final active = tripProvider.activeTrip;
      const expectedFuel = (idleFuelRate * idleDuration) / 3600.0;

      expect(active.distanceKm, 0.0);
      expect(active.avgSpeed, 0.0);
      expect(active.avgFuelConsumption, 0.0); // Must be 0.0, NOT division by zero NaN!
      expect(active.fuelConsumedLiters, closeTo(expectedFuel, 0.0001));

      tripProvider.dispose();
    });

    test('5.2: Discard threshold filters accidental key-on events (< 5s and < 0.01 km)', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final tripProvider = TripProvider(historyService: historyService);
      await tripProvider.setMinTripDistanceKm(0.1);
      tripProvider.manualStartTrip();

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      // Key on for 2 seconds without moving
      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 750, engineFuelRate: 0.8),
        timestamp: t0,
      );
      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 750, engineFuelRate: 0.8),
        timestamp: t0.add(const Duration(seconds: 2)),
      );

      await tripProvider.manualEndTrip(t0.add(const Duration(seconds: 2)));

      final trips = await historyService.loadTrips();
      expect(trips, isEmpty, reason: 'Accidental key-on without movement must be discarded');

      tripProvider.dispose();
    });
  });
}
