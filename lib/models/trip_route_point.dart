import 'dart:math' as math;

/// Represents a raw GPS fix reading from device hardware or location service.
class GpsFix {
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? speedKmh;
  final DateTime timestamp;

  const GpsFix({
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.speedKmh,
    required this.timestamp,
  });

  GpsFix copyWith({
    double? latitude,
    double? longitude,
    double? altitudeMeters,
    double? speedKmh,
    DateTime? timestamp,
  }) =>
      GpsFix(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        altitudeMeters: altitudeMeters ?? this.altitudeMeters,
        speedKmh: speedKmh ?? this.speedKmh,
        timestamp: timestamp ?? this.timestamp,
      );

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (altitudeMeters != null) 'altitudeMeters': altitudeMeters,
        if (speedKmh != null) 'speedKmh': speedKmh,
        'timestamp': timestamp.toIso8601String(),
      };

  factory GpsFix.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] ?? json['lat'] as num?)?.toDouble() ??
        double.tryParse(
          json['latitude']?.toString() ?? json['lat']?.toString() ?? '',
        ) ??
        0.0;
    final lon = (json['longitude'] ?? json['lon'] as num?)?.toDouble() ??
        double.tryParse(
          json['longitude']?.toString() ?? json['lon']?.toString() ?? '',
        ) ??
        0.0;

    double? alt;
    final rawAlt = json['altitudeMeters'] ?? json['altitude'] ?? json['alt'];
    if (rawAlt is num) {
      alt = rawAlt.toDouble();
    } else if (rawAlt != null) {
      alt = double.tryParse(rawAlt.toString());
    }

    double? spd;
    final rawSpd = json['speedKmh'] ?? json['speed'];
    if (rawSpd is num) {
      spd = rawSpd.toDouble();
    } else if (rawSpd != null) {
      spd = double.tryParse(rawSpd.toString());
    }

    final ts = DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now();

    return GpsFix(
      latitude: lat,
      longitude: lon,
      altitudeMeters: alt,
      speedKmh: spd,
      timestamp: ts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsFix &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-7 &&
          (longitude - other.longitude).abs() < 1e-7 &&
          altitudeMeters == other.altitudeMeters &&
          speedKmh == other.speedKmh &&
          timestamp.isAtSameMomentAs(other.timestamp);

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        altitudeMeters,
        speedKmh,
        timestamp,
      );

  @override
  String toString() =>
      'GpsFix(lat: $latitude, lon: $longitude, alt: $altitudeMeters, speed: $speedKmh, time: $timestamp)';
}

/// Represents a combined GPS position and synchronized OBD-II telemetry snapshot
/// downsampled for lightweight trip route storage.
class TripRoutePoint {
  final double latitude;
  final double longitude;
  final double speedKmh;
  final int rpm;
  final double fuelRateLph;
  final double fuelL100km;
  final double engineLoadPercent;
  final int coolantTempC;
  final double shortTermFuelTrim;
  final double longTermFuelTrim;
  final double elapsedSeconds;

  const TripRoutePoint({
    required this.latitude,
    required this.longitude,
    this.speedKmh = 0.0,
    this.rpm = 0,
    this.fuelRateLph = 0.0,
    this.fuelL100km = 0.0,
    this.engineLoadPercent = 0.0,
    this.coolantTempC = 0,
    this.shortTermFuelTrim = 0.0,
    this.longTermFuelTrim = 0.0,
    this.elapsedSeconds = 0.0,
  });

