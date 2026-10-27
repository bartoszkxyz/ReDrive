import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/services/garage/garage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('obdrive_garage_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  VehicleProfile createTestProfile({
    required String id,
    required String name,
    double displacementLiters = 2.0,
    FuelType fuelType = FuelType.gasoline,
    double baseOdometerKm = 50000.0,
  }) {
    return VehicleProfile(
      id: id,
      name: name,
      displacementLiters: displacementLiters,
      fuelType: fuelType,
      baseOdometerKm: baseOdometerKm,
      maintenanceItems: [
        MaintenanceItem(
          id: 'oil',
          name: 'Engine Oil',
          intervalKm: 10000.0,
          lastServiceOdometerKm: baseOdometerKm,
        ),
      ],
    );
  }

  group('GarageState', () {
    test('activeProfile returns matching profile when activeProfileId exists', () {
      final p1 = createTestProfile(id: 'car1', name: 'Car One');
      final p2 = createTestProfile(id: 'car2', name: 'Car Two');
      final state = GarageState(profiles: [p1, p2], activeProfileId: 'car2');

      expect(state.activeProfile.id, 'car2');
      expect(state.activeProfile.name, 'Car Two');
    });

    test('activeProfile falls back to first profile if activeProfileId does not match', () {
      final p1 = createTestProfile(id: 'car1', name: 'Car One');
      final p2 = createTestProfile(id: 'car2', name: 'Car Two');
      final state =
          GarageState(profiles: [p1, p2], activeProfileId: 'non_existent');

      expect(state.activeProfile.id, 'car1');
    });

    test('activeProfile falls back to default Suzuki Swift if profiles list is empty', () {
      const state = GarageState(profiles: [], activeProfileId: 'any');

      final profile = state.activeProfile;
      expect(profile.id, 'default_swift_m15a');
      expect(profile.name, 'Suzuki Swift 3 (M15A 1.5L)');
    });

    test('toJson and fromJson preserves complete GarageState fidelity', () {
      final p1 = createTestProfile(id: 'car1', name: 'Car One');
      final state = GarageState(profiles: [p1], activeProfileId: 'car1');

      final json = state.toJson();
      final restored = GarageState.fromJson(json);

      expect(restored, equals(state));
      expect(restored.hashCode, equals(state.hashCode));
      expect(restored.profiles.first.name, 'Car One');
      expect(restored.toString(), contains('car1'));
    });
  });

  group('GarageService Initialization & File Recovery', () {
    test('fresh initialization seeds default Suzuki Swift M15A profile and persists to disk', () async {
      final service = GarageService(customDirectory: tempDir);
      final state = await service.loadGarage();

      expect(state.profiles, hasLength(1));
      expect(state.activeProfileId, 'default_swift_m15a');
      expect(state.activeProfile.name, 'Suzuki Swift 3 (M15A 1.5L)');
      expect(state.activeProfile.maintenanceItems, hasLength(4));

      // Check file was actually written to disk
      final file = File('${tempDir.path}/garage_profiles.json');
      expect(file.existsSync(), isTrue);
      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded['activeProfileId'], 'default_swift_m15a');
      expect((decoded['profiles'] as List), hasLength(1));
    });

    test('empty or malformed empty profiles re-seeds default profile', () async {
      final file = File('${tempDir.path}/garage_profiles.json');
      await file.writeAsString(jsonEncode({'profiles': [], 'activeProfileId': ''}));

      final service = GarageService(customDirectory: tempDir);
      final state = await service.loadGarage();

      expect(state.profiles, hasLength(1));
      expect(state.activeProfileId, 'default_swift_m15a');
    });

    test('corrupt JSON creates timestamped backup and heals primary file with default state', () async {
      final file = File('${tempDir.path}/garage_profiles.json');
      const corruptContent = '{ "profiles": [ { "id": "truncated_bad_data...';
      await file.writeAsString(corruptContent);

      final service = GarageService(customDirectory: tempDir);
      final state = await service.loadGarage();

      // Recovers with default state
      expect(state.profiles, hasLength(1));
      expect(state.activeProfileId, 'default_swift_m15a');

      // Verifies backup file was created matching .corrupt.<timestamp>.bak
      final backupFiles = tempDir
          .listSync()
          .where((f) => f.path.contains('.corrupt.') && f.path.endsWith('.bak'))
          .toList();

      expect(backupFiles, hasLength(1));
      final backupContent = File(backupFiles.first.path).readAsStringSync();
      expect(backupContent, corruptContent);

      // Verifies primary file was healed
      final healedContent = jsonDecode(file.readAsStringSync());
      expect(healedContent['activeProfileId'], 'default_swift_m15a');
    });
  });

  group('GarageService CRUD Operations', () {
    test('upsertProfile adds a new vehicle and retains active profile', () async {
      final service = GarageService(customDirectory: tempDir);
      await service.loadGarage(); // initial default

      final civic = createTestProfile(
        id: 'civic_ep3',
        name: 'Honda Civic Type-R (EP3)',
        displacementLiters: 2.0,
      );

      final updatedState = await service.upsertProfile(civic, setAsActive: false);

      expect(updatedState.profiles, hasLength(2));
      expect(updatedState.profiles.any((p) => p.id == 'civic_ep3'), isTrue);
      expect(updatedState.activeProfileId, 'default_swift_m15a');
    });

    test('upsertProfile with setAsActive true updates active profile', () async {
      final service = GarageService(customDirectory: tempDir);
      final civic = createTestProfile(id: 'civic_ep3', name: 'Honda Civic Type-R');

      final updatedState = await service.upsertProfile(civic, setAsActive: true);

      expect(updatedState.activeProfileId, 'civic_ep3');
      expect(updatedState.activeProfile.name, 'Honda Civic Type-R');
    });

    test('upsertProfile updates an existing profile in place without duplicating', () async {
      final service = GarageService(customDirectory: tempDir);
      final civic = createTestProfile(id: 'civic_ep3', name: 'Honda Civic');
      await service.upsertProfile(civic);

      final modifiedCivic = civic.copyWith(
        name: 'Honda Civic Type-R (Tuned)',
        fuelType: FuelType.lpg,
      );

      final updatedState = await service.upsertProfile(modifiedCivic);

      expect(updatedState.profiles, hasLength(2));
      final storedCivic = updatedState.profiles.firstWhere((p) => p.id == 'civic_ep3');
      expect(storedCivic.name, 'Honda Civic Type-R (Tuned)');
      expect(storedCivic.fuelType, FuelType.lpg);
    });

    test('setActiveProfile switches the active vehicle', () async {
      final service = GarageService(customDirectory: tempDir);
      final civic = createTestProfile(id: 'civic_ep3', name: 'Honda Civic');
      await service.upsertProfile(civic);

      final state = await service.setActiveProfile('civic_ep3');
      expect(state.activeProfileId, 'civic_ep3');

      // Attempting to set an invalid profile throws ArgumentError
      expect(
        () => service.setActiveProfile('non_existent_car'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteProfile removes specified profile', () async {
      final service = GarageService(customDirectory: tempDir);
      final civic = createTestProfile(id: 'civic_ep3', name: 'Honda Civic');
      await service.upsertProfile(civic);

      final state = await service.deleteProfile('civic_ep3');
      expect(state.profiles, hasLength(1));
      expect(state.profiles.any((p) => p.id == 'civic_ep3'), isFalse);
    });

    test('deleteProfile of currently active profile selects remaining profile as active', () async {
      final service = GarageService(customDirectory: tempDir);
      final civic = createTestProfile(id: 'civic_ep3', name: 'Honda Civic');
      await service.upsertProfile(civic, setAsActive: true);

      expect((await service.loadGarage()).activeProfileId, 'civic_ep3');

      final state = await service.deleteProfile('civic_ep3');
      expect(state.profiles, hasLength(1));
      expect(state.activeProfileId, 'default_swift_m15a');
      expect(state.activeProfile.id, 'default_swift_m15a');
    });

    test('deleteProfile never leaves profiles empty; re-seeds default Suzuki Swift if last profile deleted', () async {
      final service = GarageService(customDirectory: tempDir);
      final initialState = await service.loadGarage();
      expect(initialState.profiles, hasLength(1));

      // Delete the only profile
      final afterDelete = await service.deleteProfile('default_swift_m15a');
      expect(afterDelete.profiles, hasLength(1));
      expect(afterDelete.activeProfileId, 'default_swift_m15a');
      expect(afterDelete.activeProfile.name, 'Suzuki Swift 3 (M15A 1.5L)');
    });

    test('markMaintenanceServiced records service odometer and date', () async {
      final service = GarageService(customDirectory: tempDir);
      final serviceDate = DateTime(2026, 4, 10, 14, 0);

      final updatedState = await service.markMaintenanceServiced(
        profileId: 'default_swift_m15a',
        maintenanceItemId: 'oil_filter',
        atOdometerKm: 160500.0,
        atDate: serviceDate,
      );

      final oilItem = updatedState.activeProfile.maintenanceItems
          .firstWhere((i) => i.id == 'oil_filter');
      expect(oilItem.lastServiceOdometerKm, 160500.0);
      expect(oilItem.lastServiceDate, serviceDate);
      expect(oilItem.nextDueOdometerKm, 170500.0);
      expect(oilItem.isOverdue(160500.0), isFalse);
    });

    test('markMaintenanceServiced throws ArgumentError on missing profile or item', () async {
      final service = GarageService(customDirectory: tempDir);

      expect(
        () => service.markMaintenanceServiced(
          profileId: 'unknown_profile',
          maintenanceItemId: 'oil_filter',
          atOdometerKm: 160000.0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.markMaintenanceServiced(
          profileId: 'default_swift_m15a',
          maintenanceItemId: 'non_existent_item',
          atOdometerKm: 160000.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('GarageService Persistence Fidelity & Concurrency', () {
    test('complete garage state survives service instance restart', () async {
      final service1 = GarageService(customDirectory: tempDir);
      final mx5 = createTestProfile(
        id: 'mazda_mx5',
        name: 'Mazda MX-5 Miata',
        displacementLiters: 1.8,
        fuelType: FuelType.gasoline,
        baseOdometerKm: 88500.0,
      );

      await service1.upsertProfile(mx5, setAsActive: true);
      await service1.markMaintenanceServiced(
        profileId: 'mazda_mx5',
        maintenanceItemId: 'oil',
        atOdometerKm: 88000.0,
        atDate: DateTime(2026, 3, 1),
      );

      // Simulate app restart with a fresh service instance
      final service2 = GarageService(customDirectory: tempDir);
      final restoredState = await service2.loadGarage();

      expect(restoredState.profiles, hasLength(2));
      expect(restoredState.activeProfileId, 'mazda_mx5');

      final restoredMx5 = restoredState.activeProfile;
      expect(restoredMx5.name, 'Mazda MX-5 Miata');
      expect(restoredMx5.displacementLiters, 1.8);
      expect(restoredMx5.baseOdometerKm, 88500.0);

      final oilItem = restoredMx5.maintenanceItems.first;
      expect(oilItem.lastServiceOdometerKm, 88000.0);
      expect(oilItem.lastServiceDate, DateTime(2026, 3, 1));
    });

    test('handles concurrent async modifications safely with mutex', () async {
      final service = GarageService(customDirectory: tempDir);
      await service.loadGarage();

      // Launch 10 concurrent operations
      final futures = <Future<GarageState>>[];
      for (int i = 0; i < 10; i++) {
        final profile = createTestProfile(
          id: 'concurrent_car_$i',
          name: 'Concurrent Car $i',
          baseOdometerKm: 10000.0 * i,
        );
        futures.add(service.upsertProfile(profile));
      }

      await Future.wait(futures);

      final finalState = await service.loadGarage();
      expect(finalState.profiles, hasLength(11)); // 1 initial + 10 added
    });
  });
}
