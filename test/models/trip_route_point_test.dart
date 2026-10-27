import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/trip_route_point.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/services/trip/route_downsampler.dart';
import 'package:obdrive/services/trip/trip_timeseries_service.dart';

void main() {
  group('GpsFix Model', () {
    test('instantiates with required and optional fields', () {
      final now = DateTime(2026, 10, 18, 12, 0, 0);
      final fix = GpsFix(
        latitude: 42.123456,
        longitude: 24.654321,
        altitudeMeters: 185.5,
        speedKmh: 65.2,
        timestamp: now,
      );

      expect(fix.latitude, equals(42.123456));
      expect(fix.longitude, equals(24.654321));
      expect(fix.altitudeMeters, equals(185.5));
      expect(fix.speedKmh, equals(65.2));
      expect(fix.timestamp, equals(now));
    });

    test('toJson and fromJson serialize and deserialize accurately', () {
      final now = DateTime(2026, 10, 18, 12, 0, 0);
      final fix = GpsFix(
        latitude: 42.123456,
        longitude: 24.654321,
        altitudeMeters: 185.5,
        speedKmh: 65.2,
        timestamp: now,
      );

      final json = fix.toJson();
      expect(json['latitude'], equals(42.123456));
      expect(json['longitude'], equals(24.654321));
      expect(json['altitudeMeters'], equals(185.5));
      expect(json['speedKmh'], equals(65.2));
      expect(json['timestamp'], equals(now.toIso8601String()));

      final restored = GpsFix.fromJson(json);
      expect(restored, equals(fix));
    });

    test('fromJson handles null optional fields and alternate keys', () {
      final json = {
        'lat': 42.0,
        'lon': 24.0,
        'alt': 120.0,
        'speed': 45.0,
        'timestamp': '2026-10-18T12:00:00.000Z',
      };

      final fix = GpsFix.fromJson(json);
      expect(fix.latitude, equals(42.0));
      expect(fix.longitude, equals(24.0));
      expect(fix.altitudeMeters, equals(120.0));
      expect(fix.speedKmh, equals(45.0));

      final minimalJson = {
        'latitude': 42.0,
        'longitude': 24.0,
        'timestamp': '2026-10-18T12:00:00.000Z',
      };
      final minimalFix = GpsFix.fromJson(minimalJson);
      expect(minimalFix.altitudeMeters, isNull);
      expect(minimalFix.speedKmh, isNull);
      final minimalOutput = minimalFix.toJson();
      expect(minimalOutput.containsKey('altitudeMeters'), isFalse);
      expect(minimalOutput.containsKey('speedKmh'), isFalse);
    });

    test('copyWith updates fields correctly', () {
      final now = DateTime(2026, 10, 18, 12, 0, 0);
      final fix = GpsFix(
        latitude: 42.0,
        longitude: 24.0,
        timestamp: now,
      );

      final updated = fix.copyWith(
        latitude: 43.0,
        speedKmh: 80.0,
      );

      expect(updated.latitude, equals(43.0));
      expect(updated.longitude, equals(24.0));
      expect(updated.speedKmh, equals(80.0));
    });

    test('equality and hashCode contract', () {
      final now = DateTime(2026, 10, 18, 12, 0, 0);
      final fix1 = GpsFix(latitude: 42.0, longitude: 24.0, timestamp: now);
      final fix2 = GpsFix(latitude: 42.0, longitude: 24.0, timestamp: now);
      final fix3 = GpsFix(latitude: 43.0, longitude: 24.0, timestamp: now);

      expect(fix1, equals(fix2));
      expect(fix1.hashCode, equals(fix2.hashCode));
      expect(fix1, isNot(equals(fix3)));
    });
  });

  group('TripRoutePoint Model', () {
    test('instantiates with defaults', () {
      const point = TripRoutePoint(
        latitude: 42.5,
        longitude: 24.5,
      );

      expect(point.latitude, equals(42.5));
      expect(point.longitude, equals(24.5));
      expect(point.speedKmh, equals(0.0));
      expect(point.rpm, equals(0));
      expect(point.fuelRateLph, equals(0.0));
      expect(point.fuelL100km, equals(0.0));
      expect(point.engineLoadPercent, equals(0.0));
      expect(point.coolantTempC, equals(0));
      expect(point.shortTermFuelTrim, equals(0.0));
      expect(point.longTermFuelTrim, equals(0.0));
      expect(point.elapsedSeconds, equals(0.0));
    });

    test('toJson serializes exact short keys', () {
      const point = TripRoutePoint(
        latitude: 42.6977,
        longitude: 23.3219,
        speedKmh: 72.5,
        rpm: 2450,
        fuelRateLph: 5.6,
        fuelL100km: 7.7,
        engineLoadPercent: 48.0,
        coolantTempC: 88,
        shortTermFuelTrim: 1.5,
        longTermFuelTrim: -0.8,
        elapsedSeconds: 125.0,
      );

      final json = point.toJson();
      expect(json, equals({
        'lat': 42.6977,
        'lon': 23.3219,
        'speedKmh': 72.5,
        'rpm': 2450,
        'fuelRateLph': 5.6,
        'fuelL100km': 7.7,
        'engineLoad': 48.0,
        'coolantTemp': 88,
        'stft': 1.5,
        'ltft': -0.8,
        'elapsedSec': 125.0,
      }));
    });

    test('fromJson deserializes from standard map and alternate keys', () {
      final json = {
        'latitude': 42.6977,
        'longitude': 23.3219,
        'speed': 72.5,
        'rpm': 2450,
        'fuelRate': 5.6,
        'fuelL100km': 7.7,
        'engineLoadPercent': 48.0,
        'coolantTempC': 88,
        'shortTermFuelTrim': 1.5,
        'longTermFuelTrim': -0.8,
        'elapsedSeconds': 125.0,
      };

      final point = TripRoutePoint.fromJson(json);
      expect(point.latitude, equals(42.6977));
      expect(point.longitude, equals(23.3219));
      expect(point.speedKmh, equals(72.5));
      expect(point.rpm, equals(2450));
      expect(point.fuelRateLph, equals(5.6));
      expect(point.fuelL100km, equals(7.7));
      expect(point.engineLoadPercent, equals(48.0));
      expect(point.coolantTempC, equals(88));
      expect(point.shortTermFuelTrim, equals(1.5));
      expect(point.longTermFuelTrim, equals(-0.8));
      expect(point.elapsedSeconds, equals(125.0));
    });

    test('fromJson deserializes from compact 6-element list', () {
      final list = [42.6977, 23.3219, 72.5, 2450, 5.6, 125.0];
      final point = TripRoutePoint.fromJson(list);

      expect(point.latitude, equals(42.6977));
      expect(point.longitude, equals(23.3219));
      expect(point.speedKmh, equals(72.5));
      expect(point.rpm, equals(2450));
      expect(point.fuelRateLph, equals(5.6));
      expect(point.elapsedSeconds, equals(125.0));
      expect(point.fuelL100km, equals(0.0));
      expect(point.engineLoadPercent, equals(0.0));
    });

    test('copyWith produces modified copy', () {
      const original = TripRoutePoint(latitude: 42.0, longitude: 24.0);
      final modified = original.copyWith(
        speedKmh: 90.0,
        coolantTempC: 92,
      );

      expect(modified.latitude, equals(42.0));
      expect(modified.longitude, equals(24.0));
      expect(modified.speedKmh, equals(90.0));
      expect(modified.coolantTempC, equals(92));
    });

    test('equality and hashCode contract', () {
      const p1 = TripRoutePoint(latitude: 42.0, longitude: 24.0, rpm: 2000);
      const p2 = TripRoutePoint(latitude: 42.0, longitude: 24.0, rpm: 2000);
      const p3 = TripRoutePoint(latitude: 42.0, longitude: 24.0, rpm: 2500);

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
    });

    test('distanceMeters accurately computes Haversine distance', () {
      // Identical coordinates
      expect(TripRoutePoint.distanceMeters(42.0, 24.0, 42.0, 24.0), equals(0.0));

      // Known distance between London (51.5074, -0.1278) and Paris (48.8566, 2.3522) ~ 343.5 km
      final distMeters = TripRoutePoint.distanceMeters(
        51.5074,
        -0.1278,
        48.8566,
        2.3522,
      );
      expect(distMeters, closeTo(343550, 2000));

      // Short distance (~111 meters for 0.001 deg latitude change)
      final shortDist = TripRoutePoint.distanceMeters(42.0, 24.0, 42.001, 24.0);
      expect(shortDist, closeTo(111.2, 2.0));
    });
  });

  group('RouteDownsampler', () {
    test('default threshold configuration', () {
      final downsampler = RouteDownsampler();
      expect(downsampler.minIntervalSeconds, equals(5.0));
      expect(downsampler.minDistanceMeters, equals(25.0));
      expect(downsampler.maxPoints, equals(1500));
      expect(downsampler.points, isEmpty);
    });

    test('records first point unconditionally', () {
      final downsampler = RouteDownsampler();
      const p1 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 0.5);

      final added = downsampler.recordPoint(p1);
      expect(added, isTrue);
      expect(downsampler.points.length, equals(1));
      expect(downsampler.points.first, equals(p1));
    });

    test('ignores candidate below interval and distance thresholds', () {
      final downsampler = RouteDownsampler(
        minIntervalSeconds: 5.0,
        minDistanceMeters: 25.0,
      );
      const p1 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 0.0);
      downsampler.recordPoint(p1);

      // Candidate at +2s and 5m distance
      const p2 = TripRoutePoint(latitude: 42.00004, longitude: 24.0, elapsedSeconds: 2.0);
      final added = downsampler.recordPoint(p2);

      expect(added, isFalse);
      expect(downsampler.points.length, equals(1));
    });

    test('records candidate when elapsedSeconds exceeds minIntervalSeconds', () {
      final downsampler = RouteDownsampler(
        minIntervalSeconds: 5.0,
        minDistanceMeters: 25.0,
      );
      const p1 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 0.0);
      downsampler.recordPoint(p1);

      // Candidate at +5.1s (even at same location)
      const p2 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 5.1);
      final added = downsampler.recordPoint(p2);

      expect(added, isTrue);
      expect(downsampler.points.length, equals(2));
      expect(downsampler.points.last, equals(p2));
    });

    test('records candidate when distance exceeds minDistanceMeters even if under minIntervalSeconds', () {
      final downsampler = RouteDownsampler(
        minIntervalSeconds: 5.0,
        minDistanceMeters: 25.0,
      );
      const p1 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 0.0);
      downsampler.recordPoint(p1);

      // Candidate at +1.0s but 50m away
      const p2 = TripRoutePoint(latitude: 42.0005, longitude: 24.0, elapsedSeconds: 1.0);
      final added = downsampler.recordPoint(p2);

      expect(added, isTrue);
      expect(downsampler.points.length, equals(2));
      expect(downsampler.points.last, equals(p2));
    });

    test('force: true forces recording regardless of thresholds', () {
      final downsampler = RouteDownsampler(
        minIntervalSeconds: 5.0,
        minDistanceMeters: 25.0,
      );
      const p1 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 0.0);
      downsampler.recordPoint(p1);

      const p2 = TripRoutePoint(latitude: 42.0, longitude: 24.0, elapsedSeconds: 0.5);
      final added = downsampler.recordPoint(p2, force: true);

      expect(added, isTrue);
      expect(downsampler.points.length, equals(2));
      expect(downsampler.points.last, equals(p2));
    });

    test('reset clears accumulated points', () {
      final downsampler = RouteDownsampler();
      downsampler.recordPoint(const TripRoutePoint(latitude: 42.0, longitude: 24.0));
      expect(downsampler.points.length, equals(1));

      downsampler.reset();
      expect(downsampler.points, isEmpty);
    });

    test('loadCheckpointPoints loads points and decimates if exceeding maxPoints', () {
      final downsampler = RouteDownsampler(maxPoints: 4);
      final saved = List.generate(
        8,
        (i) => TripRoutePoint(
          latitude: 42.0 + (i * 0.01),
          longitude: 24.0,
          elapsedSeconds: i * 5.0,
        ),
      );

      downsampler.loadCheckpointPoints(saved);
      expect(downsampler.points.length, equals(4));
      expect(downsampler.points.first.latitude, equals(42.0));
      expect(downsampler.points.last.latitude, equals(42.07));
    });

    test('decimates intermediate points while preserving first and last when maxPoints is exceeded', () {
      final downsampler = RouteDownsampler(
        minIntervalSeconds: 1.0,
        minDistanceMeters: 1.0,
        maxPoints: 5,
      );

      for (var i = 0; i < 10; i++) {
        downsampler.recordPoint(
          TripRoutePoint(
            latitude: 42.0 + (i * 0.01),
            longitude: 24.0,
            elapsedSeconds: i * 2.0,
          ),
        );
      }

      expect(downsampler.points.length, equals(5));
      expect(downsampler.points.first.elapsedSeconds, equals(0.0));
      expect(downsampler.points.last.elapsedSeconds, equals(18.0));
    });

    test('static downsample batch helper preserves first, last, and enforces thresholds & maxPoints', () {
      final raw = List.generate(
        20,
        (i) => TripRoutePoint(
          latitude: 42.0 + (i * 0.001),
          longitude: 24.0,
          elapsedSeconds: i * 1.0, // 1s intervals
        ),
      );

      // minInterval = 5s, so candidates at 0, 5, 10, 15, and last point (19) forced
      final downsampled = RouteDownsampler.downsample(
        raw,
        minIntervalSeconds: 5.0,
        minDistanceMeters: 500.0, // Large so time threshold drives it
        maxPoints: 10,
      );

      expect(downsampled.first.elapsedSeconds, equals(0.0));
      expect(downsampled.last.elapsedSeconds, equals(19.0));
      expect(downsampled.length, lessThanOrEqualTo(10));

      // Batch with maxPoints decimation
      final heavilyDecimated = RouteDownsampler.downsample(
        raw,
        minIntervalSeconds: 1.0,
        minDistanceMeters: 1.0,
        maxPoints: 4,
      );
      expect(heavilyDecimated.length, equals(4));
      expect(heavilyDecimated.first.elapsedSeconds, equals(0.0));
      expect(heavilyDecimated.last.elapsedSeconds, equals(19.0));

      // Edge cases: empty and single-element lists
      expect(RouteDownsampler.downsample([]), isEmpty);
      final single = [const TripRoutePoint(latitude: 42.0, longitude: 24.0)];
      expect(RouteDownsampler.downsample(single), equals(single));
    });
  });

  group('Trip Model GPS Extensions', () {
    test('default routePoints is empty and hasRoute is false', () {
      final trip = Trip(
        id: 'trip_noroute',
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        duration: const Duration(minutes: 5),
        distanceKm: 2.0,
        fuelConsumedLiters: 0.2,
        avgFuelConsumption: 8.0,
        avgSpeed: 40.0,
        maxSpeed: 60.0,
        maxRpm: 2500,
        avgRpm: 1800,
      );

      expect(trip.routePoints, isEmpty);
      expect(trip.hasRoute, isFalse);
    });

    test('hasRoute is true only when routePoints length >= 2', () {
      final trip1 = Trip(
        id: 'trip_1pt',
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        duration: const Duration(minutes: 5),
        distanceKm: 2.0,
        fuelConsumedLiters: 0.2,
        avgFuelConsumption: 8.0,
        avgSpeed: 40.0,
        maxSpeed: 60.0,
        maxRpm: 2500,
        avgRpm: 1800,
        routePoints: const [TripRoutePoint(latitude: 42.0, longitude: 24.0)],
      );
      expect(trip1.hasRoute, isFalse);

      final trip2 = trip1.copyWith(
        routePoints: const [
          TripRoutePoint(latitude: 42.0, longitude: 24.0),
          TripRoutePoint(latitude: 42.01, longitude: 24.01),
        ],
      );
      expect(trip2.hasRoute, isTrue);
    });

    test('Trip.toJson and fromJson correctly serialize and deserialize routePoints', () {
      final now = DateTime(2026, 10, 18, 14, 0, 0);
      final trip = Trip(
        id: 'trip_route_test',
        startTime: now,
        endTime: now.add(const Duration(minutes: 10)),
        duration: const Duration(minutes: 10),
        distanceKm: 8.5,
        fuelConsumedLiters: 0.7,
        avgFuelConsumption: 7.5,
        avgSpeed: 51.0,
        maxSpeed: 78.0,
        maxRpm: 3100,
        avgRpm: 2000,
        routePoints: const [
          TripRoutePoint(
            latitude: 42.6977,
            longitude: 23.3219,
            speedKmh: 45.0,
            rpm: 2100,
            fuelRateLph: 4.2,
            elapsedSeconds: 0.0,
          ),
          TripRoutePoint(
            latitude: 42.7000,
            longitude: 23.3300,
            speedKmh: 55.0,
            rpm: 2400,
            fuelRateLph: 5.1,
            elapsedSeconds: 60.0,
          ),
        ],
      );

      final json = trip.toJson();
      expect(json['routePoints'], isA<List>());
      expect((json['routePoints'] as List).length, equals(2));

      final restored = Trip.fromJson(json);
      expect(restored.hasRoute, isTrue);
      expect(restored.routePoints.length, equals(2));
      expect(restored.routePoints[0].latitude, equals(42.6977));
      expect(restored.routePoints[1].elapsedSeconds, equals(60.0));
    });

    test('Trip.fromJson gracefully handles absent or null routePoints', () {
      final json = {
        'id': 'legacy_trip',
        'startTime': '2026-10-18T10:00:00.000Z',
        'endTime': '2026-10-18T10:15:00.000Z',
        'durationSeconds': 900,
        'distanceKm': 10.0,
        'fuelConsumedLiters': 0.8,
        'avgFuelConsumption': 8.0,
        'avgSpeed': 40.0,
        'maxSpeed': 65.0,
        'maxRpm': 2800,
        'avgRpm': 1900,
      };

      final trip = Trip.fromJson(json);
      expect(trip.routePoints, isEmpty);
      expect(trip.hasRoute, isFalse);
    });
  });

  group('TripAnomalyEpisode GPS Extensions', () {
    test('instantiates with optional GPS fields and copyWith updates them', () {
      final now = DateTime(2026, 10, 18, 15, 0, 0);
      final episode = TripAnomalyEpisode(
        id: 'anomaly_gps_1',
        severity: AnomalySeverity.problem,
        category: AnomalyCategory.powerLoss,
        title: 'High RPM Power Loss',
        description: 'Engine load dropped on uphill climb',
        startTime: now,
        endTime: now.add(const Duration(seconds: 8)),
        latitude: 42.6955,
        longitude: 23.3180,
        elapsedSeconds: 142.5,
      );

      expect(episode.latitude, equals(42.6955));
      expect(episode.longitude, equals(23.3180));
      expect(episode.elapsedSeconds, equals(142.5));

      final copied = episode.copyWith(
        latitude: 42.7000,
        elapsedSeconds: 150.0,
      );
      expect(copied.latitude, equals(42.7000));
      expect(copied.longitude, equals(23.3180));
      expect(copied.elapsedSeconds, equals(150.0));
    });

    test('toJson and fromJson serialize and deserialize GPS fields', () {
      final now = DateTime(2026, 10, 18, 15, 0, 0);
      final episode = TripAnomalyEpisode(
        id: 'anomaly_gps_2',
        severity: AnomalySeverity.suspicion,
        category: AnomalyCategory.fuelTrim,
        title: 'Lean Trim',
        description: 'STFT spiked positive',
        startTime: now,
        endTime: now.add(const Duration(seconds: 4)),
        latitude: 42.6955,
        longitude: 23.3180,
        elapsedSeconds: 88.0,
      );

      final json = episode.toJson();
      expect(json['latitude'], equals(42.6955));
      expect(json['longitude'], equals(23.3180));
      expect(json['elapsedSeconds'], equals(88.0));

      final restored = TripAnomalyEpisode.fromJson(json);
      expect(restored.latitude, equals(42.6955));
      expect(restored.longitude, equals(23.3180));
      expect(restored.elapsedSeconds, equals(88.0));
      expect(restored, equals(episode));
    });

    test('omits null GPS fields in toJson and gracefully defaults to null in fromJson', () {
      final now = DateTime(2026, 10, 18, 15, 0, 0);
      final episode = TripAnomalyEpisode(
        id: 'anomaly_no_gps',
        severity: AnomalySeverity.suspicion,
        category: AnomalyCategory.thermal,
        title: 'Warm Idle',
        description: 'Coolant reached 102 C',
        startTime: now,
        endTime: now.add(const Duration(seconds: 10)),
      );

      final json = episode.toJson();
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('longitude'), isFalse);
      expect(json.containsKey('elapsedSeconds'), isFalse);

      final restored = TripAnomalyEpisode.fromJson(json);
      expect(restored.latitude, isNull);
      expect(restored.longitude, isNull);
      expect(restored.elapsedSeconds, isNull);
    });

    test('equality and hashCode include GPS fields', () {
      final now = DateTime(2026, 10, 18, 15, 0, 0);
      final ep1 = TripAnomalyEpisode(
        id: 'ep1',
        severity: AnomalySeverity.problem,
        category: AnomalyCategory.powerLoss,
        title: 'P1',
        description: 'D1',
        startTime: now,
        endTime: now.add(const Duration(seconds: 5)),
        latitude: 42.0,
        longitude: 24.0,
        elapsedSeconds: 10.0,
      );
      final ep2 = TripAnomalyEpisode(
        id: 'ep1',
        severity: AnomalySeverity.problem,
        category: AnomalyCategory.powerLoss,
        title: 'P1',
        description: 'D1',
        startTime: now,
        endTime: now.add(const Duration(seconds: 5)),
        latitude: 42.0,
        longitude: 24.0,
        elapsedSeconds: 10.0,
      );
      final ep3 = ep1.copyWith(latitude: 42.5);

      expect(ep1, equals(ep2));
      expect(ep1.hashCode, equals(ep2.hashCode));
      expect(ep1, isNot(equals(ep3)));
    });
  });

  group('TripTimeseriesSample GPS Extensions', () {
    test('instantiates with GPS fields and serializes to/from JSON', () {
      final now = DateTime(2026, 10, 18, 16, 0, 0);
      final sample = TripTimeseriesSample(
        timestamp: now,
        elapsedSeconds: 32.5,
        data: const ObdData(rpm: 2500, speed: 60),
        latitude: 42.1234,
        longitude: 24.5678,
        altitudeMeters: 210.0,
        gpsSpeedKmh: 59.8,
      );

      expect(sample.latitude, equals(42.1234));
      expect(sample.longitude, equals(24.5678));
      expect(sample.altitudeMeters, equals(210.0));
      expect(sample.gpsSpeedKmh, equals(59.8));

      final json = sample.toJson();
      expect(json['latitude'], equals(42.1234));
      expect(json['longitude'], equals(24.5678));
      expect(json['altitudeMeters'], equals(210.0));
      expect(json['gpsSpeedKmh'], equals(59.8));

      final restored = TripTimeseriesSample.fromJson(json);
      expect(restored.latitude, equals(42.1234));
      expect(restored.longitude, equals(24.5678));
      expect(restored.altitudeMeters, equals(210.0));
      expect(restored.gpsSpeedKmh, equals(59.8));
      expect(restored, equals(sample));
      expect(restored.hashCode, equals(sample.hashCode));
    });

    test('omits null GPS fields in toJson and handles absent keys in fromJson', () {
      final now = DateTime(2026, 10, 18, 16, 0, 0);
      final sample = TripTimeseriesSample(
        timestamp: now,
        elapsedSeconds: 10.0,
        data: const ObdData(rpm: 1800, speed: 40),
      );

      final json = sample.toJson();
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('longitude'), isFalse);
      expect(json.containsKey('altitudeMeters'), isFalse);
      expect(json.containsKey('gpsSpeedKmh'), isFalse);

      final restored = TripTimeseriesSample.fromJson(json);
      expect(restored.latitude, isNull);
      expect(restored.longitude, isNull);
      expect(restored.altitudeMeters, isNull);
      expect(restored.gpsSpeedKmh, isNull);
    });

    test('TripTimeseriesService.recordSample records GPS fields into buffered sample', () {
      final service = TripTimeseriesService();
      final startTime = DateTime(2026, 10, 18, 16, 30, 0);
      service.startRecording('trip_service_gps', startTime);

      service.recordSample(
        const ObdData(rpm: 2200, speed: 50),
        timestamp: startTime.add(const Duration(seconds: 2)),
        latitude: 42.6977,
        longitude: 23.3219,
        altitudeMeters: 550.0,
        gpsSpeedKmh: 50.2,
      );

      expect(service.bufferedSampleCount, equals(1));
    });
  });
}
