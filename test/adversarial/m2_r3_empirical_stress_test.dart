import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/settings/app_preferences.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.setMinTripDistanceKm(0.1);
    await AppPreferences.setAutoTripEnabled(true);
    tempDir = Directory.systemTemp.createTempSync('obdrive_r3_stress_');
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
    double distanceKm = 12.4,
    double fuelConsumed = 0.82,
  }) {
    final start = startTime ?? DateTime(2026, 8, 15, 11, 30);
    return Trip(
      id: id,
      startTime: start,
      endTime: start.add(const Duration(minutes: 20)),
      duration: const Duration(minutes: 20),
      distanceKm: distanceKm,
      fuelConsumedLiters: fuelConsumed,
      avgFuelConsumption: (fuelConsumed / distanceKm) * 100.0,
      avgSpeed: 37.2,
      maxSpeed: 65.0,
      maxRpm: 2600,
      avgRpm: 1750,
    );
  }

  group('M2 Round 3 Stress: Non-UTF8 Raw Byte Handling & Mirror Resilience', () {
    test('Stress 1.1: Non-UTF8 raw bytes backed up to .corrupt_<timestamp> and restored from .bak mirror', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final tripA = createTestTrip(id: 'trip_preserved_alpha');
      final tripB = createTestTrip(id: 'trip_preserved_beta', startTime: DateTime(2026, 8, 15, 12, 0));
      await service.saveTrip(tripA);
      await service.saveTrip(tripB);

      final primaryFile = File('${tempDir.path}/trips_history.json');
      final bakFile = File('${tempDir.path}/trips_history.json.bak');
      expect(primaryFile.existsSync(), isTrue);
      expect(bakFile.existsSync(), isTrue);

      // Corrupt primary file with arbitrary invalid non-UTF-8 bytes
      final corruptBytes = Uint8List.fromList([
        0xFF, 0xFE, 0xFD, 0xFC, 0x80, 0x81, 0x82, 0xC0, 0xC1, 0xF5, 0xF6, 0x00
      ]);
      await primaryFile.writeAsBytes(corruptBytes, flush: true);

      // Load trips: should trigger _handleCorruptedRawBytes
      final loaded = await service.loadTrips();

      expect(loaded, hasLength(2));
      expect(loaded.map((t) => t.id), containsAll(['trip_preserved_alpha', 'trip_preserved_beta']));

      // Verify a timestamped .corrupt_<timestamp> file was created with the exact raw bytes
      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles, hasLength(1));
      final savedCorruptBytes = await corruptFiles.first.readAsBytes();
      expect(savedCorruptBytes, equals(corruptBytes));

      // Verify primary file is now atomically restored to valid JSON
      final primaryContent = await primaryFile.readAsString();
      final decodedPrimary = jsonDecode(primaryContent) as List;
      expect(decodedPrimary, hasLength(2));

      // Verify subsequent loadTrips does not create any additional corrupt files
      final secondLoad = await service.loadTrips();
      expect(secondLoad, hasLength(2));
      final corruptFilesAfter = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFilesAfter, hasLength(1));
    });

    test('Stress 1.2: Empty .bak mirror ([]) with non-UTF8 primary resets primary to [] and avoids loop', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');
      final bakFile = File('${tempDir.path}/trips_history.json.bak');

      // Mirror exists with valid empty list '[]'
      await bakFile.writeAsString('[]');
      // Primary file has invalid non-UTF8 bytes
      await primaryFile.writeAsBytes([0x80, 0x81, 0xFF, 0xAA, 0xBB], flush: true);

      // First load
      final loaded1 = await service.loadTrips();
      expect(loaded1, isEmpty);

      // Verify primary file was reset to '[]'
      final content1 = await primaryFile.readAsString();
      expect(jsonDecode(content1), isEmpty);

      // Verify exactly 1 .corrupt_ file exists
      var corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles, hasLength(1));

      // Stress loop: call loadTrips 5 times in succession
      for (int i = 0; i < 5; i++) {
        final loopTrips = await service.loadTrips();
        expect(loopTrips, isEmpty);
      }

      // Verify no extra corrupt files were spawned
      corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles, hasLength(1), reason: 'Zero additional corrupt backup files should be spawned');
    });

    test('Stress 1.3: Total unrecoverable corruption (corrupt primary, no bak) resets primary to [] safely', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      // Write invalid non-UTF8 bytes with no .bak file present
      await primaryFile.writeAsBytes([0xC3, 0x28, 0x00, 0xFE, 0xFF], flush: true);

      final loaded = await service.loadTrips();
      expect(loaded, isEmpty);

      // Primary file must be safely reset to '[]'
      expect(primaryFile.existsSync(), isTrue);
      final content = await primaryFile.readAsString();
      expect(content, '[]');

      // Corrupt backup file preserved
      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles, hasLength(1));

      // Subsequent save works normally
      final newTrip = createTestTrip(id: 'fresh_trip_after_recovery');
      await service.saveTrip(newTrip);

      final reloaded = await service.loadTrips();
      expect(reloaded, hasLength(1));
      expect(reloaded.first.id, 'fresh_trip_after_recovery');
    });

    test('Stress 1.4: Subsequent saveTrip after non-UTF8 recovery preserves recovered trips in both files', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final trip1 = createTestTrip(id: 'trip_1_recovered');
      await service.saveTrip(trip1);

      final primaryFile = File('${tempDir.path}/trips_history.json');
      final bakFile = File('${tempDir.path}/trips_history.json.bak');

      // Inject non-UTF8 corrupt bytes into primary
      await primaryFile.writeAsBytes([0xFF, 0xFE, 0x80], flush: true);

      // User saves a second trip without an explicit loadTrips call first
      final trip2 = createTestTrip(id: 'trip_2_new', startTime: DateTime(2026, 8, 15, 14, 0));
      await service.saveTrip(trip2);

      // Primary and .bak should both contain trip2 and trip1
      final primaryTrips = _parse(await primaryFile.readAsString());
      final bakTrips = _parse(await bakFile.readAsString());

      expect(primaryTrips, hasLength(2));
      expect(bakTrips, hasLength(2));
      expect(primaryTrips.map((t) => t['id']), containsAll(['trip_1_recovered', 'trip_2_new']));
      expect(bakTrips.map((t) => t['id']), containsAll(['trip_1_recovered', 'trip_2_new']));
    });
  });

  group('M2 Round 3 Stress: Corrupted Active Checkpoint Purge & Zombie Prevention', () {
    test('Stress 2.1: Malformed JSON active checkpoint is deleted by loadActiveCheckpoint()', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');

      await checkpointFile.writeAsString('{"id": "broken", "distanceKm": 12.3, [truncated');
      expect(checkpointFile.existsSync(), isTrue);

      final loaded = await service.loadActiveCheckpoint();
      expect(loaded, isNull);
      expect(checkpointFile.existsSync(), isFalse, reason: 'Malformed JSON checkpoint must be deleted immediately');
    });

    test('Stress 2.2: Non-UTF8 raw bytes active checkpoint is deleted by loadActiveCheckpoint()', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');

      await checkpointFile.writeAsBytes([0xFF, 0xFE, 0x00, 0x80, 0xBF], flush: true);
      expect(checkpointFile.existsSync(), isTrue);

      final loaded = await service.loadActiveCheckpoint();
      expect(loaded, isNull);
      expect(checkpointFile.existsSync(), isFalse, reason: 'Non-UTF8 active checkpoint must be deleted immediately');
    });

    test('Stress 2.3: TripProvider startup purges corrupted checkpoint without leaving zombie file', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');

      await checkpointFile.writeAsString('{not even json: ???');
      expect(checkpointFile.existsSync(), isTrue);

      final provider = TripProvider(historyService: service);
      await provider.initialized;

      expect(provider.pastTrips, isEmpty);
      expect(checkpointFile.existsSync(), isFalse, reason: 'TripProvider startup must eradicate zombie checkpoint');

      provider.dispose();
    });

    test('Stress 2.4: Empty active checkpoint file is deleted without exception', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final checkpointFile = File('${tempDir.path}/active_trip_checkpoint.json');

      await checkpointFile.writeAsString('   \n  \t ');
      expect(checkpointFile.existsSync(), isTrue);

      final loaded = await service.loadActiveCheckpoint();
      expect(loaded, isNull);
      expect(checkpointFile.existsSync(), isFalse, reason: 'Empty checkpoint file must be purged');
    });
  });

  group('M2 Round 3 Stress: Asynchronous Constructor Initialization Synchronization', () {
    test('Stress 3.1: provider.initialized resolves deterministically before state consumption', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      // Pre-seed history with 3 trips
      for (int i = 1; i <= 3; i++) {
        await service.saveTrip(createTestTrip(id: 'preseed_$i', startTime: DateTime(2026, 8, 1, i, 0)));
      }

      final provider = TripProvider(historyService: service);

      // Await initialization deterministically
      await provider.initialized;

      // State is guaranteed to be fully loaded
      expect(provider.pastTrips, hasLength(3));
      expect(provider.minTripDistanceKm, 0.1);
      expect(provider.autoTripEnabled, isTrue);

      provider.dispose();
    });

    test('Stress 3.2: Rapid consecutive TripProvider re-instantiations complete initialized cleanly', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      await service.saveTrip(createTestTrip(id: 'stable_trip'));

      for (int i = 0; i < 5; i++) {
        final p = TripProvider(historyService: service);
        await p.initialized;
        expect(p.pastTrips, hasLength(1));
        expect(p.pastTrips.first.id, 'stable_trip');
        p.dispose();
      }
    });
  });

  group('M2 Round 3 Stress: High Concurrency Contention', () {
    test('Stress 4.1: 25 concurrent saves, loads, and checkpoint writes do not corrupt storage', () async {
      final service = TripHistoryService(customDirectory: tempDir);

      final futures = <Future>[];
      for (int i = 0; i < 25; i++) {
        final tripId = 'concurrent_trip_$i';
        if (i % 2 == 0) {
          futures.add(service.saveTrip(createTestTrip(id: tripId, startTime: DateTime(2026, 8, 10, 0, i))));
        } else {
          futures.add(service.loadTrips());
        }
      }

      await Future.wait(futures);

      final finalTrips = await service.loadTrips();
      expect(finalTrips, hasLength(13)); // 13 even indices saved

      // Check storage integrity
      final primaryFile = File('${tempDir.path}/trips_history.json');
      final content = await primaryFile.readAsString();
      expect(() => jsonDecode(content), returnsNormally);
    });
  });
}

List<dynamic> _parse(String jsonStr) => jsonDecode(jsonStr) as List<dynamic>;
