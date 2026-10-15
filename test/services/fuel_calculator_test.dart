import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';

void main() {
  // Calibrated for Suzuki Swift 3 M15A (1.5L naturally aspirated engine)
  const calculator = FuelCalculator(displacementLiters: 1.5);

  group('FuelCalculator.calculateFuelFlowLitersPerHour - M15A Baselines', () {
    test('returns 0 when engine is off (0 RPM)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 0,
        engineLoadPercent: 0,
      );
      expect(flow, 0.0);
    });

    test('returns 0 when RPM is negative', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: -500,
        engineLoadPercent: 0,
      );
      expect(flow, 0.0);
    });

    test('prioritizes Direct ECU Fuel Rate (PID 015E)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        directFuelRateLPerHour: 5.75,
        mafGramsPerSecond: 20.0,
        engineLoadPercent: 50.0,
      );
      expect(flow, 5.75);
    });

    test('calculates realistic idle fuel flow (0.6 to 0.9 L/h) at ~750 RPM with MAF', () {
      // Warm idle MAF sensor reading for 1.5L M15A is typically 2.0 - 2.5 g/s
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 750,
        mafGramsPerSecond: 2.3,
        engineLoadPercent: 25.0,
      );
      // Stoichiometric baseline: 2.3 * 3600 / (14.7 * 820) ≈ 0.6869 L/h
      expect(flow, greaterThanOrEqualTo(0.60));
      expect(flow, lessThanOrEqualTo(0.90));
      expect(flow, closeTo(0.687, 0.02));
    });

    test('calculates realistic idle fuel flow (0.6 to 0.9 L/h) at ~750 RPM with volumetric fallback', () {
      // Warm idle without MAF: 750 RPM, 25% load, 1.5L displacement
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 750,
        engineLoadPercent: 25.0,
      );
      // Speed-density: (750 * 1.5 * 0.25) / 125 = 2.25 g/s air -> 2.25 * 3600 / 12054 ≈ 0.672 L/h
      expect(flow, greaterThanOrEqualTo(0.60));
      expect(flow, lessThanOrEqualTo(0.90));
      expect(flow, closeTo(0.672, 0.02));
    });

    test('calculates cruising fuel flow (2.7 to 3.9 L/h) at 2000 RPM 60 km/h with MAF', () {
      // Cruising at 60 km/h: ~4.5 - 6.5 L/100km corresponds to 2.7 - 3.9 L/h
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 60,
        mafGramsPerSecond: 11.0,
        engineLoadPercent: 45.0,
      );
      // 11.0 * 3600 / 12054 ≈ 3.285 L/h
      expect(flow, greaterThanOrEqualTo(2.70));
      expect(flow, lessThanOrEqualTo(3.90));

      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: flow,
        speedKmH: 60,
      );
      // (3.285 / 60) * 100 ≈ 5.48 L/100km (within 4.5 - 6.5 L/100km baseline)
      expect(economy, greaterThanOrEqualTo(4.5));
      expect(economy, lessThanOrEqualTo(6.5));
    });

    test('calculates cruising fuel economy (4.5 to 6.5 L/100km) with volumetric fallback', () {
      // 2000 RPM, 60 km/h, 45% load, 1.5L displacement without MAF
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 60,
        engineLoadPercent: 45.0,
      );
      // Air: (2000 * 1.5 * 0.45) / 125 = 10.8 g/s -> 10.8 * 3600 / 12054 ≈ 3.225 L/h
      expect(flow, greaterThanOrEqualTo(2.70));
      expect(flow, lessThanOrEqualTo(3.90));

      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: flow,
        speedKmH: 60,
      );
      // (3.225 / 60) * 100 ≈ 5.38 L/100km
      expect(economy, greaterThanOrEqualTo(4.5));
      expect(economy, lessThanOrEqualTo(6.5));
    });

    test('detects Deceleration Fuel Cut-Off (DFCO) with throttle 0%', () {
      // Vehicle coasting in gear at 60 km/h, 2200 RPM, throttle 0%, low load
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 60,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 4.5,
      );
      expect(flow, 0.0);

      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: flow,
        speedKmH: 60,
      );
      expect(economy, 0.0);
    });

    test('detects DFCO when throttle is at physical closed idle position (<= 14%)', () {
      // Physical Suzuki Swift M15A throttle body reports ~10-14% at closed stop
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 60,
        throttlePositionPercent: 12.0,
        engineLoadPercent: 14.0,
      );
      expect(flow, 0.0);

      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: flow,
        speedKmH: 60,
      );
      expect(economy, 0.0);
    });

    test('de-asserts DFCO below cutoff speed (<= 20 km/h)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 18,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
      );
      expect(flow, greaterThan(0.0));
    });

    test('de-asserts DFCO below recovery RPM (<= 1300 RPM)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1200,
        speedKmH: 60,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
      );
      expect(flow, greaterThan(0.0));
    });

    test('de-asserts DFCO on throttle tip-in (> 14%)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 60,
        throttlePositionPercent: 25.0,
        engineLoadPercent: 12.0,
      );
      expect(flow, greaterThan(0.0));
    });

    test('de-asserts DFCO under engine load (>= 18%)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 60,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 22.0,
      );
      expect(flow, greaterThan(0.0));
    });

    test('uses MAF sensor when provided at stoichiometric baseline', () {
      // 10 g/s of air -> 10 * 3600 / (14.7 * 820) ≈ 2.9866 L/h
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
      );
      expect(flow, closeTo(2.987, 0.02));
    });

    test('positive fuel trim (+10%) increases fuel flow rate proportionally', () {
      // +10% positive fuel trim (STFT + LTFT = 10%) means lean correction / extra fuel
      final flowNormal = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
      );
      final flowWithTrim = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: 5.0,
        longTermFuelTrimPercent: 5.0,
      );

      // Positive fuel trim adds fuel (+10% flow)
      expect(flowWithTrim, greaterThan(flowNormal));
      expect(flowWithTrim, closeTo(flowNormal * 1.10, 0.01));
    });

    test('negative fuel trim (-10%) decreases fuel flow rate proportionally', () {
      // -10% negative fuel trim (STFT + LTFT = -10%) means rich correction / less fuel
      final flowNormal = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
      );
      final flowWithTrim = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: -5.0,
        longTermFuelTrimPercent: -5.0,
      );

      // Negative fuel trim reduces fuel (-10% flow)
      expect(flowWithTrim, lessThan(flowNormal));
      expect(flowWithTrim, closeTo(flowNormal * 0.90, 0.01));
    });

    test('fuel trims scale volumetric fallback flow proportionally', () {
      final flowNormal = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        engineLoadPercent: 40.0,
      );
      final flowWithTrim = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        engineLoadPercent: 40.0,
        shortTermFuelTrimPercent: 10.0,
      );

      expect(flowWithTrim, greaterThan(flowNormal));
      expect(flowWithTrim, closeTo(flowNormal * 1.10, 0.01));
    });

    test('applies calibration multiplier', () {
      const calibratedCalc = FuelCalculator(
        displacementLiters: 1.5,
        calibrationFactor: 1.10, // +10% pump calibration
      );

      final flow = calibratedCalc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        directFuelRateLPerHour: 5.0,
      );
      expect(flow, closeTo(5.5, 0.01));
    });

    test('clamps fuel flow to 60.0 L/h maximum', () {
      final flowFromDfr = calculator.calculateFuelFlowLitersPerHour(
        rpm: 3000,
        directFuelRateLPerHour: 100.0,
      );
      expect(flowFromDfr, 60.0);

      final flowFromMaf = calculator.calculateFuelFlowLitersPerHour(
        rpm: 3000,
        mafGramsPerSecond: 250.0,
      );
      expect(flowFromMaf, 60.0);
    });

    test('clamps volumetric fallback engine load between 10% and 100%', () {
      // Load 5% clamped to 10%
      final flowLowLoad = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1000,
        engineLoadPercent: 5.0,
      );
      final flowAt10Load = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1000,
        engineLoadPercent: 10.0,
      );
      expect(flowLowLoad, equals(flowAt10Load));

      // Load 120% clamped to 100%
      final flowOverLoad = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1000,
        engineLoadPercent: 120.0,
      );
      final flowAt100Load = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1000,
        engineLoadPercent: 100.0,
      );
      expect(flowOverLoad, equals(flowAt100Load));
    });

    test('scales volumetric fallback by displacement (1.5L vs 1.8L)', () {
      const calc18 = FuelCalculator(displacementLiters: 1.8);
      final flow15 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        engineLoadPercent: 40.0,
      );
      final flow18 = calc18.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        engineLoadPercent: 40.0,
      );

      expect(flow15, closeTo(flow18 * (1.5 / 1.8), 0.001));
    });
  });

  group('FuelCalculator.calculateLitersPer100Km', () {
    test('returns 0.0 when stationary (speed == 0)', () {
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 0.8,
        speedKmH: 0,
      );
      expect(economy, 0.0);
    });

    test('returns 0.0 when speed is negative', () {
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 0.8,
        speedKmH: -20,
      );
      expect(economy, 0.0);
    });

    test('returns 0.0 when fuel flow is zero or negative', () {
      expect(
        calculator.calculateLitersPer100Km(
          fuelFlowLitersPerHour: 0.0,
          speedKmH: 60,
        ),
        0.0,
      );
      expect(
        calculator.calculateLitersPer100Km(
          fuelFlowLitersPerHour: -2.5,
          speedKmH: 60,
        ),
        0.0,
      );
    });

    test('calculates correct L/100km at 90 km/h with 5.4 L/h flow', () {
      // (5.4 / 90) * 100 = 6.0 L/100km
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 5.4,
        speedKmH: 90,
      );
      expect(economy, closeTo(6.0, 0.01));
    });

    test('clamps unreasonably high values to 99.9 L/100km', () {
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 30.0,
        speedKmH: 10,
      );
      expect(economy, lessThanOrEqualTo(99.9));

      final extreme = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 50.0,
        speedKmH: 2,
      );
      expect(extreme, 99.9);
    });
  });
}
