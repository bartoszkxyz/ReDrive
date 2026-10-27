import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/trip_route_point.dart';

/// Represents a recorded driving trip with telemetry, fuel consumption history,
/// diagnostic anomaly episodes, and timeseries recording metadata.
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
  final int problemCount;
  final int suspicionCount;
  final List<TripAnomalyEpisode> anomalies;
  final List<String> recordedDtcs;
  final List<TripRoutePoint> routePoints;
  final bool hasTimeseries;
  final bool isSynced;
  final bool isExported;
  final String? exportedPath;

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
    this.problemCount = 0,
    this.suspicionCount = 0,
    this.anomalies = const [],
    this.recordedDtcs = const [],
    this.routePoints = const [],
    this.hasTimeseries = false,
    this.isSynced = false,
    this.isExported = false,
    this.exportedPath,
  });

  bool get hasRoute => routePoints.length >= 2;

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
    int? problemCount,
    int? suspicionCount,
    List<TripAnomalyEpisode>? anomalies,
    List<String>? recordedDtcs,
    List<TripRoutePoint>? routePoints,
    bool? hasTimeseries,
    bool? isSynced,
    bool? isExported,
    String? exportedPath,
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
        problemCount: problemCount ?? this.problemCount,
        suspicionCount: suspicionCount ?? this.suspicionCount,
        anomalies: anomalies ?? this.anomalies,
        recordedDtcs: recordedDtcs ?? this.recordedDtcs,
        routePoints: routePoints ?? this.routePoints,
        hasTimeseries: hasTimeseries ?? this.hasTimeseries,
        isSynced: isSynced ?? this.isSynced,
        isExported: isExported ?? this.isExported,
        exportedPath: exportedPath ?? this.exportedPath,
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
        'problemCount': problemCount,
        'suspicionCount': suspicionCount,
        'anomalies': anomalies.map((a) => a.toJson()).toList(),
        'recordedDtcs': recordedDtcs,
        'routePoints': routePoints.map((p) => p.toJson()).toList(),
        'hasTimeseries': hasTimeseries,
        'isSynced': isSynced,
        'isExported': isExported,
        'exportedPath': exportedPath,
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

  static bool _toBool(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    return val.toString().toLowerCase() == 'true';
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    final parsedAnomalies = <TripAnomalyEpisode>[];
    final rawAnomalies = json['anomalies'];
    if (rawAnomalies is Iterable) {
      for (final item in rawAnomalies) {
        if (item is Map<String, dynamic>) {
          parsedAnomalies.add(TripAnomalyEpisode.fromJson(item));
        } else if (item is Map) {
          parsedAnomalies
              .add(TripAnomalyEpisode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final parsedDtcs = <String>[];
    final rawDtcs = json['recordedDtcs'];
    if (rawDtcs is Iterable) {
      for (final item in rawDtcs) {
        if (item != null) parsedDtcs.add(item.toString());
      }
    }

    final parsedRoutePoints = <TripRoutePoint>[];
    final rawRoutePoints = json['routePoints'];
    if (rawRoutePoints is Iterable) {
      for (final item in rawRoutePoints) {
        if (item != null) {
          try {
            parsedRoutePoints.add(TripRoutePoint.fromJson(item));
          } catch (_) {}
        }
      }
    }

    final defaultProblems = parsedAnomalies
        .where((a) => a.severity == AnomalySeverity.problem)
        .length;
    final defaultSuspicions = parsedAnomalies
        .where((a) => a.severity == AnomalySeverity.suspicion)
        .length;

    return Trip(
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
      problemCount: json.containsKey('problemCount')
          ? _toInt(json['problemCount'])
          : defaultProblems,
      suspicionCount: json.containsKey('suspicionCount')
          ? _toInt(json['suspicionCount'])
          : defaultSuspicions,
      anomalies: parsedAnomalies,
      recordedDtcs: parsedDtcs,
      routePoints: parsedRoutePoints,
      hasTimeseries: _toBool(json['hasTimeseries']),
      isSynced: _toBool(json['isSynced']),
      isExported: _toBool(json['isExported']),
      exportedPath: json['exportedPath']?.toString(),
    );
  }

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
          avgRpm == other.avgRpm &&
          problemCount == other.problemCount &&
          suspicionCount == other.suspicionCount &&
          hasTimeseries == other.hasTimeseries &&
          isSynced == other.isSynced &&
          isExported == other.isExported &&
          exportedPath == other.exportedPath;

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
      avgRpm.hashCode ^
      problemCount.hashCode ^
      suspicionCount.hashCode ^
      hasTimeseries.hashCode ^
      isSynced.hashCode ^
      isExported.hashCode ^
      (exportedPath?.hashCode ?? 0);

  @override
  String toString() =>
      'Trip(id: $id, distance: ${distanceKm.toStringAsFixed(2)} km, '
      'duration: ${duration.inMinutes}m, avgSpeed: ${avgSpeed.toStringAsFixed(1)} km/h, '
      'fuel: ${fuelConsumedLiters.toStringAsFixed(2)} L, '
      'problems: $problemCount, suspicions: $suspicionCount)';
}
