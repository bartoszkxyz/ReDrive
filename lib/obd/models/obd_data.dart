class ObdData {
  final int rpm;
  final int speed;
  final int coolantTemp;
  final int intakeAirTemp;
  final double voltage;
  final double engineLoad;
  final double throttlePosition;
  final double maf;
  final double engineFuelRate;
  final double instantFuelLPerHour;
  final double instantFuelL100km;

  const ObdData({
    this.rpm = 0,
    this.speed = 0,
    this.coolantTemp = 0,
    this.intakeAirTemp = 0,
    this.voltage = 0.0,
    this.engineLoad = 0.0,
    this.throttlePosition = 0.0,
    this.maf = 0.0,
    this.engineFuelRate = 0.0,
    this.instantFuelLPerHour = 0.0,
    this.instantFuelL100km = 0.0,
  });

  ObdData copyWith({
    int? rpm,
    int? speed,
    int? coolantTemp,
    int? intakeAirTemp,
    double? voltage,
    double? engineLoad,
    double? throttlePosition,
    double? maf,
    double? engineFuelRate,
    double? instantFuelLPerHour,
    double? instantFuelL100km,
  }) {
    return ObdData(
      rpm: rpm ?? this.rpm,
      speed: speed ?? this.speed,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      intakeAirTemp: intakeAirTemp ?? this.intakeAirTemp,
      voltage: voltage ?? this.voltage,
      engineLoad: engineLoad ?? this.engineLoad,
      throttlePosition: throttlePosition ?? this.throttlePosition,
      maf: maf ?? this.maf,
      engineFuelRate: engineFuelRate ?? this.engineFuelRate,
      instantFuelLPerHour: instantFuelLPerHour ?? this.instantFuelLPerHour,
      instantFuelL100km: instantFuelL100km ?? this.instantFuelL100km,
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
        'maf: ${maf.toStringAsFixed(2)} g/s, '
        'directFuelRate: ${engineFuelRate.toStringAsFixed(2)} L/h, '
        'fuelRate: ${instantFuelLPerHour.toStringAsFixed(2)} L/h, '
        'fuelEconomy: ${instantFuelL100km.toStringAsFixed(1)} L/100km'
        ')';
  }
}