  /// Serializes into compact JSON representation with standard short keys.
  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        'speedKmh': speedKmh,
        'rpm': rpm,
        'fuelRateLph': fuelRateLph,
        'fuelL100km': fuelL100km,
        'engineLoad': engineLoadPercent,
        'coolantTemp': coolantTempC,
        'stft': shortTermFuelTrim,
        'ltft': longTermFuelTrim,
        'elapsedSec': elapsedSeconds,
      };

  static double _toDouble(dynamic val, [double fallback = 0.0]) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? fallback;
  }

  static int _toInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? fallback;
  }

  /// Parses from either a Map or a compact 6-element list:
  /// `[lat, lon, speedKmh, rpm, fuelRateLph, elapsedSec]`.
  factory TripRoutePoint.fromJson(dynamic json) {
    if (json is List) {
      final lat = json.isNotEmpty ? _toDouble(json[0]) : 0.0;
      final lon = json.length > 1 ? _toDouble(json[1]) : 0.0;
      final speed = json.length > 2 ? _toDouble(json[2]) : 0.0;
      final rpm = json.length > 3 ? _toInt(json[3]) : 0;
      final fuelRate = json.length > 4 ? _toDouble(json[4]) : 0.0;
      final elapsed = json.length > 5 ? _toDouble(json[5]) : 0.0;
      return TripRoutePoint(
        latitude: lat,
        longitude: lon,
        speedKmh: speed,
        rpm: rpm,
        fuelRateLph: fuelRate,
        elapsedSeconds: elapsed,
      );
    }

    if (json is Map) {
      final map = json is Map<String, dynamic>
          ? json
          : Map<String, dynamic>.from(json);

      return TripRoutePoint(
        latitude: _toDouble(map['lat'] ?? map['latitude']),
        longitude: _toDouble(map['lon'] ?? map['longitude']),
        speedKmh: _toDouble(map['speedKmh'] ?? map['speed']),
        rpm: _toInt(map['rpm']),
        fuelRateLph: _toDouble(map['fuelRateLph'] ?? map['fuelRate']),
        fuelL100km: _toDouble(map['fuelL100km']),
        engineLoadPercent:
            _toDouble(map['engineLoad'] ?? map['engineLoadPercent']),
        coolantTempC: _toInt(map['coolantTemp'] ?? map['coolantTempC']),
        shortTermFuelTrim:
            _toDouble(map['stft'] ?? map['shortTermFuelTrim']),
        longTermFuelTrim:
            _toDouble(map['ltft'] ?? map['longTermFuelTrim']),
        elapsedSeconds:
            _toDouble(map['elapsedSec'] ?? map['elapsedSeconds']),
      );
    }

    throw ArgumentError('Invalid JSON format for TripRoutePoint: $json');
  }

  /// Calculates great-circle distance between two GPS coordinates in meters using the Haversine formula.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    if (lat1 == lat2 && lon1 == lon2) return 0.0;
    const earthRadiusMeters = 6371000.0;
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final rLat1 = lat1 * (math.pi / 180.0);
    final rLat2 = lat2 * (math.pi / 180.0);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  TripRoutePoint copyWith({
    double? latitude,
    double? longitude,
    double? speedKmh,
    int? rpm,
    double? fuelRateLph,
    double? fuelL100km,
    double? engineLoadPercent,
    int? coolantTempC,
    double? shortTermFuelTrim,
    double? longTermFuelTrim,
    double? elapsedSeconds,
  }) =>
      TripRoutePoint(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        speedKmh: speedKmh ?? this.speedKmh,
        rpm: rpm ?? this.rpm,
        fuelRateLph: fuelRateLph ?? this.fuelRateLph,
        fuelL100km: fuelL100km ?? this.fuelL100km,
        engineLoadPercent: engineLoadPercent ?? this.engineLoadPercent,
        coolantTempC: coolantTempC ?? this.coolantTempC,
        shortTermFuelTrim: shortTermFuelTrim ?? this.shortTermFuelTrim,
        longTermFuelTrim: longTermFuelTrim ?? this.longTermFuelTrim,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripRoutePoint &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-7 &&
          (longitude - other.longitude).abs() < 1e-7 &&
          (speedKmh - other.speedKmh).abs() < 1e-4 &&
          rpm == other.rpm &&
          (fuelRateLph - other.fuelRateLph).abs() < 1e-4 &&
          (fuelL100km - other.fuelL100km).abs() < 1e-4 &&
          (engineLoadPercent - other.engineLoadPercent).abs() < 1e-4 &&
          coolantTempC == other.coolantTempC &&
          (shortTermFuelTrim - other.shortTermFuelTrim).abs() < 1e-4 &&
          (longTermFuelTrim - other.longTermFuelTrim).abs() < 1e-4 &&
          (elapsedSeconds - other.elapsedSeconds).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        speedKmh,
        rpm,
        fuelRateLph,
        fuelL100km,
        engineLoadPercent,
        coolantTempC,
        shortTermFuelTrim,
        longTermFuelTrim,
        elapsedSeconds,
      );

  @override
  String toString() =>
      'TripRoutePoint(lat: $latitude, lon: $longitude, speed: $speedKmh, rpm: $rpm, fuelRate: $fuelRateLph, elapsed: $elapsedSeconds)';
}
