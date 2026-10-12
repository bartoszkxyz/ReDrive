import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';

void main() {
  const calculator = FuelCalculator(displacementLiters: 1.8);

  group('FuelCalculator.calculateFuelFlowLitersPerHour', () {
    test('returns 0 when engine is off (0 RPM)', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 0,
        engineLoadPercent: 0,
      );
      expect(flow, 0.0);
    });

    test('detects Deceleration Fuel Cut-Off (DFCO)', () {
      // Vehicle coasting in gear at 60 km/h, 2200 RPM, throttle 0%, low load
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 60,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 4.5,
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

    test('calculates realistic idle fuel flow (0.5 to 1.2 L/h) at 800 RPM', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 800,
        engineLoadPercent: 20.0,
      );
      // Expected around 0.69 L/h
      expect(flow, greaterThan(0.5));
      expect(flow, lessThan(1.2));
    });

    test('calculates cruising fuel flow at 2500 RPM', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        engineLoadPercent: 40.0,
      );
      // Expected around 4.8 L/h
      expect(flow, greaterThan(3.5));
      expect(flow, lessThan(7.0));
    });

    test('uses MAF sensor when provided', () {
      // 10 g/s of air -> 10 * 3600 / (14.7 * 820) ≈ 2.98 L/h
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
      );
      expect(flow, closeTo(2.98, 0.2));
    });

    test('adjusts MAF flow rate using fuel trims', () {
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

      // Higher AFR reduces fuel liters per hour for given grams of air
      expect(flowWithTrim, lessThan(flowNormal));
    });

    test('applies calibration multiplier', () {
      const calibratedCalc = FuelCalculator(
        displacementLiters: 1.8,
        calibrationFactor: 1.10, // +10% pump calibration
      );

      final flow = calibratedCalc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        directFuelRateLPerHour: 5.0,
      );
      expect(flow, closeTo(5.5, 0.01));
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

    test('calculates correct L/100km at 90 km/h with 5.4 L/h flow', () {
      // (5.4 / 90) * 100 = 6.0 L/100km
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 5.4,
        speedKmH: 90,
      );
      expect(economy, closeTo(6.0, 0.01));
    });

    test('clamps unreasonably high values', () {
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 30.0,
        speedKmH: 10,
      );
      expect(economy, lessThanOrEqualTo(99.9));
    });
  });
}
