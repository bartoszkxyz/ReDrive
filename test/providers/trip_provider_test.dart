import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/settings/app_preferences.dart';
import 'package:redrive/services/trip/trip_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // AppPreferences caches its SharedPreferences instance; reset it so each
    // test starts from true defaults (not values written by earlier tests).
    AppPreferences.resetCacheForTesting();
    await AppPreferences.setAutoTripEnabled(true);
    tempDir = Directory.systemTemp.createTempSync(
      'redrive_trip_provider_test_',
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('TripProvider Min Trip Distance Threshold', () {
    test('defaults to 0.1 km', () async {
      final provider = TripProvider();
      await provider.initialized;
      expect(provider.minTripDistanceKm, 0.1);
      provider.dispose();
    });

    test('updates and persists user configured min trip distance', () async {
      final provider = TripProvider();
      await provider.initialized;

      await provider.setMinTripDistanceKm(15.0);
      expect(provider.minTripDistanceKm, 15.0);

      final saved = await AppPreferences.getMinTripDistanceKm();
      expect(saved, 15.0);

      provider.dispose();
    });
  });

  group('TripProvider Direct OBD Stream Binding', () {
    test(
      'bindToObd processes telemetry continuously from ObdProvider',
      () async {
        final tripProvider = TripProvider();
        final obdProvider = ObdProvider();

        tripProvider.bindToObd(obdProvider);

        expect(tripProvider.activeTrip.isActive, isFalse);

        await obdProvider.startDemoMode();
        await Future.delayed(const Duration(milliseconds: 300));

        expect(tripProvider.activeTrip.isActive, isTrue);
        expect(tripProvider.activeTrip.currentSpeed, greaterThan(0));

        await obdProvider.stopDemoMode();
        tripProvider.dispose();
        obdProvider.dispose();
      },
    );
  });

  group('TripProvider Symmetrical Integration and Persistence', () {
    test(
      'symmetrical trapezoidal fuel integration integrates linear ramp accurately',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);
        final provider = TripProvider(historyService: historyService);
        await provider.setMinTripDistanceKm(0.0);
        provider.manualStartTrip();

        final t0 = DateTime(2026, 6, 1, 12, 0, 0);

        // Ramp fuel from 2.0 L/h to 6.0 L/h over 10 seconds at 60 km/h
        // Theoretical fuel = integral_0^10 (2.0 + 0.4 t) dt / 3600 = 40.0 / 3600 = 0.0111111 L
        // Theoretical distance = 60 * 10 / 3600 = 0.1666667 km
        provider.processDataPoint(
          const ObdData(speed: 60, rpm: 2000, engineFuelRate: 2.0),
          timestamp: t0,
        );

        for (int i = 1; i <= 10; i++) {
          final t = t0.add(Duration(seconds: i));
          final fuel = 2.0 + 0.4 * i;
          provider.processDataPoint(
            ObdData(speed: 60, rpm: 2000, engineFuelRate: fuel),
            timestamp: t,
          );
        }

        final active = provider.activeTrip;
        const expectedFuel = 40.0 / 3600.0;
        const expectedDist = 60.0 * 10.0 / 3600.0;

        expect(active.distanceKm, closeTo(expectedDist, 0.0001));
        expect(active.fuelConsumedLiters, closeTo(expectedFuel, 0.00001));

        provider.dispose();
      },
    );

    test('recovers in-flight active trip from checkpoint upon restart', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final provider1 = TripProvider(historyService: historyService);
      await provider1.initialized;
      await provider1.setMinTripDistanceKm(0.0);

      final t0 = DateTime(2026, 6, 1, 12, 0, 0);
      provider1.manualStartTrip(t0);

      // Drive 500 meters (36 seconds at 50 km/h)
      provider1.processDataPoint(
        const ObdData(speed: 50, rpm: 1800, engineFuelRate: 3.5),
        timestamp: t0,
      );
      for (int s = 1; s <= 36; s++) {
        provider1.processDataPoint(
          const ObdData(speed: 50, rpm: 1800, engineFuelRate: 3.5),
          timestamp: t0.add(Duration(seconds: s)),
        );
      }

      expect(provider1.activeTrip.distanceKm, closeTo(0.5, 0.01));

      // Save checkpoint and terminate provider (simulating crash / process death)
      await provider1.saveCheckpoint();
      provider1.dispose();

      // Checkpoint file should have been written
      final checkpointFile = File(
        '${tempDir.path}/active_trip_checkpoint.json',
      );
      expect(checkpointFile.existsSync(), isTrue);

      // Start fresh provider instance
      final provider2 = TripProvider(historyService: historyService);
      await provider2.initialized;

      final pastTrips = provider2.pastTrips;
      expect(pastTrips, isNotEmpty);
      expect(pastTrips.first.distanceKm, closeTo(0.5, 0.01));
      // Checkpoint cleared after recovery
      expect(checkpointFile.existsSync(), isFalse);

      provider2.dispose();
    });

    test(
      'initialized future resolves after startup completes deterministically',
      () async {
        // Real default: no override set (clear any late writes from prior tests).
        await (await SharedPreferences.getInstance()).remove(
          'min_trip_distance_km',
        );
        final provider = TripProvider();
        await expectLater(provider.initialized, completes);
        expect(provider.minTripDistanceKm, 0.1);
        provider.dispose();
      },
    );

    test(
      'applies STFT + LTFT fuel trim correction and persists anomalies & 2-trip rolling timeseries',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);
        final provider = TripProvider(historyService: historyService);
        await provider.initialized;
        await provider.setMinTripDistanceKm(0.0);

        final t0 = DateTime(2026, 10, 17, 10, 0, 0);
        provider.manualStartTrip(t0);

        // Process high-RPM power loss with +15% STFT and +5% LTFT (+20% trim multiplier)
        for (int s = 0; s <= 10; s++) {
          provider.processDataPoint(
            const ObdData(
              speed: 80,
              rpm: 3600,
              relativeThrottle: 65.0,
              engineLoad: 32.0,
              maf: 10.0,
              shortTermFuelTrim: 15.0,
              longTermFuelTrim: 5.0,
            ),
            timestamp: t0.add(Duration(seconds: s)),
          );
        }

        expect(provider.activeTrip.problemCount, greaterThanOrEqualTo(2));
        await provider.manualEndTrip(t0.add(const Duration(seconds: 10)));

        expect(provider.pastTrips, hasLength(1));
        final savedTrip = provider.pastTrips.first;
        expect(savedTrip.hasTimeseries, isTrue);
        expect(savedTrip.problemCount, greaterThanOrEqualTo(2));
        expect(savedTrip.anomalies, isNotEmpty);

        provider.dispose();
      },
    );
  });
}
