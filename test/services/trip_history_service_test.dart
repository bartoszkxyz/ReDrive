import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/services/trip/trip_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('redrive_trip_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Trip createSampleTrip({
    required String id,
    required DateTime startTime,
    Duration duration = const Duration(minutes: 25),
    double distanceKm = 18.5,
    double fuelConsumedLiters = 1.25,
    double avgFuelConsumption = 6.76,
    double avgSpeed = 44.4,
    double maxSpeed = 78.0,
    int maxRpm = 3100,
    int avgRpm = 1850,
  }) {
    return Trip(
      id: id,
      startTime: startTime,
      endTime: startTime.add(duration),
      duration: duration,
      distanceKm: distanceKm,
      fuelConsumedLiters: fuelConsumedLiters,
      avgFuelConsumption: avgFuelConsumption,
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
      maxRpm: maxRpm,
      avgRpm: avgRpm,
    );
  }

  group('Requirement R2 - TripHistoryService Persistence & Restart Recovery', () {
    test('1. Trip records fully survive service instance restart with complete field fidelity', () async {
      final serviceInstance1 = TripHistoryService(customDirectory: tempDir);

      final trip1 = createSampleTrip(
        id: 'trip_restart_001',
        startTime: DateTime(2026, 3, 15, 8, 30),
        duration: const Duration(hours: 1, minutes: 12),
        distanceKm: 64.8,
        fuelConsumedLiters: 4.15,
        avgFuelConsumption: 6.40,
        avgSpeed: 54.0,
        maxSpeed: 105.0,
        maxRpm: 3450,
        avgRpm: 2150,
      );

      await serviceInstance1.saveTrip(trip1);

      // Simulate complete application termination / service restart
      final serviceInstance2 = TripHistoryService(customDirectory: tempDir);
      final restoredTrips = await serviceInstance2.loadTrips();

      expect(restoredTrips, hasLength(1));
      final restored = restoredTrips.first;

      expect(restored.id, trip1.id);
      expect(restored.startTime, trip1.startTime);
      expect(restored.endTime, trip1.endTime);
      expect(restored.duration.inSeconds, trip1.duration.inSeconds);
      expect(restored.distanceKm, trip1.distanceKm);
      expect(restored.fuelConsumedLiters, trip1.fuelConsumedLiters);
      expect(restored.avgFuelConsumption, trip1.avgFuelConsumption);
      expect(restored.avgSpeed, trip1.avgSpeed);
      expect(restored.maxSpeed, trip1.maxSpeed);
      expect(restored.maxRpm, trip1.maxRpm);
      expect(restored.avgRpm, trip1.avgRpm);
    });

    test('2. Multiple trips are chronologically sorted (newest first) across restarts', () async {
      final service1 = TripHistoryService(customDirectory: tempDir);

      final tOld = createSampleTrip(
        id: 'trip_old',
        startTime: DateTime(2026, 1, 1, 9, 0),
        distanceKm: 10.0,
      );
      final tNew = createSampleTrip(
        id: 'trip_new',
        startTime: DateTime(2026, 1, 2, 9, 0),
        distanceKm: 25.0,
      );
      final tMid = createSampleTrip(
        id: 'trip_mid',
        startTime: DateTime(2026, 1, 1, 18, 0),
        distanceKm: 15.0,
      );

      // Save in unordered sequence
      await service1.saveTrip(tOld);
      await service1.saveTrip(tNew);
      await service1.saveTrip(tMid);

      final service2 = TripHistoryService(customDirectory: tempDir);
      final trips = await service2.loadTrips();

      expect(trips, hasLength(3));
      expect(trips[0].id, 'trip_new');
      expect(trips[1].id, 'trip_mid');
      expect(trips[2].id, 'trip_old');
    });

    test('3. Temporary directory isolation prevents cross-instance interference', () async {
      final tempDirA = Directory.systemTemp.createTempSync('redrive_sandbox_a_');
      final tempDirB = Directory.systemTemp.createTempSync('redrive_sandbox_b_');

      try {
        final serviceA = TripHistoryService(customDirectory: tempDirA);
        final serviceB = TripHistoryService(customDirectory: tempDirB);

        await serviceA.saveTrip(createSampleTrip(id: 'trip_a', startTime: DateTime.now()));
        await serviceB.saveTrip(createSampleTrip(id: 'trip_b', startTime: DateTime.now()));

        final tripsA = await serviceA.loadTrips();
        final tripsB = await serviceB.loadTrips();

        expect(tripsA, hasLength(1));
        expect(tripsA.first.id, 'trip_a');
        expect(tripsB, hasLength(1));
        expect(tripsB.first.id, 'trip_b');
      } finally {
        tempDirA.deleteSync(recursive: true);
        tempDirB.deleteSync(recursive: true);
      }
    });

    test('4. Atomic file write guarantees primary storage validity', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final trip = createSampleTrip(id: 'atomic_trip', startTime: DateTime.now());

      await service.saveTrip(trip);

      final file = File('${tempDir.path}/trips_history.json');
      expect(file.existsSync(), isTrue);

      // No lingering .tmp file left after successful atomic rename
      final tmpFile = File('${tempDir.path}/trips_history.json.tmp');
      expect(tmpFile.existsSync(), isFalse);

      final parsed = jsonDecode(file.readAsStringSync()) as List;
      expect(parsed, hasLength(1));
      expect(parsed.first['id'], 'atomic_trip');
    });

    test('5. Resilience to corrupted JSON: creates backup and prevents crash', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final historyFile = File('${tempDir.path}/trips_history.json');

      // Inject corrupt, truncated JSON
      await historyFile.writeAsString('[{"id":"trip_broken", "distanceKm": 12.3, "fuelCons');

      // loadTrips should not throw FormatException
      final trips = await service.loadTrips();
      expect(trips, isEmpty);

      // Verify a corrupt backup file was created
      final backupFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_') || f.path.endsWith('.bak'))
          .toList();

      expect(backupFiles, isNotEmpty, reason: 'A backup file of the corrupt content must be created');
    });

    test('6. Recovers valid trip records from .bak mirror when primary JSON is corrupt', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final tripValid = createSampleTrip(id: 'trip_recovered', startTime: DateTime.now());

      // Save a valid trip (which also populates the .bak mirror)
      await service.saveTrip(tripValid);

      // Corrupt the primary file only
      final historyFile = File('${tempDir.path}/trips_history.json');
      await historyFile.writeAsString('CORRUPTED_BINARY_PAYLOAD_%%%');

      // Next service restart
      final restartService = TripHistoryService(customDirectory: tempDir);
      final recoveredTrips = await restartService.loadTrips();

      expect(recoveredTrips, hasLength(1));
      expect(recoveredTrips.first.id, 'trip_recovered');
    });

    test('7. Trip deletion and clearAll persist across service restart', () async {
      final service1 = TripHistoryService(customDirectory: tempDir);

      await service1.saveTrip(createSampleTrip(id: 'trip_del_1', startTime: DateTime.now()));
      await service1.saveTrip(createSampleTrip(id: 'trip_del_2', startTime: DateTime.now()));

      await service1.deleteTrip('trip_del_1');

      final service2 = TripHistoryService(customDirectory: tempDir);
      var trips = await service2.loadTrips();
      expect(trips, hasLength(1));
      expect(trips.first.id, 'trip_del_2');

      await service2.clearAll();

      final service3 = TripHistoryService(customDirectory: tempDir);
      trips = await service3.loadTrips();
      expect(trips, isEmpty);
    });

    test('8. Recovers valid trip records from .bak mirror when primary contains non-UTF8 raw bytes and creates timestamped corrupt backup', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final tripValid = createSampleTrip(id: 'trip_non_utf8_recovery', startTime: DateTime.now());

      await service.saveTrip(tripValid);

      final historyFile = File('${tempDir.path}/trips_history.json');
      await historyFile.writeAsBytes([0xFF, 0xFE, 0x80, 0xBF, 0xC0, 0x00]);

      final restartService = TripHistoryService(customDirectory: tempDir);
      final recoveredTrips = await restartService.loadTrips();

      expect(recoveredTrips, hasLength(1));
      expect(recoveredTrips.first.id, 'trip_non_utf8_recovery');

      final corruptBackups = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptBackups, isNotEmpty);
    });
  });
}
