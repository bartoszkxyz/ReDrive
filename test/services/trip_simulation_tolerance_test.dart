import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/trip_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// Mathematical helper asserting relative error < 1.0%
  void assertWithinTolerance({
    required double actual,
    required double expected,
    required String metric,
    double tolerancePercent = 1.0,
  }) {
    if (expected.abs() < 1e-6) {
      expect(
        actual.abs(),
        lessThan(1e-4),
        reason: '$metric: Expected ~0, but got $actual',
      );
      return;
    }
    final relativeErrorPercent = ((actual - expected).abs() / expected) * 100.0;
    expect(
      relativeErrorPercent,
      lessThan(tolerancePercent),
      reason: '$metric failed tolerance test: actual=$actual, expected=$expected, '
          'relativeError=${relativeErrorPercent.toStringAsFixed(4)}% (limit: $tolerancePercent%)',
    );
  }

  group('Requirement R2 - Driving Sequence Simulation Tolerance (< 1.0%)', () {
    test('Sequence 1: Steady Cruise Sequence (Constant 60 km/h, 4.2 L/h over 600s)', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime currentTime = startTime;

      const durationSeconds = 600;
      const speedKmH = 60;
      const fuelFlowLPerHour = 4.2; // L/h

      // Ground truth calculations
      const theoreticalDurationSec = durationSeconds;
      const theoreticalDistanceKm = (speedKmH * durationSeconds) / 3600.0; // 10.0 km
      const theoreticalAvgSpeedKmH = 60.0;
      const theoreticalFuelConsumedLiters = (fuelFlowLPerHour * durationSeconds) / 3600.0; // 0.700 L

      for (int i = 0; i <= durationSeconds; i++) {
        currentTime = startTime.add(Duration(seconds: i));
        final data = ObdData(
          speed: speedKmH,
          rpm: 2000,
          engineFuelRate: fuelFlowLPerHour,
          throttlePosition: 20.0,
          engineLoad: 30.0,
        );
        tripProvider.processDataPoint(data, timestamp: currentTime);
      }

      final active = tripProvider.activeTrip;

      assertWithinTolerance(
        actual: active.distanceKm,
        expected: theoreticalDistanceKm,
        metric: 'distanceKm',
      );
      assertWithinTolerance(
        actual: active.duration.inSeconds.toDouble(),
        expected: theoreticalDurationSec.toDouble(),
        metric: 'duration',
      );
      assertWithinTolerance(
        actual: active.avgSpeed,
        expected: theoreticalAvgSpeedKmH,
        metric: 'averageSpeedKmH',
      );
      assertWithinTolerance(
        actual: active.fuelConsumedLiters,
        expected: theoreticalFuelConsumedLiters,
        metric: 'fuelConsumedLiters',
      );

      tripProvider.dispose();
    });

    test('Sequence 2: Linear Acceleration, Cruise, and Deceleration Profile', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime currentTime = startTime;

      // Profile phases:
      // 1. Accel: 0 to 90 km/h over 30s, fuel: 1.5 to 9.0 L/h
      // 2. Cruise: 90 km/h for 120s, fuel: 6.0 L/h
      // 3. Decel: 90 to 0 km/h over 30s, fuel: 6.0 to 1.5 L/h
      double theoreticalDistanceKm = 0.0;
      double theoreticalFuelLiters = 0.0;
      int elapsedSeconds = 0;

      double lastSpeed = 0.0;
      double lastFuel = 1.5;

      // 0s initial point
      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 750, engineFuelRate: 1.5),
        timestamp: currentTime,
      );

      // Phase 1: Accel (30s)
      for (int t = 1; t <= 30; t++) {
        elapsedSeconds++;
        currentTime = startTime.add(Duration(seconds: elapsedSeconds));
        final speed = (90.0 / 30.0) * t;
        final fuel = 1.5 + ((9.0 - 1.5) / 30.0) * t;

        theoreticalDistanceKm += ((lastSpeed + speed) / 2.0) * (1.0 / 3600.0);
        theoreticalFuelLiters += ((lastFuel + fuel) / 2.0) * (1.0 / 3600.0);
        lastSpeed = speed;
        lastFuel = fuel;

        tripProvider.processDataPoint(
          ObdData(speed: speed.round(), rpm: 1000 + (t * 60), engineFuelRate: fuel),
          timestamp: currentTime,
        );
      }

      // Phase 2: Cruise (120s at 90 km/h, 6.0 L/h)
      for (int t = 1; t <= 120; t++) {
        elapsedSeconds++;
        currentTime = startTime.add(Duration(seconds: elapsedSeconds));
        const speed = 90.0;
        const fuel = 6.0;

        theoreticalDistanceKm += ((lastSpeed + speed) / 2.0) * (1.0 / 3600.0);
        theoreticalFuelLiters += ((lastFuel + fuel) / 2.0) * (1.0 / 3600.0);
        lastSpeed = speed;
        lastFuel = fuel;

        tripProvider.processDataPoint(
          const ObdData(speed: 90, rpm: 2800, engineFuelRate: 6.0),
          timestamp: currentTime,
        );
      }

      // Phase 3: Decel (30s)
      for (int t = 1; t <= 30; t++) {
        elapsedSeconds++;
        currentTime = startTime.add(Duration(seconds: elapsedSeconds));
        final speed = 90.0 - (90.0 / 30.0) * t;
        final fuel = 6.0 - ((6.0 - 1.5) / 30.0) * t;

        theoreticalDistanceKm += ((lastSpeed + speed) / 2.0) * (1.0 / 3600.0);
        theoreticalFuelLiters += ((lastFuel + fuel) / 2.0) * (1.0 / 3600.0);
        lastSpeed = speed;
        lastFuel = fuel;

        tripProvider.processDataPoint(
          ObdData(speed: speed.round(), rpm: 2800 - (t * 60), engineFuelRate: fuel),
          timestamp: currentTime,
        );
      }

      final theoreticalAvgSpeed = theoreticalDistanceKm / (elapsedSeconds / 3600.0);
      final active = tripProvider.activeTrip;

      assertWithinTolerance(
        actual: active.distanceKm,
        expected: theoreticalDistanceKm,
        metric: 'distanceKm',
      );
      assertWithinTolerance(
        actual: active.duration.inSeconds.toDouble(),
        expected: elapsedSeconds.toDouble(),
        metric: 'duration',
      );
      assertWithinTolerance(
        actual: active.avgSpeed,
        expected: theoreticalAvgSpeed,
        metric: 'averageSpeedKmH',
      );
      assertWithinTolerance(
        actual: active.fuelConsumedLiters,
        expected: theoreticalFuelLiters,
        metric: 'fuelConsumedLiters',
      );

      tripProvider.dispose();
    });

    test('Sequence 3: Multi-Phase Drive Cycle including DFCO Coasting', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime currentTime = startTime;

      double theoreticalDistanceKm = 0.0;
      double theoreticalFuelLiters = 0.0;
      int totalSeconds = 0;

      void feedSlice({
        required int durationSec,
        required double startSpeed,
        required double endSpeed,
        required double startFuel,
        required double endFuel,
        required int rpm,
        required double throttle,
      }) {
        for (int i = 1; i <= durationSec; i++) {
          totalSeconds++;
          currentTime = startTime.add(Duration(seconds: totalSeconds));
          final frac = i / durationSec;
          final prevFrac = (i - 1) / durationSec;
          final s1 = startSpeed + (endSpeed - startSpeed) * prevFrac;
          final s2 = startSpeed + (endSpeed - startSpeed) * frac;
          final f1 = startFuel + (endFuel - startFuel) * prevFrac;
          final f2 = startFuel + (endFuel - startFuel) * frac;

          theoreticalDistanceKm += ((s1 + s2) / 2.0) * (1.0 / 3600.0);
          theoreticalFuelLiters += ((f1 + f2) / 2.0) * (1.0 / 3600.0);

          tripProvider.processDataPoint(
            ObdData(
              speed: s2.round(),
              rpm: rpm,
              engineFuelRate: f2,
              throttlePosition: throttle,
              engineLoad: throttle > 0 ? 30.0 : 10.0,
            ),
            timestamp: currentTime,
          );
        }
      }

      // Initial point
      tripProvider.processDataPoint(
        const ObdData(speed: 0, rpm: 750, engineFuelRate: 0.819),
        timestamp: currentTime,
      );

      // Phase 1: 30s Idle (0 km/h, 0.819 L/h)
      feedSlice(
        durationSec: 30,
        startSpeed: 0,
        endSpeed: 0,
        startFuel: 0.819,
        endFuel: 0.819,
        rpm: 750,
        throttle: 0,
      );

      // Phase 2: 20s City ramp (0 -> 50 km/h, 1.5 -> 7.5 L/h)
      feedSlice(
        durationSec: 20,
        startSpeed: 0,
        endSpeed: 50,
        startFuel: 1.5,
        endFuel: 7.5,
        rpm: 2200,
        throttle: 35,
      );

      // Phase 3: 60s City cruise (50 km/h, 3.5 L/h)
      feedSlice(
        durationSec: 60,
        startSpeed: 50,
        endSpeed: 50,
        startFuel: 3.5,
        endFuel: 3.5,
        rpm: 1800,
        throttle: 20,
      );

      // Phase 4: 15s Highway ramp (50 -> 100 km/h, 4.0 -> 12.0 L/h)
      feedSlice(
        durationSec: 15,
        startSpeed: 50,
        endSpeed: 100,
        startFuel: 4.0,
        endFuel: 12.0,
        rpm: 3200,
        throttle: 60,
      );

      // Phase 5: 300s Highway cruise (100 km/h, 6.5 L/h)
      feedSlice(
        durationSec: 300,
        startSpeed: 100,
        endSpeed: 100,
        startFuel: 6.5,
        endFuel: 6.5,
        rpm: 2900,
        throttle: 28,
      );

      // Phase 6: 20s DFCO Coasting in gear (100 -> 35 km/h, 0.0 L/h, closed throttle, RPM > 1300)
      feedSlice(
        durationSec: 20,
        startSpeed: 100,
        endSpeed: 35,
        startFuel: 0.0,
        endFuel: 0.0,
        rpm: 2100,
        throttle: 0.0,
      );

      // Phase 7: 10s Final Braking (35 -> 0 km/h, 0.819 L/h)
      feedSlice(
        durationSec: 10,
        startSpeed: 35,
        endSpeed: 0,
        startFuel: 0.819,
        endFuel: 0.819,
        rpm: 750,
        throttle: 0.0,
      );

      final theoreticalAvgSpeed = theoreticalDistanceKm / (totalSeconds / 3600.0);
      final active = tripProvider.activeTrip;

      assertWithinTolerance(
        actual: active.distanceKm,
        expected: theoreticalDistanceKm,
        metric: 'distanceKm',
      );
      assertWithinTolerance(
        actual: active.duration.inSeconds.toDouble(),
        expected: totalSeconds.toDouble(),
        metric: 'duration',
      );
      assertWithinTolerance(
        actual: active.avgSpeed,
        expected: theoreticalAvgSpeed,
        metric: 'averageSpeedKmH',
      );
      assertWithinTolerance(
        actual: active.fuelConsumedLiters,
        expected: theoreticalFuelLiters,
        metric: 'fuelConsumedLiters',
      );

      tripProvider.dispose();
    });

    test('Sequence 4: Non-uniform Time Steps (Telemetry Jitter Resilience)', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime currentTime = startTime;

      // Time steps varying from 0.2s to 2.5s
      final deltaSteps = [0.2, 0.5, 1.0, 1.8, 2.5, 0.8, 1.2, 0.4, 1.6];
      double totalTimeSec = 0.0;
      double theoreticalDistanceKm = 0.0;
      double theoreticalFuelLiters = 0.0;

      double lastSpeed = 40.0;
      double lastFuel = 3.0;

      tripProvider.processDataPoint(
        const ObdData(speed: 40, rpm: 1500, engineFuelRate: 3.0),
        timestamp: currentTime,
      );

      for (int step = 0; step < 50; step++) {
        final dt = deltaSteps[step % deltaSteps.length];
        totalTimeSec += dt;
        currentTime = startTime.add(Duration(milliseconds: (totalTimeSec * 1000).round()));

        final currentSpeed = 40.0 + 20.0 * sin(step * 0.2);
        final currentFuel = 3.0 + 1.5 * sin(step * 0.2);

        theoreticalDistanceKm += ((lastSpeed + currentSpeed) / 2.0) * (dt / 3600.0);
        theoreticalFuelLiters += ((lastFuel + currentFuel) / 2.0) * (dt / 3600.0);
        lastSpeed = currentSpeed;
        lastFuel = currentFuel;

        tripProvider.processDataPoint(
          ObdData(
            speed: currentSpeed.round(),
            rpm: 1800,
            engineFuelRate: currentFuel,
            throttlePosition: 20.0,
          ),
          timestamp: currentTime,
        );
      }

      final theoreticalAvgSpeed = theoreticalDistanceKm / (totalTimeSec / 3600.0);
      final active = tripProvider.activeTrip;

      assertWithinTolerance(
        actual: active.distanceKm,
        expected: theoreticalDistanceKm,
        metric: 'distanceKm',
      );
      assertWithinTolerance(
        actual: active.duration.inMilliseconds / 1000.0,
        expected: totalTimeSec,
        metric: 'duration',
      );
      assertWithinTolerance(
        actual: active.avgSpeed,
        expected: theoreticalAvgSpeed,
        metric: 'averageSpeedKmH',
      );
      assertWithinTolerance(
        actual: active.fuelConsumedLiters,
        expected: theoreticalFuelLiters,
        metric: 'fuelConsumedLiters',
      );

      tripProvider.dispose();
    });

    test('Sequence 5: Pure Deceleration Fuel Cut-Off (DFCO) Zero Fuel Consumption', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      tripProvider.manualStartTrip();

      final startTime = DateTime(2026, 1, 1, 10, 0, 0);
      DateTime currentTime = startTime;

      const durationSec = 60;
      const speedKmH = 70;
      // In DFCO, throttle is 0, RPM > 1300, speed > 20, load < 18
      for (int i = 0; i <= durationSec; i++) {
        currentTime = startTime.add(Duration(seconds: i));
        tripProvider.processDataPoint(
          const ObdData(
            speed: speedKmH,
            rpm: 2200,
            throttlePosition: 0.0,
            engineLoad: 12.0,
            maf: 0.0, // Triggers DFCO in FuelCalculator
          ),
          timestamp: currentTime,
        );
      }

      final active = tripProvider.activeTrip;
      const expectedDistKm = (speedKmH * durationSec) / 3600.0;

      assertWithinTolerance(
        actual: active.distanceKm,
        expected: expectedDistKm,
        metric: 'distanceKm',
      );
      expect(active.fuelConsumedLiters, 0.0, reason: 'DFCO coasting must accumulate exactly 0.0 fuel');

      tripProvider.dispose();
    });
  });
}
