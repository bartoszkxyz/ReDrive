import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/trip_route_point.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/settings/app_preferences.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';
import 'package:obdrive/services/trip/trip_timeseries_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppPreferences.resetCacheForTesting();
    await AppPreferences.setAutoTripEnabled(true);
    tempDir = Directory.systemTemp.createTempSync('trip_gps_route_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('M3.2 GPS Route and Timeseries Recording Unit Tests', () {
    test(
      'TripProvider records GpsFix coordinates into Trip.routePoints and TripTimeseriesSample',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);
        final timeseriesService =
            TripTimeseriesService(customDirectory: tempDir);
        final provider = TripProvider(
          historyService: historyService,
          timeseriesService: timeseriesService,
        );
        await provider.initialized;
        await provider.setMinTripDistanceKm(0.0);

        final t0 = DateTime(2026, 6, 1, 10, 0, 0);
        provider.manualStartTrip(t0);

        // Record a continuous sequence of 15 samples with GpsFix spaced 1 per second
        for (int s = 0; s <= 15; s++) {
          final t = t0.add(Duration(seconds: s));
          final fix = GpsFix(
            latitude: 42.6977 + s * 0.0003,
            longitude: 23.3219 + s * 0.0003,
            altitudeMeters: 550.0 + s * 1.5,
            speedKmh: 45.0,
            timestamp: t,
          );
          provider.processDataPoint(
            const ObdData(speed: 45, rpm: 2000, engineFuelRate: 3.0),
            timestamp: t,
            gpsFix: fix,
          );
        }

        await provider.manualEndTrip(t0.add(const Duration(seconds: 15)));

        // Verify downsampled routePoints stored on completed Trip
        expect(provider.pastTrips, isNotEmpty);
        final savedTrip = provider.pastTrips.first;
        expect(savedTrip.routePoints.length, greaterThanOrEqualTo(2));
        expect(savedTrip.hasRoute, isTrue);

        // First point should match starting fix
        expect(savedTrip.routePoints.first.latitude, closeTo(42.6977, 0.0001));
        expect(savedTrip.routePoints.first.longitude, closeTo(23.3219, 0.0001));

        // Forced final point should match final fix
        expect(
          savedTrip.routePoints.last.latitude,
          closeTo(42.6977 + 15 * 0.0003, 0.0001),
        );
        expect(
          savedTrip.routePoints.last.longitude,
          closeTo(23.3219 + 15 * 0.0003, 0.0001),
        );

        // Verify 1 Hz samples recorded into TripTimeseriesService
        final samples = await timeseriesService.readSamples(savedTrip.id);
        expect(samples, isNotEmpty);
        expect(samples.first.latitude, closeTo(42.6977, 0.0001));
        expect(samples.first.longitude, closeTo(23.3219, 0.0001));
        expect(samples.first.altitudeMeters, closeTo(550.0, 0.1));
        expect(samples.first.gpsSpeedKmh, closeTo(45.0, 0.1));

        provider.dispose();
      },
    );

    test(
      'tags TripAnomalyEpisode with exact latitude, longitude, and elapsedSeconds during active GpsFix',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);
        final provider = TripProvider(historyService: historyService);
        await provider.initialized;
        await provider.setMinTripDistanceKm(0.0);

        final t0 = DateTime(2026, 6, 1, 11, 0, 0);
        provider.manualStartTrip(t0);

        // Baseline normal point at t0
        provider.processDataPoint(
          const ObdData(speed: 40, rpm: 2000, coolantTemp: 90),
          timestamp: t0,
          gpsFix: GpsFix(
            latitude: 42.6977,
            longitude: 23.3219,
            timestamp: t0,
          ),
        );

        // At t = 12s, overheat anomaly occurs (>105°C critical threshold)
        final tOverheat = t0.add(const Duration(seconds: 12));
        final overheatFix = GpsFix(
          latitude: 42.7015,
          longitude: 23.3260,
          timestamp: tOverheat,
        );
        provider.processDataPoint(
          const ObdData(speed: 40, rpm: 2000, coolantTemp: 112),
          timestamp: tOverheat,
          gpsFix: overheatFix,
        );

        // Also record a DTC at t = 20s
        final tDtc = t0.add(const Duration(seconds: 20));
        final dtcFix = GpsFix(
          latitude: 42.7050,
          longitude: 23.3300,
          timestamp: tDtc,
        );
        provider.recordDtcCodes(
          [
            const DtcCode(
              code: 'P0118',
              system: 'Powertrain',
              title: 'Engine Coolant Temp High',
              description: 'Coolant temperature sensor circuit high input',
            ),
          ],
          timestamp: tDtc,
          gpsFix: dtcFix,
        );

        final anomalies = provider.activeTrip.anomalies;
        expect(anomalies, isNotEmpty);

        // Thermal overheat episode verification
        final thermalEpisode = anomalies.firstWhere(
          (a) => a.category == AnomalyCategory.thermal,
        );
        expect(thermalEpisode.latitude, closeTo(42.7015, 0.0001));
        expect(thermalEpisode.longitude, closeTo(23.3260, 0.0001));
        expect(thermalEpisode.elapsedSeconds, closeTo(12.0, 0.5));

        // DTC fault episode verification
        final dtcEpisode = anomalies.firstWhere(
          (a) => a.category == AnomalyCategory.dtcFault,
        );
        expect(dtcEpisode.latitude, closeTo(42.7050, 0.0001));
        expect(dtcEpisode.longitude, closeTo(23.3300, 0.0001));
        expect(dtcEpisode.elapsedSeconds, closeTo(20.0, 0.5));

        provider.dispose();
      },
    );

    test(
      'active trip checkpoint saves routePoints and crash recovery restores routePoints on recovered Trip',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);
        final provider1 = TripProvider(historyService: historyService);
        await provider1.initialized;
        await provider1.setMinTripDistanceKm(0.0);

        final t0 = DateTime(2026, 6, 1, 12, 0, 0);
        provider1.manualStartTrip(t0);

        // Record initial point
        provider1.processDataPoint(
          const ObdData(speed: 50, rpm: 2200, engineFuelRate: 3.2),
          timestamp: t0,
          gpsFix: GpsFix(
            latitude: 42.6977,
            longitude: 23.3219,
            timestamp: t0,
          ),
        );

        // Advance 6 seconds and 100 meters to trigger downsampling threshold
        final t1 = t0.add(const Duration(seconds: 6));
        provider1.processDataPoint(
          const ObdData(speed: 50, rpm: 2200, engineFuelRate: 3.2),
          timestamp: t1,
          gpsFix: GpsFix(
            latitude: 42.6995,
            longitude: 23.3240,
            timestamp: t1,
          ),
        );

        expect(provider1.activeRoutePoints.length, greaterThanOrEqualTo(2));

        // Save active checkpoint
        await provider1.saveCheckpoint(t1);

        // Verify checkpoint file exists on disk
        final checkpointFile =
            File('${tempDir.path}/active_trip_checkpoint.json');
        expect(checkpointFile.existsSync(), isTrue);

        // Dispose provider1 simulating crash / application kill
        provider1.dispose();

        // Spin up fresh provider2 with the same storage
        final provider2 = TripProvider(historyService: historyService);
        await provider2.initialized;

        expect(provider2.pastTrips, isNotEmpty);
        final recoveredTrip = provider2.pastTrips.first;
        expect(recoveredTrip.routePoints.length, greaterThanOrEqualTo(2));
        expect(recoveredTrip.routePoints.first.latitude, closeTo(42.6977, 0.0001));
        expect(recoveredTrip.routePoints.last.latitude, closeTo(42.6995, 0.0001));
        expect(checkpointFile.existsSync(), isFalse);

        provider2.dispose();
      },
    );

    test(
      'in ObdMode.demo, updateFromObd automatically advances simulated GPS route in GpsLocationService',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);
        final tripProvider = TripProvider(historyService: historyService);
        await tripProvider.initialized;
        await tripProvider.setMinTripDistanceKm(0.0);

        final obdProvider = ObdProvider();
        await obdProvider.startDemoMode();
        expect(obdProvider.mode, ObdMode.demo);

        tripProvider.manualStartTrip();

        // Initially no fix injected
        expect(tripProvider.gpsService.lastFix, isNull);

        // Calling updateFromObd in demo mode advances simulated route
        tripProvider.updateFromObd(obdProvider);

        final fix1 = tripProvider.gpsService.lastFix;
        expect(fix1, isNotNull);
        final initialLat = fix1!.latitude;
        final initialLon = fix1.longitude;

        // Calling updateFromObd again advances simulated trajectory
        tripProvider.updateFromObd(obdProvider);

        final fix2 = tripProvider.gpsService.lastFix;
        expect(fix2, isNotNull);
        expect(
          fix2!.latitude != initialLat || fix2.longitude != initialLon,
          isTrue,
        );

        await obdProvider.stopDemoMode();
        tripProvider.dispose();
        obdProvider.dispose();
      },
    );
  });
}
