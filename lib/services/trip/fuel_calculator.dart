/// Computes instantaneous fuel flow and fuel economy from OBD telemetry
/// based on industry-standard SAE J1979 / ISO 15031-5 specifications.
class FuelCalculator {
  /// Engine displacement in liters (e.g. 1.8L, 2.0L).
  final double displacementLiters;

  /// Stoichiometric air-to-fuel ratio (default 14.7:1 for gasoline; 14.5:1 for diesel, 14.08:1 for E10).
  final double airFuelRatio;

  /// Fuel density in grams per liter (default 820 g/L for gasoline; 840 g/L for diesel).
  final double fuelDensityGramsPerLiter;

  /// User-adjustable calibration multiplier (e.g. 1.00 ± 0.15) for pump receipt reconciliation.
  final double calibrationFactor;

  const FuelCalculator({
    this.displacementLiters = 1.5,
    this.airFuelRatio = 14.7,
    this.fuelDensityGramsPerLiter = 820.0,
    this.calibrationFactor = 1.0,
  });

  /// Calculates instantaneous fuel flow in liters per hour (L/h).
  ///
  /// Prioritizes sensor data based on OBD-II accuracy tiers:
  /// 1. Deceleration Fuel Cut-Off (DFCO) check (0.0 L/h during closed-throttle deceleration).
  /// 2. Direct ECU Engine Fuel Rate (PID 015E).
  /// 3. MAF Sensor (PID 0110) adjusted by STFT/LTFT if provided.
  /// 4. Speed-Density / Load fallback (PID 0104 + Engine RPM).
  double calculateFuelFlowLitersPerHour({
    required int rpm,
    double engineLoadPercent = 25.0,
    double? mafGramsPerSecond,
    double? directFuelRateLPerHour,
    double throttlePositionPercent = 0.0,
    int speedKmH = 0,
    double shortTermFuelTrimPercent = 0.0,
    double longTermFuelTrimPercent = 0.0,
  }) {
    if (rpm <= 0) return 0.0;

    // Deceleration Fuel Cut-Off (DFCO):
    // When moving in gear at speed and coasting with throttle closed, the ECU completely shuts off injectors.
    // Supports both relative throttle (< 1.0%) and Suzuki Swift 3 M15A absolute closed throttle (10% - 14%).
    final isThrottleClosed = throttlePositionPercent < 1.0 ||
        (throttlePositionPercent >= 10.0 && throttlePositionPercent <= 14.0);
    if (speedKmH > 20 &&
        rpm > 1300 &&
        isThrottleClosed &&
        engineLoadPercent < 18.0) {
      return 0.0;
    }

    // Tier 1: Direct ECU Engine Fuel Rate (Mode 01 PID 015E)
    if (directFuelRateLPerHour != null && directFuelRateLPerHour > 0) {
      return (directFuelRateLPerHour * calibrationFactor).clamp(0.0, 60.0);
    }

    // Fuel Trim Compensation:
    // Positive trims (ECU correcting lean mixture) command additional fuel.
    // Negative trims (ECU correcting rich mixture) command less fuel.
    // Multiplier is clamped to [0.5, 1.5] (±50%) to guard against corrupted OBD packets.
    final trimMultiplier = (1.0 + ((shortTermFuelTrimPercent + longTermFuelTrimPercent) / 100.0)).clamp(0.5, 1.5);
    final airGramsPerFuelLiter = airFuelRatio * fuelDensityGramsPerLiter;

    // Tier 2: Direct Air Mass (MAF) sensor (Mode 01 PID 0110)
    if (mafGramsPerSecond != null && mafGramsPerSecond > 0) {
      final fuelLPerHour = (mafGramsPerSecond * 3600.0) / airGramsPerFuelLiter * trimMultiplier;
      return (fuelLPerHour * calibrationFactor).clamp(0.0, 60.0);
    }

    // Tier 3: Load-adjusted speed-density volumetric fallback (Mode 01 PID 0104 + RPM)
    final load = engineLoadPercent.clamp(10.0, 100.0);
    final airGramsPerSec = (rpm * displacementLiters * (load / 100.0)) / 125.0;
    final fuelLPerHour = (airGramsPerSec * 3600.0) / airGramsPerFuelLiter * trimMultiplier;

    return (fuelLPerHour * calibrationFactor).clamp(0.0, 60.0);
  }

  /// Calculates fuel consumption in Liters per 100 Kilometers (L/100km).
  ///
  /// Returns 0.0 when vehicle is stationary (speed == 0).
  double calculateLitersPer100Km({
    required double fuelFlowLitersPerHour,
    required int speedKmH,
  }) {
    if (speedKmH <= 0 || fuelFlowLitersPerHour <= 0) return 0.0;

    // (L/h / km/h) * 100 = L/100km
    final l100km = (fuelFlowLitersPerHour / speedKmH) * 100.0;
    return l100km.clamp(0.0, 99.9);
  }
}
