import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/services/dtc/dtc_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_history_service.dart';

import 'e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {});

  group('Tier 4: Real-World Driving Cycles & Scenarios', () {
    const calculator = FuelCalculator(
      displacementLiters: 1.5,
      airFuelRatio: 14.7,
      fuelDensityGramsPerLiter: 820.0,
    );

    test('Scenario 1: Cold Start Idle & Warm-Up Driving Cycle', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);

      // 1. Key-on engine off: 0 RPM, 0 km/h, 20°C coolant
      final fuelOff = calculator.calculateFuelFlowLitersPerHour(
        rpm: 0,
        speedKmH: 0,
        engineLoadPercent: 0.0,
      );
      expect(fuelOff, 0.0);
      expect(tripProvider.activeTrip.isActive, isFalse);

      // 2. Engine start: fast cold idle at 1250 RPM, load 35%, MAF 4.2 g/s
      tripProvider.manualStartTrip();
      expect(tripProvider.activeTrip.isActive, isTrue);

      final coldFuelRate = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1250,
        speedKmH: 0,
        mafGramsPerSecond: 4.2,
        engineLoadPercent: 35.0,
      );
      final theoreticalCold = AnalyticalOracles.theoreticalFuelFlow(mafGramsPerSecond: 4.2);
      expect(coldFuelRate, closeTo(theoreticalCold, 0.05));
      expect(coldFuelRate, inInclusiveRange(1.1, 1.4));

      // 3. Warm-up sequence: coolant climbs from 20°C to 88°C, idle settles to 750 RPM, MAF 2.4 g/s
      final warmFuelRate = calculator.calculateFuelFlowLitersPerHour(
        rpm: 750,
        speedKmH: 0,
        mafGramsPerSecond: 2.4,
        engineLoadPercent: 20.0,
      );
      final theoreticalWarm = AnalyticalOracles.theoreticalFuelFlow(mafGramsPerSecond: 2.4);
      expect(warmFuelRate, closeTo(theoreticalWarm, 0.05));
      expect(warmFuelRate, lessThan(coldFuelRate));
      expect(warmFuelRate, inInclusiveRange(0.65, 0.85));

      // Stationary fuel economy is strictly 0.0 L/100km
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: warmFuelRate,
        speedKmH: 0,
      );
      expect(economy, 0.0);

      tripProvider.dispose();
    });

    test('Scenario 2: Urban Stop-and-Go Driving Cycle', () async {
      // Slices:
      // - Launch: 0 -> 25 km/h (2s)
      // - Accelerate: 25 -> 45 km/h (3s)
      // - Cruise: 45 km/h (10s)
      // - Brake to stop: 45 -> 0 km/h (4s)
      // - Idle at red light: 0 km/h (15s)
      // - Re-accelerate: 0 -> 50 km/h (4s)
      final speedSlices = [
        (speedKmH: 25.0, dtSeconds: 2.0),
        (speedKmH: 45.0, dtSeconds: 3.0),
        (speedKmH: 45.0, dtSeconds: 10.0),
        (speedKmH: 0.0, dtSeconds: 4.0),
        (speedKmH: 0.0, dtSeconds: 15.0),
        (speedKmH: 50.0, dtSeconds: 4.0),
      ];

      final analyticalDistance = AnalyticalOracles.theoreticalTrapezoidalDistance(
        speedSlices,
        initialSpeed: 0.0,
      );

      // Verify analytical distance computation
      expect(analyticalDistance, greaterThan(0.2));
      expect(analyticalDistance, lessThan(0.4));

      // Fuel flows corresponding to each phase
      final fuelSlices = [
        (fuelFlowLPerHour: 8.5, dtSeconds: 2.0),  // Launch
        (fuelFlowLPerHour: 12.0, dtSeconds: 3.0), // Hard acceleration
        (fuelFlowLPerHour: 3.8, dtSeconds: 10.0), // Urban cruise at 45 km/h
        (fuelFlowLPerHour: 0.0, dtSeconds: 4.0),  // Coasting/braking with DFCO
        (fuelFlowLPerHour: 0.75, dtSeconds: 15.0),// Idle at traffic light
        (fuelFlowLPerHour: 14.0, dtSeconds: 4.0), // Re-acceleration
      ];

      final analyticalFuel = AnalyticalOracles.theoreticalCumulativeFuel(fuelSlices);
      expect(analyticalFuel, greaterThan(0.02));
      expect(analyticalFuel, lessThan(0.06));

      // Overall average fuel consumption (L/100km)
      final avgL100km = (analyticalFuel / analyticalDistance) * 100.0;
      expect(avgL100km, inInclusiveRange(7.0, 25.0));
    });

    test('Scenario 3: Highway Cruise Driving Cycle', () async {
      // 90 km/h steady cruise at 2500 RPM, MAF ~15.5 g/s
      final cruiseFlow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        speedKmH: 90,
        mafGramsPerSecond: 15.5,
        engineLoadPercent: 38.0,
        throttlePositionPercent: 20.0,
      );
      final theoreticalCruiseFlow = AnalyticalOracles.theoreticalFuelFlow(mafGramsPerSecond: 15.5);
      expect(cruiseFlow, closeTo(theoreticalCruiseFlow, 0.05));
      expect(cruiseFlow, inInclusiveRange(4.2, 5.0));

      final cruiseEconomy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: cruiseFlow,
        speedKmH: 90,
      );
      final theoreticalEconomy = AnalyticalOracles.theoreticalLitersPer100Km(
        fuelFlowLPerHour: theoreticalCruiseFlow,
        speedKmH: 90,
      );
      expect(cruiseEconomy, closeTo(theoreticalEconomy, 0.05));
      expect(cruiseEconomy, inInclusiveRange(5.0, 6.0));

      // Over 1 hour of highway cruise: 90 km traveled, ~4.63 L consumed
      final hourSlices = [(speedKmH: 90.0, dtSeconds: 3600.0)];
      final dist = AnalyticalOracles.theoreticalTrapezoidalDistance(hourSlices, initialSpeed: 90.0);
      expect(dist, 90.0);

      final fuel = AnalyticalOracles.theoreticalCumulativeFuel([
        (fuelFlowLPerHour: cruiseFlow, dtSeconds: 3600.0),
      ]);
      expect(fuel, closeTo(4.63, 0.2));
    });

    test('Scenario 4: Mountain Descent with Deceleration Fuel Cut-Off (DFCO)', () async {
      // Vehicle descending mountain pass:
      // Initial state: 80 km/h, 2400 RPM
      // Coasting with throttle completely closed (0.0%), engine load 11%, speed 75 km/h, RPM 2200
      final dfcoRate = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 75,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 11.0,
        directFuelRateLPerHour: 3.5, // Even if ECU reports a nominal fuel rate, DFCO overrides to 0.0
      );
      expect(dfcoRate, 0.0);

      // Coasting down for 30 seconds at average 70 km/h:
      final descentDistance = AnalyticalOracles.theoreticalTrapezoidalDistance(
        [(speedKmH: 70.0, dtSeconds: 30.0)],
        initialSpeed: 70.0,
      );
      // 70 * 30 / 3600 = 0.5833 km
      expect(descentDistance, closeTo(0.583, 0.01));

      // Cumulative fuel consumed during DFCO is strictly 0.0
      final descentFuel = AnalyticalOracles.theoreticalCumulativeFuel([
        (fuelFlowLPerHour: dfcoRate, dtSeconds: 30.0),
      ]);
      expect(descentFuel, 0.0);

      // Driver taps accelerator at bottom of mountain: throttle 20%, RPM 2200
      final powerRestoredRate = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 70,
        throttlePositionPercent: 20.0,
        engineLoadPercent: 35.0,
        mafGramsPerSecond: 12.0,
      );
      expect(powerRestoredRate, greaterThan(3.0));
    });

    test('Scenario 5: Engine Shutdown, Trip Completion & Restart Persistence Cycle', () async {
      final historyService = TripHistoryService();
      final now = DateTime.now();

      // 1. Initial completed trip
      final completedTrip = Trip(
        id: 'cycle5_${now.millisecondsSinceEpoch}',
        startTime: now.subtract(const Duration(minutes: 35)),
        endTime: now,
        duration: const Duration(minutes: 35),
        distanceKm: 28.4,
        fuelConsumedLiters: 1.76,
        avgFuelConsumption: 6.2,
        avgSpeed: 48.7,
        maxSpeed: 82.0,
        maxRpm: 3100,
        avgRpm: 2050,
      );

      // Save trip to disk
      await historyService.saveTrip(completedTrip);

      // 2. Simulate application restart: load trips afresh
      final reloadedTrips = await historyService.loadTrips();
      expect(reloadedTrips, isNotEmpty);
      final found = reloadedTrips.firstWhere((t) => t.id == completedTrip.id);
      expect(found.distanceKm, 28.4);
      expect(found.fuelConsumedLiters, 1.76);
      expect(found.avgFuelConsumption, 6.2);
      expect(found.avgSpeed, 48.7);
      expect(found.maxSpeed, 82.0);
      expect(found.maxRpm, 3100);

      // 3. Next drive starts a fresh active trip
      final newTripProvider = TripProvider();
      await newTripProvider.setMinTripDistanceKm(0.0);
      newTripProvider.manualStartTrip();

      expect(newTripProvider.activeTrip.isActive, isTrue);
      expect(newTripProvider.activeTrip.distanceKm, 0.0);
      expect(newTripProvider.activeTrip.fuelConsumedLiters, 0.0);

      newTripProvider.dispose();
    });

    test('Scenario 6: In-Flight Fault Trigger & Diagnostic Resolution Cycle', () async {
      final dtcService = DtcService();
      final obdProvider = ObdProvider();
      await obdProvider.startDemoMode();
      await Future.delayed(const Duration(milliseconds: 300));

      // 1. Normal driving: ECU triggers trouble codes
      final detectedCodes = await dtcService.scanAllCodes(obdProvider);
      expect(detectedCodes, isNotEmpty);

      // 2. Verify codes have full descriptions and severities
      final misfireCode = detectedCodes.firstWhere((c) => c.code == 'P0300');
      expect(misfireCode.title, contains('Misfire'));
      expect(misfireCode.severity, 'Critical');
      expect(misfireCode.system, 'Powertrain');

      final leanCode = detectedCodes.firstWhere((c) => c.code == 'P0171');
      expect(leanCode.title, contains('Too Lean'));
      expect(leanCode.severity, 'Critical');

      // 3. Driver brings vehicle to safe stop and initiates Mode 04 clear
      final clearSuccess = await dtcService.clearAllCodes(obdProvider);
      expect(clearSuccess, isTrue);

      // 4. Verify diagnostic state is clean
      final postClear = await dtcService.scanAllCodes(obdProvider);
      expect(postClear, isEmpty);

      await obdProvider.stopDemoMode();
      obdProvider.dispose();
    });
  });
}
