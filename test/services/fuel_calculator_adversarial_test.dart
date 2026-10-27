import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';

void main() {
  const calculator = FuelCalculator(
    displacementLiters: 1.5,
    airFuelRatio: 14.7,
    fuelDensityGramsPerLiter: 820.0,
    calibrationFactor: 1.0,
  );

  group('Stoichiometric Physics Oracle Verification', () {
    test('verifies theoretical stoichiometric baseline constants (AFR = 14.7, rho = 820.0 g/L)', () {
      const expectedAirGramsPerLiter = 14.7 * 820.0; // 12054.0 g/L
      expect(calculator.airFuelRatio, 14.7);
      expect(calculator.fuelDensityGramsPerLiter, 820.0);
      expect(calculator.displacementLiters, 1.5);
      expect(calculator.calibrationFactor, 1.0);

      // Theoretical flow for 1 g/s MAF: 1 * 3600 / 12054 ≈ 0.298656 L/h
      final flow1g = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 1.0,
      );
      expect(flow1g, closeTo(3600.0 / expectedAirGramsPerLiter, 0.0001));
    });

    test('verifies MAF flow linearity against physics equations across spectrum', () {
      const mafTestPoints = [0.5, 1.0, 2.3, 5.0, 10.0, 20.0, 50.0, 100.0, 150.0];
      for (final maf in mafTestPoints) {
        final flow = calculator.calculateFuelFlowLitersPerHour(
          rpm: 2000,
          mafGramsPerSecond: maf,
        );
        final theoretical = min(60.0, (maf * 3600.0) / (14.7 * 820.0));
        expect(flow, closeTo(theoretical, 0.001),
            reason: 'Failed MAF physics linearity at MAF = $maf g/s');
      }
    });

    test('verifies exact mathematical trim proportionality (+10% and -10%)', () {
      final baseFlow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
      );

      final plus10Flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: 10.0,
      );
      expect(plus10Flow, closeTo(baseFlow * 1.10, 0.0001));

      final minus10Flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: -10.0,
      );
      expect(minus10Flow, closeTo(baseFlow * 0.90, 0.0001));

      // Combined STFT + LTFT (+7% + +3% = +10%)
      final combinedFlow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: 7.0,
        longTermFuelTrimPercent: 3.0,
      );
      expect(combinedFlow, closeTo(baseFlow * 1.10, 0.0001));
    });

    test('verifies speed-density fallback aligns with volumetric physics', () {
      // Theoretical air: (rpm * displacement * (load / 100)) / 125.0
      // Theoretical fuel: (air * 3600) / 12054
      const rpmPoints = [800, 1500, 2500, 4000, 6000];
      const loadPoints = [15.0, 25.0, 50.0, 80.0, 95.0];

      for (final rpm in rpmPoints) {
        for (final load in loadPoints) {
          final flow = calculator.calculateFuelFlowLitersPerHour(
            rpm: rpm,
            engineLoadPercent: load,
          );
          final theoreticalAir = (rpm * 1.5 * (load / 100.0)) / 125.0;
          final theoreticalFuel = min(60.0, (theoreticalAir * 3600.0) / (14.7 * 820.0));
          expect(flow, closeTo(theoreticalFuel, 0.001),
              reason: 'Failed volumetric physics at RPM=$rpm, Load=$load%');
        }
      }
    });

    test('verifies fuel economy theoretical calculation (L/100km = (L/h / km/h) * 100)', () {
      const speeds = [30, 50, 90, 120, 160];
      const flows = [1.5, 3.2, 5.4, 7.8, 12.0];

      for (final s in speeds) {
        for (final f in flows) {
          final economy = calculator.calculateLitersPer100Km(
            fuelFlowLitersPerHour: f,
            speedKmH: s,
          );
          final theoretical = min(99.9, (f / s) * 100.0);
          expect(economy, closeTo(theoretical, 0.0001),
              reason: 'Failed economy physics at Speed=$s km/h, Flow=$f L/h');
        }
      }
    });
  });

  group('DFCO Boundary Stress Testing', () {
    // Exact specified boundary thresholds:
    // Speed: > 20 km/h (discrete 20 vs 21 km/h)
    // RPM: > 1300 RPM (1299, 1300 vs 1301 RPM)
    // Throttle: <= 14.0% (14.0% vs 14.1%) and < 1.0% (0.9% vs 1.0%)
    // Load: < 18.0% (17.9% vs 18.0%)

    test('verifies active DFCO when all 4 conditions are strictly inside boundary', () {
      final active = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1301,
        speedKmH: 21,
        throttlePositionPercent: 14.0,
        engineLoadPercent: 17.9,
        directFuelRateLPerHour: 3.5,
        mafGramsPerSecond: 10.0,
      );
      expect(active, 0.0, reason: 'DFCO must activate when all 4 conditions are inside boundary');

      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: active,
        speedKmH: 21,
      );
      expect(economy, 0.0);
    });

    test('boundary edge: Speed = 20 km/h (DFCO inactive) vs 21 km/h (DFCO active)', () {
      // Speed <= 20 must NOT trigger DFCO
      final flowAt20 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 20,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt20, greaterThan(0.0), reason: 'Speed 20 km/h must not trigger DFCO (> 20 required)');

      // Speed 19 km/h must NOT trigger DFCO
      final flowAt19 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 19,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt19, greaterThan(0.0), reason: 'Speed 19 km/h must not trigger DFCO');

      // Speed 21 km/h MUST trigger DFCO
      final flowAt21 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 21,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt21, 0.0, reason: 'Speed 21 km/h must trigger DFCO');
    });

    test('boundary edge: RPM = 1299 & 1300 RPM (DFCO inactive) vs 1301 RPM (DFCO active)', () {
      // RPM 1299: Inactive
      final flowAt1299 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1299,
        speedKmH: 50,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt1299, greaterThan(0.0), reason: 'RPM 1299 must not trigger DFCO');

      // RPM 1300: Inactive (strict > 1300)
      final flowAt1300 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1300,
        speedKmH: 50,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt1300, greaterThan(0.0), reason: 'RPM 1300 must not trigger DFCO');

      // RPM 1301: Active
      final flowAt1301 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1301,
        speedKmH: 50,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt1301, 0.0, reason: 'RPM 1301 must trigger DFCO');
    });

    test('boundary edge: Throttle = 14.0% (DFCO active) vs 14.1% (DFCO inactive)', () {
      // Throttle 14.0%: Inside closed idle range [10.0, 14.0] -> Active
      final flowAt140 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 14.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt140, 0.0, reason: 'Throttle 14.0% must trigger DFCO');

      // Throttle 14.1%: Above closed idle range -> Inactive
      final flowAt141 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 14.1,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt141, greaterThan(0.0), reason: 'Throttle 14.1% must not trigger DFCO');

      // Relative throttle edges: 0.9% active vs 1.0% inactive
      final flowAt09 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 0.9,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt09, 0.0, reason: 'Throttle 0.9% must trigger DFCO (< 1.0%)');

      final flowAt10 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 1.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt10, greaterThan(0.0), reason: 'Throttle 1.0% must not trigger DFCO');

      // Middle gap: 9.9% inactive vs 10.0% active
      final flowAt99 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 9.9,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt99, greaterThan(0.0), reason: 'Throttle 9.9% must not trigger DFCO');

      final flowAt100 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 10.0,
        engineLoadPercent: 15.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt100, 0.0, reason: 'Throttle 10.0% must trigger DFCO');
    });

    test('boundary edge: Load = 17.9% (DFCO active) vs 18.0% (DFCO inactive)', () {
      // Load 17.9%: Below 18.0% threshold -> Active
      final flowAt179 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 17.9,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt179, 0.0, reason: 'Load 17.9% must trigger DFCO');

      // Load 18.0%: At threshold (< 18.0 required) -> Inactive
      final flowAt180 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 18.0,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt180, greaterThan(0.0), reason: 'Load 18.0% must not trigger DFCO');

      // Load 18.1%: Above threshold -> Inactive
      final flowAt181 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 18.1,
        mafGramsPerSecond: 5.0,
      );
      expect(flowAt181, greaterThan(0.0), reason: 'Load 18.1% must not trigger DFCO');
    });

    test('strict conjunctivity: single-variable perturbation breaks DFCO', () {
      // Nominal active state right at edge
      const edgeRpm = 1301;
      const edgeSpeed = 21;
      const edgeThrottle = 14.0;
      const edgeLoad = 17.9;

      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: edgeRpm,
          speedKmH: edgeSpeed,
          throttlePositionPercent: edgeThrottle,
          engineLoadPercent: edgeLoad,
        ),
        0.0,
      );

      // Perturb RPM below edge
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: 1300,
          speedKmH: edgeSpeed,
          throttlePositionPercent: edgeThrottle,
          engineLoadPercent: edgeLoad,
        ),
        greaterThan(0.0),
      );

      // Perturb Speed below edge
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: edgeRpm,
          speedKmH: 20,
          throttlePositionPercent: edgeThrottle,
          engineLoadPercent: edgeLoad,
        ),
        greaterThan(0.0),
      );

      // Perturb Throttle above edge
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: edgeRpm,
          speedKmH: edgeSpeed,
          throttlePositionPercent: 14.01,
          engineLoadPercent: edgeLoad,
        ),
        greaterThan(0.0),
      );

      // Perturb Load at edge
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: edgeRpm,
          speedKmH: edgeSpeed,
          throttlePositionPercent: edgeThrottle,
          engineLoadPercent: 18.0,
        ),
        greaterThan(0.0),
      );
    });
  });

  group('Fuzzing & Extremes - Defensive Invariants and Clamping', () {
    test('handles negative RPM by returning 0.0 L/h', () {
      for (final rpm in [-1, -10, -500, -10000]) {
        final flow = calculator.calculateFuelFlowLitersPerHour(
          rpm: rpm,
          engineLoadPercent: 50.0,
          mafGramsPerSecond: 10.0,
        );
        expect(flow, 0.0);
      }
    });

    test('handles stationary and negative speeds by returning 0.0 L/100km', () {
      for (final speed in [0, -1, -20, -100]) {
        final economy = calculator.calculateLitersPer100Km(
          fuelFlowLitersPerHour: 5.0,
          speedKmH: speed,
        );
        expect(economy, 0.0);
      }
    });

    test('handles zero and negative fuel flows by returning 0.0 L/100km', () {
      for (final flow in [0.0, -0.1, -5.0, -100.0]) {
        final economy = calculator.calculateLitersPer100Km(
          fuelFlowLitersPerHour: flow,
          speedKmH: 60,
        );
        expect(economy, 0.0);
      }
    });

    test('clamps fuel flow to [0.0, 60.0] under extreme sensor inputs', () {
      // Extremely high MAF (300 g/s to 5000 g/s)
      for (final maf in [300.0, 500.0, 1000.0, 5000.0]) {
        final flow = calculator.calculateFuelFlowLitersPerHour(
          rpm: 6500,
          mafGramsPerSecond: maf,
        );
        expect(flow, 60.0);
      }

      // Extremely high direct fuel rate (100 to 1000 L/h)
      for (final dfr in [65.0, 100.0, 500.0]) {
        final flow = calculator.calculateFuelFlowLitersPerHour(
          rpm: 3000,
          directFuelRateLPerHour: dfr,
        );
        expect(flow, 60.0);
      }

      // Extremely high speed-density (8000 RPM, 100% load)
      final flowSDHigh = calculator.calculateFuelFlowLitersPerHour(
        rpm: 8000,
        engineLoadPercent: 100.0,
      );
      expect(flowSDHigh, lessThanOrEqualTo(60.0));
      expect(flowSDHigh, greaterThan(0.0));
    });

    test('clamps fuel economy to [0.0, 99.9] under extreme low speed & high flow', () {
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 60.0,
        speedKmH: 1, // 60.0 / 1 * 100 = 6000.0 L/100km -> clamped to 99.9
      );
      expect(economy, 99.9);

      final economy2 = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 20.0,
        speedKmH: 2, // 20.0 / 2 * 100 = 1000.0 -> clamped to 99.9
      );
      expect(economy2, 99.9);
    });

    test('fuzzes 10,000 parameter combinations: 0 NaNs, 0 Infinities, non-negative, clamped', () {
      final rng = Random(1337);
      int nanCount = 0;
      int infCount = 0;
      int flowOutOfBounds = 0;
      int economyOutOfBounds = 0;

      for (int i = 0; i < 10000; i++) {
        final rpm = rng.nextInt(10000) - 1000; // -1000 to 9000
        final speed = rng.nextInt(300) - 50; // -50 to 250
        final mafChoice = rng.nextInt(4);
        final double? maf = mafChoice == 0
            ? null
            : (mafChoice == 1 ? -rng.nextDouble() * 20 : rng.nextDouble() * 350.0);
        final dfrChoice = rng.nextInt(4);
        final double? dfr = dfrChoice == 0
            ? null
            : (dfrChoice == 1 ? -rng.nextDouble() * 10 : rng.nextDouble() * 150.0);
        final throttle = rng.nextDouble() * 150.0 - 25.0; // -25% to 125%
        final load = rng.nextDouble() * 150.0 - 25.0; // -25% to 125%
        final stft = rng.nextDouble() * 200.0 - 100.0; // -100% to +100%
        final ltft = rng.nextDouble() * 200.0 - 100.0; // -100% to +100%

        final flow = calculator.calculateFuelFlowLitersPerHour(
          rpm: rpm,
          speedKmH: speed,
          mafGramsPerSecond: maf,
          directFuelRateLPerHour: dfr,
          throttlePositionPercent: throttle,
          engineLoadPercent: load,
          shortTermFuelTrimPercent: stft,
          longTermFuelTrimPercent: ltft,
        );

        final economy = calculator.calculateLitersPer100Km(
          fuelFlowLitersPerHour: flow,
          speedKmH: speed,
        );

        if (flow.isNaN || economy.isNaN) nanCount++;
        if (flow.isInfinite || economy.isInfinite) infCount++;
        if (flow < 0.0 || flow > 60.0) flowOutOfBounds++;
        if (economy < 0.0 || economy > 99.9) economyOutOfBounds++;
      }

      expect(nanCount, 0, reason: 'NaNs detected during fuzzing');
      expect(infCount, 0, reason: 'Infinities detected during fuzzing');
      expect(flowOutOfBounds, 0, reason: 'Fuel flow bounds violation [0.0, 60.0]');
      expect(economyOutOfBounds, 0, reason: 'Fuel economy bounds violation [0.0, 99.9]');
    });
  });
}
