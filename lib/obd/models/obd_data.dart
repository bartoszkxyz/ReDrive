import 'fuel_system_status.dart';

export 'fuel_system_status.dart';

class ObdData {
  final int rpm;
  final int speed;
  final int coolantTemp;
  final int intakeAirTemp;
  final double voltage;
  final double engineLoad;
  final double throttlePosition;
  final double relativeThrottle;
  final double maf;
  final double engineFuelRate;
  final double instantFuelLPerHour;
  final double instantFuelL100km;

  // Category 2 Expanded Sensor Metrics
  final double shortTermFuelTrim;
  final double longTermFuelTrim;
  final double timingAdvance;
  final double manifoldPressure;
  final double fuelLevelPercent;
  final FuelSystemStatus fuelSystemStatus;

  // Zero-Overhead Derived Dynamic Metrics
  final double horsepower;
  final double torqueNm;
  final double accelerationG;
  final bool isDfcoActive;
  final double remainingFuelLiters;
  final double estimatedRangeKm;

  const ObdData({
    this.rpm = 0,
    this.speed = 0,
    this.coolantTemp = 0,
    this.intakeAirTemp = 0,
    this.voltage = 0.0,
    this.engineLoad = 0.0,
    this.throttlePosition = 0.0,
    this.relativeThrottle = 0.0,
    this.maf = 0.0,
    this.engineFuelRate = 0.0,
    this.instantFuelLPerHour = 0.0,
    this.instantFuelL100km = 0.0,
    this.shortTermFuelTrim = 0.0,
    this.longTermFuelTrim = 0.0,
    this.timingAdvance = 0.0,
    this.manifoldPressure = 0.0,
    this.fuelLevelPercent = 0.0,
    this.fuelSystemStatus = FuelSystemStatus.unknown,
    this.horsepower = 0.0,
    this.torqueNm = 0.0,
    this.accelerationG = 0.0,
    this.isDfcoActive = false,
    this.remainingFuelLiters = 0.0,
    this.estimatedRangeKm = 0.0,
  });

  ObdData copyWith({
    int? rpm,
    int? speed,
    int? coolantTemp,
    int? intakeAirTemp,
    double? voltage,
    double? engineLoad,
    double? throttlePosition,
    double? relativeThrottle,
    double? maf,
    double? engineFuelRate,
    double? instantFuelLPerHour,
    double? instantFuelL100km,
    double? shortTermFuelTrim,
    double? longTermFuelTrim,
    double? timingAdvance,
    double? manifoldPressure,
    double? fuelLevelPercent,
    FuelSystemStatus? fuelSystemStatus,
    double? horsepower,
    double? torqueNm,
    double? accelerationG,
    bool? isDfcoActive,
    double? remainingFuelLiters,
    double? estimatedRangeKm,
  }) {
    return ObdData(
      rpm: rpm ?? this.rpm,
      speed: speed ?? this.speed,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      intakeAirTemp: intakeAirTemp ?? this.intakeAirTemp,
      voltage: voltage ?? this.voltage,
      engineLoad: engineLoad ?? this.engineLoad,
      throttlePosition: throttlePosition ?? this.throttlePosition,
      relativeThrottle: relativeThrottle ?? this.relativeThrottle,
      maf: maf ?? this.maf,
      engineFuelRate: engineFuelRate ?? this.engineFuelRate,
      instantFuelLPerHour: instantFuelLPerHour ?? this.instantFuelLPerHour,
      instantFuelL100km: instantFuelL100km ?? this.instantFuelL100km,
      shortTermFuelTrim: shortTermFuelTrim ?? this.shortTermFuelTrim,
      longTermFuelTrim: longTermFuelTrim ?? this.longTermFuelTrim,
      timingAdvance: timingAdvance ?? this.timingAdvance,
      manifoldPressure: manifoldPressure ?? this.manifoldPressure,
      fuelLevelPercent: fuelLevelPercent ?? this.fuelLevelPercent,
      fuelSystemStatus: fuelSystemStatus ?? this.fuelSystemStatus,
      horsepower: horsepower ?? this.horsepower,
      torqueNm: torqueNm ?? this.torqueNm,
      accelerationG: accelerationG ?? this.accelerationG,
      isDfcoActive: isDfcoActive ?? this.isDfcoActive,
      remainingFuelLiters: remainingFuelLiters ?? this.remainingFuelLiters,
      estimatedRangeKm: estimatedRangeKm ?? this.estimatedRangeKm,
    );
  }

  @override
  String toString() {
    return 'ObdData('
        'rpm: $rpm, '
        'speed: $speed km/h, '
        'coolantTemp: $coolantTemp°C, '
        'iat: $intakeAirTemp°C, '
        'voltage: $voltage V, '
        'load: ${engineLoad.toStringAsFixed(1)}%, '
        'throttle: ${throttlePosition.toStringAsFixed(1)}%, '
        'relThrottle: ${relativeThrottle.toStringAsFixed(1)}%, '
        'maf: ${maf.toStringAsFixed(2)} g/s, '
        'directFuelRate: ${engineFuelRate.toStringAsFixed(2)} L/h, '
        'fuelRate: ${instantFuelLPerHour.toStringAsFixed(2)} L/h, '
        'fuelEconomy: ${instantFuelL100km.toStringAsFixed(1)} L/100km, '
        'hp: ${horsepower.toStringAsFixed(1)} HP, '
        'torque: ${torqueNm.toStringAsFixed(1)} Nm, '
        'gForce: ${accelerationG.toStringAsFixed(2)} g, '
        'dfco: $isDfcoActive, '
        'stft: ${shortTermFuelTrim.toStringAsFixed(1)}%, '
        'ltft: ${longTermFuelTrim.toStringAsFixed(1)}%, '
        'timing: ${timingAdvance.toStringAsFixed(1)}°, '
        'map: ${manifoldPressure.toStringAsFixed(1)} kPa, '
        'fuelTank: ${fuelLevelPercent.toStringAsFixed(1)}% (${remainingFuelLiters.toStringAsFixed(1)}L, ~${estimatedRangeKm.toStringAsFixed(0)}km), '
        'loopStatus: ${fuelSystemStatus.shortCode}'
        ')';
  }
}
