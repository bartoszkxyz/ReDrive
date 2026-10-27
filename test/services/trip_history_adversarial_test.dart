import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('obdrive_adversarial_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Trip createTestTrip({
    required String id,
    DateTime? startTime,
    double distanceKm = 10.0,
    double fuelConsumed = 0.8,
  }) {
    final start = startTime ?? DateTime(2026, 6, 1, 10, 0);
    return Trip(
      id: id,
      startTime: start,
      endTime: start.add(const Duration(minutes: 15)),
      duration: const Duration(minutes: 15),
      distanceKm: distanceKm,
      fuelConsumedLiters: fuelConsumed,
      avgFuelConsumption: (fuelConsumed / distanceKm) * 100.0,
      avgSpeed: 40.0,
      maxSpeed: 60.0,
      maxRpm: 2500,
      avgRpm: 1800,
    );
  }

  group('Adversarial Test Suite 1: Non-UTF8 Raw Byte Corruption Analysis', () {
    test('ADV-1.1: Non-UTF8 bytes in primary history triggers .corrupt backup and .bak recovery', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final trip = createTestTrip(id: 'valuable_historical_trip');
      await service.saveTrip(trip);

      final primaryFile = File('${tempDir.path}/trips_history.json');
      expect(primaryFile.existsSync(), isTrue);
      final bakFile = File('${tempDir.path}/trips_history.json.bak');
      expect(bakFile.existsSync(), isTrue);

      // Overwrite primary file with invalid raw non-UTF-8 bytes (e.g. corrupted flash sector)
      await primaryFile.writeAsBytes([0xFF, 0xFE, 0x80, 0xBF, 0xC0, 0x00]);

      // Call loadTrips
      final loaded = await service.loadTrips();

      // Check whether .corrupt_<timestamp> was created
      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();

      expect(loaded, hasLength(1), reason: 'Must recover valid history from .bak mirror');
      expect(loaded.first.id, 'valuable_historical_trip');
      expect(corruptFiles, isNotEmpty, reason: 'Must create .corrupt_<timestamp> for non-UTF8 bytes');
    });

    test('ADV-1.2: Subsequent saveTrip after non-UTF8 corruption preserves .bak mirror history', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final initialTrip = createTestTrip(id: 'original_safeguarded_trip');
      await service.saveTrip(initialTrip);

      final primaryFile = File('${tempDir.path}/trips_history.json');
      final bakFile = File('${tempDir.path}/trips_history.json.bak');

      // Inject non-UTF8 corruption into primary only
      await primaryFile.writeAsBytes([0xFF, 0xFE, 0x80]);

      // Verify .bak currently has the original trip
      final bakBefore = jsonDecode(bakFile.readAsStringSync()) as List;
      expect(bakBefore, hasLength(1));
      expect(bakBefore.first['id'], 'original_safeguarded_trip');

      // Now user completes and saves a new trip
      final newTrip = createTestTrip(id: 'new_trip_after_crash');
      await service.saveTrip(newTrip);

      // Check what is in .bak now
      final bakAfter = jsonDecode(bakFile.readAsStringSync()) as List;

      expect(bakAfter, hasLength(2), reason: 'Must preserve original trip alongside new trip in .bak mirror');
      final ids = bakAfter.map((t) => t['id']).toList();
      expect(ids, containsAll(['new_trip_after_crash', 'original_safeguarded_trip']));
    });

    test('ADV-1.3: Empty .bak mirror ([]) when primary contains non-UTF8 raw bytes resets primary file to [] without loop', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');
      final bakFile = File('${tempDir.path}/trips_history.json.bak');

      // Mirror exists and contains valid empty JSON array []
      await bakFile.writeAsString('[]');
      // Primary contains corrupt non-UTF8 bytes
      await primaryFile.writeAsBytes([0xFF, 0xFE, 0x80, 0xBF, 0xC0, 0x00]);

      // First load: triggers corruption handling, backs up corrupt bytes, resets primary to []
      final trips1 = await service.loadTrips();
      expect(trips1, isEmpty);

      // Verify primary file is now valid empty JSON array
      expect(primaryFile.existsSync(), isTrue);
      final primaryContent = await primaryFile.readAsString();
      expect(jsonDecode(primaryContent), isEmpty);

      // Verify exactly 1 .corrupt_ file was created
      final corruptFiles1 = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles1, hasLength(1));

      // Second load: reads clean [] from primary, no duplicate .corrupt_ file created
      final trips2 = await service.loadTrips();
      expect(trips2, isEmpty);

      final corruptFiles2 = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles2, hasLength(1), reason: 'Must not spawn duplicate .corrupt_ files on subsequent boots');
    });

    test('ADV-1.4: Corrupted JSON when all recovery mechanisms fail safely resets primary file to []', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      // Unrecoverable corrupted JSON with no .bak mirror
      await primaryFile.writeAsString('{"completely_broken": true, [unclosed');

      final trips1 = await service.loadTrips();
      expect(trips1, isEmpty);

      // Verify primary file has been reset to valid []
      final content = await primaryFile.readAsString();
      expect(jsonDecode(content), isEmpty);

      // Verify exactly 1 corrupt backup was created and no duplicate on second load
      final corruptFiles1 = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles1, hasLength(1));

      await service.loadTrips();
      final corruptFiles2 = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles2, hasLength(1));
    });
  });

  group('Adversarial Test Suite 2: Structural JSON Corruptions & Partial Salvage', () {
    test('ADV-2.1: Partially written JSON with intact leading trip salvages intact trip and backs up corrupt file', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      final t1 = createTestTrip(id: 'intact_trip_1', distanceKm: 12.0);
      final t1Json = jsonEncode(t1.toJson());

      // Severed JSON: intact first trip, broken second trip, no closing array bracket
      final severed = '[$t1Json, {"id": "broken_trip", "distanceKm": 5.4, "fuel';
      await primaryFile.writeAsString(severed);

      final loaded = await service.loadTrips();

      // Check if corrupt file was backed up
      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles, isNotEmpty, reason: '.corrupt_<timestamp> backup must be created');

      // The intact trip should be salvaged by _salvageTripsFromDamagedContent
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'intact_trip_1');
    });

    test('ADV-2.2: Missing comma between valid JSON objects salvages all intact trips', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      final t1 = createTestTrip(id: 'trip_alpha');
      final t2 = createTestTrip(id: 'trip_beta');
      final t1Json = jsonEncode(t1.toJson());
      final t2Json = jsonEncode(t2.toJson());

      // Malformed array: missing comma between objects
      final malformed = '[$t1Json $t2Json]';
      await primaryFile.writeAsString(malformed);

      final loaded = await service.loadTrips();

      expect(loaded, hasLength(2));
      final ids = loaded.map((t) => t.id).toSet();
      expect(ids, containsAll(['trip_alpha', 'trip_beta']));
    });

    test('ADV-2.3: Truncated opening bracket and noise surrounds valid trip object', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      final t1 = createTestTrip(id: 'survivor_trip');
      final t1Json = jsonEncode(t1.toJson());

      // Garbage prefix, intact object, garbage suffix
      final payload = '### CORRUPT HEADER ### $t1Json &&& TRAILING NOISE &&&';
      await primaryFile.writeAsString(payload);

      final loaded = await service.loadTrips();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'survivor_trip');
    });

    test('ADV-2.4: Empty, whitespace-only, and single-brace files return empty list safely', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      // Empty string
      await primaryFile.writeAsString('');
      expect(await service.loadTrips(), isEmpty);

      // Whitespace
      await primaryFile.writeAsString('   \n\t  \r\n');
      expect(await service.loadTrips(), isEmpty);

      // Unmatched single brace
      await primaryFile.writeAsString('{');
      expect(await service.loadTrips(), isEmpty);
    });
  });

  group('Adversarial Test Suite 3: Atomic File Writing & Concurrency Stress', () {
    test('ADV-3.1: Heavy concurrent reads and writes do not corrupt storage', () async {
      final service = TripHistoryService(customDirectory: tempDir);

      // Fire 30 concurrent async operations
      final futures = <Future>[];
      for (int i = 0; i < 20; i++) {
        final index = i;
        futures.add(service.saveTrip(createTestTrip(
          id: 'concurrent_trip_$index',
          startTime: DateTime(2026, 6, 1, 10, index),
          distanceKm: 5.0 + index,
        )));
        if (i % 3 == 0) {
          futures.add(service.loadTrips());
        }
      }

      await Future.wait(futures);

      final finalTrips = await service.loadTrips();
      expect(finalTrips, hasLength(20));

      final primaryFile = File('${tempDir.path}/trips_history.json');
      expect(primaryFile.existsSync(), isTrue);

      // Verify JSON on disk is valid and parseable
      final diskContent = primaryFile.readAsStringSync();
      final decoded = jsonDecode(diskContent);
      expect(decoded, isA<List>());
      expect((decoded as List).length, 20);

      // No lingering .tmp files
      final tmpFile = File('${tempDir.path}/trips_history.json.tmp');
      expect(tmpFile.existsSync(), isFalse);
    });

    test('ADV-3.2: Lingering stale .tmp file does not block subsequent atomic saves', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final tmpFile = File('${tempDir.path}/trips_history.json.tmp');

      // Create a stale .tmp file simulating previous hard crash
      await tmpFile.writeAsString('HALF_WRITTEN_STALE_CRASH_CONTENT');
      expect(tmpFile.existsSync(), isTrue);

      // Now perform a saveTrip
      final trip = createTestTrip(id: 'clean_after_crash');
      await service.saveTrip(trip);

      // The save must succeed, overwrite .tmp, and rename cleanly
      final trips = await service.loadTrips();
      expect(trips, hasLength(1));
      expect(trips.first.id, 'clean_after_crash');
      expect(tmpFile.existsSync(), isFalse);
    });
  });

  group('Adversarial Test Suite 4: Active Trip Checkpointing & Crash Recovery', () {
    test('ADV-4.1: Simulated mid-trip process crash reconstructs in-flight trip', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final clockTime = DateTime(2026, 7, 10, 14, 0, 0);

      final provider1 = TripProvider(
        historyService: historyService,
        clock: () => clockTime,
      );
      provider1.manualStartTrip(clockTime);

      // Drive 2.5 km over 150 seconds at 60 km/h
      for (int i = 0; i <= 150; i += 10) {
        final t = clockTime.add(Duration(seconds: i));
        provider1.processDataPoint(
          const ObdData(speed: 60, rpm: 2200, engineFuelRate: 4.5),
          timestamp: t,
        );
      }

      final inFlightDistance = provider1.activeTrip.distanceKm;
      final inFlightFuel = provider1.activeTrip.fuelConsumedLiters;
      expect(inFlightDistance, greaterThan(2.0));

      // Force checkpoint
      await provider1.saveCheckpoint(clockTime.add(const Duration(seconds: 150)));

      // Simulate sudden process termination (no finishTrip, just dispose)
      provider1.dispose();

      // Checkpoint file should exist
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');
      expect(checkpointFile.existsSync(), isTrue);

      // Restart application: new TripProvider instance
      final provider2 = TripProvider(
        historyService: historyService,
        clock: () => clockTime.add(const Duration(minutes: 10)),
      );

      // Wait for async initialization deterministically
      await provider2.initialized;

      // The crashed in-flight trip should have been recovered into pastTrips
      expect(provider2.pastTrips, isNotEmpty);
      final recovered = provider2.pastTrips.first;
      expect(recovered.distanceKm, closeTo(inFlightDistance, 0.05));
      expect(recovered.fuelConsumedLiters, closeTo(inFlightFuel, 0.05));

      // Checkpoint must be purged after recovery
      expect(checkpointFile.existsSync(), isFalse);

      provider2.dispose();
    });

    test('ADV-4.2: Corrupted active checkpoint is cleared and does not leave zombie file', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');

      // Write corrupt checkpoint
      await checkpointFile.writeAsString('{"id": "corrupt", "distanceKm": INVALID_NUM');

      // Starting provider must not throw
      final provider = TripProvider(historyService: historyService);
      await provider.initialized;

      expect(provider.pastTrips, isEmpty);

      final stillExists = checkpointFile.existsSync();
      expect(stillExists, isFalse, reason: 'Corrupt checkpoint file must be purged by startup recovery');

      provider.dispose();
    });

    test('ADV-4.3: Sub-threshold checkpoint (< 0.1 km and < 5s) discarded cleanly', () async {
      final historyService = TripHistoryService(customDirectory: tempDir);
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');

      // Trip with only 2 seconds and 0.005 km (key-on / key-off jitter)
      final subThresholdData = {
        'id': 'accidental_start',
        'startTime': DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'durationSeconds': 2,
        'distanceKm': 0.005,
        'fuelConsumedLiters': 0.001,
        'avgFuelConsumption': 5.0,
        'avgSpeed': 5.0,
        'maxSpeed': 10.0,
        'maxRpm': 800,
        'rpmSum': 800,
        'sampleCount': 1,
        'lastSpeed': 0,
      };
      await checkpointFile.writeAsString(jsonEncode(subThresholdData));

      final provider = TripProvider(historyService: historyService);
      await provider.initialized;

      // Discarded; not added to pastTrips
      expect(provider.pastTrips, isEmpty);
      expect(checkpointFile.existsSync(), isFalse);

      provider.dispose();
    });
  });
}
