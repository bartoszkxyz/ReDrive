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
  };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: DateTime.parse(json['endTime'] as String),
    duration: Duration(seconds: (json['durationSeconds'] as num).toInt()),
    distanceKm: (json['distanceKm'] as num).toDouble(),
    fuelConsumedLiters: (json['fuelConsumedLiters'] as num).toDouble(),
    avgFuelConsumption: (json['avgFuelConsumption'] as num).toDouble(),
    avgSpeed: (json['avgSpeed'] as num).toDouble(),
    maxSpeed: (json['maxSpeed'] as num).toDouble(),
    maxRpm: (json['maxRpm'] as num).toInt(),
    avgRpm: (json['avgRpm'] as num).toInt(),
  );
}
