/// Represents a recorded driving trip with telemetry and fuel consumption history.
class Trip {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final double distanceKm;
  final double fuelConsumedLiters;
  final double avgFuelConsumption; // L/100km
  final double avgSpeed; // km/h
  final double maxSpeed; // km/h
  final int maxRpm;
  final int avgRpm;

  const Trip({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distanceKm,
    required this.fuelConsumedLiters,
    required this.avgFuelConsumption,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.maxRpm,
    required this.avgRpm,
  });

  // Getter aliases for Requirement R2 compatibility
  double get averageSpeedKmH => avgSpeed;
  double get averageFuelL100km => avgFuelConsumption;
  double get maxSpeedKmH => maxSpeed;
  int get durationSeconds => duration.inSeconds;

  Trip copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    double? distanceKm,
    double? fuelConsumedLiters,
    double? avgFuelConsumption,
    double? avgSpeed,
    double? maxSpeed,
    int? maxRpm,
    int? avgRpm,
  }) =>
      Trip(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        duration: duration ?? this.duration,
        distanceKm: distanceKm ?? this.distanceKm,
        fuelConsumedLiters: fuelConsumedLiters ?? this.fuelConsumedLiters,
        avgFuelConsumption: avgFuelConsumption ?? this.avgFuelConsumption,
        avgSpeed: avgSpeed ?? this.avgSpeed,
        maxSpeed: maxSpeed ?? this.maxSpeed,
        maxRpm: maxRpm ?? this.maxRpm,
        avgRpm: avgRpm ?? this.avgRpm,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'distanceKm': distanceKm,
    'fuelConsumedLiters': fuelConsumedLiters,
    'avgFuelConsumption': avgFuelConsumption,
    'avgSpeed': avgSpeed,
    'maxSpeed': maxSpeed,
    'maxRpm': maxRpm,
    'avgRpm': avgRpm,
    // Aliases for compatibility
    'averageSpeedKmH': avgSpeed,
    'averageFuelL100km': avgFuelConsumption,
    'maxSpeedKmH': maxSpeed,
  };

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  static int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: (json['id'] ?? '').toString(),
    startTime: DateTime.tryParse(json['startTime']?.toString() ?? '') ??
        DateTime.now(),
    endTime: DateTime.tryParse(json['endTime']?.toString() ?? '') ??
        DateTime.now(),
    duration: Duration(
      seconds: _toInt(json['durationSeconds'] ?? json['duration']),
    ),
    distanceKm: _toDouble(json['distanceKm']),
    fuelConsumedLiters: _toDouble(json['fuelConsumedLiters']),
    avgFuelConsumption: _toDouble(
      json['avgFuelConsumption'] ?? json['averageFuelL100km'],
    ),
    avgSpeed: _toDouble(json['avgSpeed'] ?? json['averageSpeedKmH']),
    maxSpeed: _toDouble(json['maxSpeed'] ?? json['maxSpeedKmH']),
    maxRpm: _toInt(json['maxRpm']),
    avgRpm: _toInt(json['avgRpm']),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Trip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          duration == other.duration &&
          distanceKm == other.distanceKm &&
          fuelConsumedLiters == other.fuelConsumedLiters &&
          avgFuelConsumption == other.avgFuelConsumption &&
          avgSpeed == other.avgSpeed &&
          maxSpeed == other.maxSpeed &&
          maxRpm == other.maxRpm &&
          avgRpm == other.avgRpm;

  @override
  int get hashCode =>
      id.hashCode ^
      startTime.hashCode ^
      endTime.hashCode ^
      duration.hashCode ^
      distanceKm.hashCode ^
      fuelConsumedLiters.hashCode ^
      avgFuelConsumption.hashCode ^
      avgSpeed.hashCode ^
      maxSpeed.hashCode ^
      maxRpm.hashCode ^
      avgRpm.hashCode;

  @override
  String toString() =>
      'Trip(id: $id, distance: ${distanceKm.toStringAsFixed(2)} km, '
      'duration: ${duration.inMinutes}m, avgSpeed: ${avgSpeed.toStringAsFixed(1)} km/h, '
      'fuel: ${fuelConsumedLiters.toStringAsFixed(2)} L)';
}
