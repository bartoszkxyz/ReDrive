import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/core/app_flavor.dart';
import 'package:obdrive/models/sync_models.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/trip_route_point.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/garage_provider.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/sync_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/garage/garage_service.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late GarageService garageService;
  late GarageProvider garageProvider;
  late ObdProvider obdProvider;
  late TripProvider tripProvider;
  late SyncProvider syncProvider;
  late BluetoothSyncService syncService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sync_provider_test_');
    garageService = GarageService(customDirectory: tempDir);
    garageProvider = GarageProvider(garageService: garageService);
    obdProvider = ObdProvider();
    tripProvider = TripProvider();
    syncService = BluetoothSyncService(
      deviceId: 'test_sync_device',
      deviceRole: 'headunit',
      customStateFile: File('${tempDir.path}/sync_state.json'),
    );
    syncProvider = SyncProvider(syncService: syncService);

    await garageProvider.initialized;
    await tripProvider.initialized;
    await syncProvider.initialized;

    syncProvider.bindProviders(
      tripProvider: tripProvider,
      garageProvider: garageProvider,
      obdProvider: obdProvider,
    );
  });

  tearDown(() {
    AppConfig.reset();
    obdProvider.dispose();
    tripProvider.dispose();
    garageProvider.dispose();
    syncProvider.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SyncProvider & ParkedCarSnapshot Virtual Tank Integration', () {
    test('captureParkedSnapshot calculates remaining fuel and range from virtual tank', () async {
      // Default Suzuki Swift has 45L tank capacity and starts with 45L full
      expect(garageProvider.activeProfile.fuelLevelSource, equals(FuelLevelSource.virtualTank));
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(45.0));

      // Deduct 15L so virtual tank is 30L
      await garageProvider.deductFuel(15.0);

      final snapshot = await syncProvider.captureParkedSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.remainingFuelLiters, equals(30.0));
      expect(snapshot.fuelLevelPercent, closeTo(66.66, 0.1));
      // 30L / 0.068 (nominal 6.8 L/100km) ~ 441 km
      expect(snapshot.estimatedRangeKm, greaterThan(400.0));
    });

    test('captureParkedSnapshot zeroes fuel and range when FuelLevelSource is none', () async {
      await garageProvider.setFuelLevelSource(FuelLevelSource.none);

      final snapshot = await syncProvider.captureParkedSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.remainingFuelLiters, equals(0.0));
      expect(snapshot.fuelLevelPercent, equals(0.0));
      expect(snapshot.estimatedRangeKm, equals(0.0));
    });

    test('captureParkedSnapshot reads OBD-II PID values when FuelLevelSource is obdPid', () async {
      await garageProvider.setFuelLevelSource(FuelLevelSource.obdPid);

      obdProvider.setDataForTesting(
        const ObdData(
          fuelLevelPercent: 75.0,
          remainingFuelLiters: 33.75,
          estimatedRangeKm: 500.0,
        ),
      );

      final snapshot = await syncProvider.captureParkedSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.remainingFuelLiters, equals(33.75));
      expect(snapshot.fuelLevelPercent, equals(75.0));
      expect(snapshot.estimatedRangeKm, equals(500.0));
    });

    test('tripProvider.onTripFinished automatically deducts fuel burned from virtual tank', () async {
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(45.0));

      final trip = Trip(
        id: 'test_trip_1',
        startTime: DateTime.now().subtract(const Duration(minutes: 30)),
        endTime: DateTime.now(),
        distanceKm: 25.0,
        duration: const Duration(minutes: 30),
        fuelConsumedLiters: 1.85,
        avgFuelConsumption: 7.4,
        avgSpeed: 50.0,
        maxSpeed: 80,
        maxRpm: 3500,
        avgRpm: 2200,
      );

      // Trigger the callback
      await tripProvider.onTripFinished?.call(trip);

      expect(garageProvider.activeProfile.virtualTankCurrentLiters, closeTo(43.15, 0.01));
      expect(syncProvider.latestSnapshot?.remainingFuelLiters, closeTo(43.15, 0.01));
    });

    test('tripProvider.onSpeedZeroStandstill snapshots vehicle location at 0 km/h stop', () async {
      tripProvider.updateGpsFix(
        GpsFix(
          latitude: 52.2297,
          longitude: 21.0122,
          speedKmh: 0.0,
          timestamp: DateTime.now(),
        ),
      );

      await tripProvider.onSpeedZeroStandstill?.call();

      expect(syncProvider.latestSnapshot, isNotNull);
      expect(syncProvider.latestSnapshot?.latitude, equals(52.2297));
      expect(syncProvider.latestSnapshot?.longitude, equals(21.0122));
    });
  });

  group('SyncProvider Phone Disconnect Fallback', () {
    test('captures phone GPS location on Bluetooth disconnect when snapshot is stale', () async {
      AppConfig.initialize(flavor: AppFlavor.phone, appTitle: 'OBDrive Phone');

      // Set an existing snapshot that is 2 minutes old (stale)
      final staleSnapshot = ParkedCarSnapshot(
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        vehicleId: 'test_car',
        vehicleName: 'Test Car',
        latitude: 10.0,
        longitude: 10.0,
      );
      await syncService.updateParkedSnapshot(staleSnapshot);

      tripProvider.updateGpsFix(
        GpsFix(
          latitude: 48.8566,
          longitude: 2.3522,
          speedKmh: 0.0,
          timestamp: DateTime.now(),
        ),
      );

      final pair = InMemorySyncTransportPair();
      await syncService.attachTransport(pair.phoneTransport);

      // Simulate disconnection via detachTransport
      await syncService.detachTransport();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(syncProvider.latestSnapshot?.latitude, equals(48.8566));
      expect(syncProvider.latestSnapshot?.longitude, equals(2.3522));
    });
  });
}
