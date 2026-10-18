/// Severity level of an anomaly episode detected during a driving trip.
enum AnomalySeverity {
  /// Suspicious behavior (borderline metric or single-sample load dip / pending DTC).
  suspicion,

  /// Confirmed problem (sustained power loss, critical threshold breach, or confirmed DTC).
  problem,
}

/// Functional category of an anomaly episode.
enum AnomalyCategory {
  powerLoss,
  fuelTrim,
  thermal,
  electrical,
  vacuumIntake,
  dtcFault,
  fuelSystemFault,
}

/// Represents a debounced/grouped diagnostic episode detected during a trip.
class TripAnomalyEpisode {
  final String id;
  final AnomalySeverity severity;
  final AnomalyCategory category;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, num> peakMetrics;
  final List<String> dtcCodes;
  final double? latitude;
  final double? longitude;
  final double? elapsedSeconds;

  const TripAnomalyEpisode({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    this.peakMetrics = const {},
    this.dtcCodes = const [],
    this.latitude,
    this.longitude,
    this.elapsedSeconds,
  });

  Duration get duration => endTime.difference(startTime);

  TripAnomalyEpisode copyWith({
    String? id,
    AnomalySeverity? severity,
    AnomalyCategory? category,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    Map<String, num>? peakMetrics,
    List<String>? dtcCodes,
    double? latitude,
    double? longitude,
    double? elapsedSeconds,
  }) =>
      TripAnomalyEpisode(
        id: id ?? this.id,
        severity: severity ?? this.severity,
        category: category ?? this.category,
        title: title ?? this.title,
        description: description ?? this.description,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        peakMetrics: peakMetrics ?? this.peakMetrics,
        dtcCodes: dtcCodes ?? this.dtcCodes,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'category': category.name,
        'title': title,
        'description': description,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'peakMetrics': peakMetrics,
        'dtcCodes': dtcCodes,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (elapsedSeconds != null) 'elapsedSeconds': elapsedSeconds,
      };

  factory TripAnomalyEpisode.fromJson(Map<String, dynamic> json) {
    final severityStr = json['severity']?.toString() ?? 'suspicion';
    final categoryStr = json['category']?.toString() ?? 'powerLoss';

    final severity = AnomalySeverity.values.firstWhere(
      (e) => e.name == severityStr,
      orElse: () => AnomalySeverity.suspicion,
    );
    final category = AnomalyCategory.values.firstWhere(
      (e) => e.name == categoryStr,
      orElse: () => AnomalyCategory.powerLoss,
    );

    final rawMetrics = json['peakMetrics'];
    final parsedMetrics = <String, num>{};
    if (rawMetrics is Map) {
      for (final entry in rawMetrics.entries) {
        final v = entry.value;
        if (v is num) {
          parsedMetrics[entry.key.toString()] = v;
        } else if (v != null) {
          final parsed = num.tryParse(v.toString());
          if (parsed != null) {
            parsedMetrics[entry.key.toString()] = parsed;
          }
        }
      }
    }

    final rawDtcs = json['dtcCodes'];
    final parsedDtcs = <String>[];
    if (rawDtcs is Iterable) {
      for (final item in rawDtcs) {
        if (item != null) parsedDtcs.add(item.toString());
      }
    }

    double? parseDoubleNullable(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    final lat = parseDoubleNullable(json['latitude'] ?? json['lat']);
    final lon = parseDoubleNullable(json['longitude'] ?? json['lon']);
    final elapsed = parseDoubleNullable(
      json['elapsedSeconds'] ?? json['elapsedSec'],
    );

    final now = DateTime.now();
    return TripAnomalyEpisode(
      id: (json['id'] ?? '').toString(),
      severity: severity,
      category: category,
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      startTime:
          DateTime.tryParse(json['startTime']?.toString() ?? '') ?? now,
      endTime: DateTime.tryParse(json['endTime']?.toString() ?? '') ?? now,
      peakMetrics: parsedMetrics,
      dtcCodes: parsedDtcs,
      latitude: lat,
      longitude: lon,
      elapsedSeconds: elapsed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripAnomalyEpisode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          severity == other.severity &&
          category == other.category &&
          title == other.title &&
          description == other.description &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          elapsedSeconds == other.elapsedSeconds;

  @override
  int get hashCode =>
      id.hashCode ^
      severity.hashCode ^
      category.hashCode ^
      title.hashCode ^
      description.hashCode ^
      startTime.hashCode ^
      endTime.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      elapsedSeconds.hashCode;
}
