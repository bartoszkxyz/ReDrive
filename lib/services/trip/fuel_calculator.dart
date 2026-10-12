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
    if (speedKmH > 20 &&
        rpm > 1300 &&
        throttlePositionPercent < 1.0 &&
        engineLoadPercent < 18.0) {
      return 0.0;
    }

    // Tier 1: Direct ECU Engine Fuel Rate (Mode 01 PID 015E)
    if (directFuelRateLPerHour != null && directFuelRateLPerHour > 0) {
      return (directFuelRateLPerHour * calibrationFactor).clamp(0.0, 60.0);
    }

    // Compute effective AFR with fuel trim adjustment
    final trimMultiplier = 1.0 + ((shortTermFuelTrimPercent + longTermFuelTrimPercent) / 100.0);
    final effectiveAfr = (airFuelRatio * trimMultiplier).clamp(9.0, 20.0);
    final airGramsPerFuelLiter = effectiveAfr * fuelDensityGramsPerLiter;

    // Tier 2: Direct Air Mass (MAF) sensor (Mode 01 PID 0110)
    if (mafGramsPerSecond != null && mafGramsPerSecond > 0) {
      final fuelLPerHour = (mafGramsPerSecond * 3600.0) / airGramsPerFuelLiter;
      return (fuelLPerHour * calibrationFactor).clamp(0.0, 60.0);
    }

    // Tier 3: Load-adjusted speed-density volumetric fallback (Mode 01 PID 0104 + RPM)
    final load = engineLoadPercent.clamp(10.0, 100.0);
    final airGramsPerSec = (rpm * displacementLiters * (load / 100.0)) / 125.0;
    final fuelLitersPerHour = (airGramsPerSec * 3600.0) / airGramsPerFuelLiter;

    return (fuelLitersPerHour * calibrationFactor).clamp(0.0, 60.0);
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
