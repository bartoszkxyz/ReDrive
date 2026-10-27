import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/garage_provider.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/garage/garage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late GarageService garageService;
  late GarageProvider garageProvider;
  late ObdProvider obdProvider;
  late TripProvider tripProvider;

  const sampleHtml = '''
<!DOCTYPE html>
<html>
<body>
  <table>
    <tbody>
      <tr><th scope="row">Brand</th><td>BMW</td></tr>
      <tr><th scope="row">Model</th><td>3 Series</td></tr>
      <tr><th scope="row">Generation</th><td>3 Series (E90)</td></tr>
      <tr><th scope="row">Modification (Engine)</th><td>320d (177 Hp)</td></tr>
      <tr><th scope="row">Start of production</th><td>2007 year</td></tr>
      <tr><th scope="row">Fuel Type</th><td>Diesel</td></tr>
      <tr><th scope="row">Power</th><td>177 Hp @ 4000 rpm.</td></tr>
      <tr><th scope="row">Engine displacement</th><td>1995 cm<sup>3</sup></td></tr>
      <tr><th scope="row">Fuel tank capacity</th><td>61 l</td></tr>
      <tr><th scope="row">Kerb Weight</th><td>1430 kg</td></tr>
      <tr><th scope="row">Redline RPM</th><td>4800 rpm</td></tr>
    </tbody>
  </table>
</body>
</html>
''';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('garage_provider_test_');
    garageService = GarageService(customDirectory: tempDir);
    garageProvider = GarageProvider(garageService: garageService);
    obdProvider = ObdProvider();
    tripProvider = TripProvider();

    await garageProvider.initialized;
    await tripProvider.initialized;
  });

  tearDown(() {
    obdProvider.dispose();
    tripProvider.dispose();
    garageProvider.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('GarageProvider Initialization', () {
    test('initializes with default Suzuki Swift profile', () async {
      expect(garageProvider.isLoading, isFalse);
      expect(garageProvider.profiles.length, equals(1));
      expect(garageProvider.activeProfileId, equals('default_swift_m15a'));
      expect(garageProvider.activeProfile.name, equals('Suzuki Swift 3 (M15A 1.5L)'));
      expect(garageProvider.activeProfile.fuelType, equals(FuelType.gasoline));
      expect(garageProvider.activeProfile.displacementLiters, equals(1.5));
      expect(garageProvider.activeProfile.fuelTankCapacityLiters, equals(45.0));
      expect(garageProvider.activeProfile.baseOdometerKm, equals(150000.0));
    });
  });

  group('GarageProvider Provider Binding and Propagation', () {
    test('bindProviders propagates active profile to ObdProvider and TripProvider', () {
      garageProvider.bindProviders(
        obdProvider: obdProvider,
        tripProvider: tripProvider,
      );

      // Verify ObdProvider received profile
      expect(obdProvider.vehicleProfile.id, equals(garageProvider.activeProfile.id));
      expect(obdProvider.vehicleProfile.fuelTankCapacityLiters, equals(45.0));
      expect(obdProvider.vehicleProfile.coolantOverheatTempC, equals(102));

      // Verify TripProvider received profile
      expect(tripProvider.activeVehicleProfile.id, equals(garageProvider.activeProfile.id));
      expect(tripProvider.fuelCalculator.displacementLiters, equals(1.5));
      expect(tripProvider.fuelCalculator.airFuelRatio, equals(14.7)); // Gasoline AFR
      expect(tripProvider.effectiveOdometerKm, equals(150000.0));
    });

    test('ObdProvider uses vehicle profile tank capacity and overheat threshold', () async {
      // Set initial OBD telemetry: 50% fuel, 104°C coolant
      obdProvider.setDataForTesting(
        const ObdData(
          fuelLevelPercent: 50.0,
          coolantTemp: 104,
        ),
      );

      // Binding with Swift profile (45L tank, 102°C overheat threshold)
      garageProvider.bindProviders(
        obdProvider: obdProvider,
        tripProvider: tripProvider,
      );

      // Overheat threshold is 102°C, 104°C triggers overheat alert
      expect(obdProvider.isCoolantOverheating, isTrue);

      // Test tank capacity calculation: 50% of 45L = 22.5L
      expect(obdProvider.data.remainingFuelLiters, closeTo(22.5, 0.01));

      // Switch to custom profile with 112°C overheat threshold and 60L tank
      final coolProfile = VehicleProfile(
        id: 'cool_profile',
        name: 'Cool Car',
        fuelTankCapacityLiters: 60.0,
        coolantOverheatTempC: 112,
      );
      await garageProvider.saveProfile(coolProfile, setAsActive: true);

      // 104°C is < clearThreshold (112 - 6 = 106), alert clears
      expect(obdProvider.isCoolantOverheating, isFalse);
      // 50% of 60L = 30L
      expect(obdProvider.data.remainingFuelLiters, closeTo(30.0, 0.01));
    });
  });

  group('GarageProvider Profile Management', () {
    final customDiesel = VehicleProfile(
      id: 'custom_diesel_profile',
      name: 'BMW 320d (E90)',
      year: 2007,
      displacementLiters: 2.0,
      fuelType: FuelType.diesel,
      fuelTankCapacityLiters: 61.0,
      idleThrottleBaselinePercent: 10.0,
      redlineRpm: 4800,
      optimalShiftRpm: 2500,
      coolantOverheatTempC: 105,
      maxHorsepower: 177,
      curbWeightKg: 1430,
      baseOdometerKm: 180000.0,
      maintenanceItems: VehicleProfile.defaultMaintenanceItems(
        baseOdometerKm: 180000.0,
      ),
    );

    test('selectActiveProfile switches active vehicle and propagates to providers', () async {
      garageProvider.bindProviders(
        obdProvider: obdProvider,
        tripProvider: tripProvider,
      );

      // Save custom diesel profile without setting active yet
      await garageProvider.saveProfile(customDiesel, setAsActive: false);
      expect(garageProvider.profiles.length, equals(2));
      expect(garageProvider.activeProfileId, equals('default_swift_m15a'));

      // Switch active profile
      await garageProvider.selectActiveProfile(customDiesel.id);
      expect(garageProvider.activeProfileId, equals(customDiesel.id));
      expect(garageProvider.activeProfile.name, equals('BMW 320d (E90)'));

      // Verify ObdProvider updated
      expect(obdProvider.vehicleProfile.id, equals(customDiesel.id));
      expect(obdProvider.vehicleProfile.fuelTankCapacityLiters, equals(61.0));
      expect(obdProvider.vehicleProfile.coolantOverheatTempC, equals(105));

      // Verify TripProvider updated
      expect(tripProvider.activeVehicleProfile.id, equals(customDiesel.id));
      expect(tripProvider.fuelCalculator.displacementLiters, equals(2.0));
      expect(tripProvider.fuelCalculator.airFuelRatio, equals(14.5)); // Diesel stoich AFR
      expect(tripProvider.effectiveOdometerKm, equals(180000.0));
    });

    test('saveProfile with setAsActive true immediately propagates new profile', () async {
      garageProvider.bindProviders(
        obdProvider: obdProvider,
        tripProvider: tripProvider,
      );

      await garageProvider.saveProfile(customDiesel, setAsActive: true);

      expect(garageProvider.activeProfileId, equals(customDiesel.id));
      expect(obdProvider.vehicleProfile.id, equals(customDiesel.id));
      expect(tripProvider.activeVehicleProfile.id, equals(customDiesel.id));
      expect(tripProvider.fuelCalculator.displacementLiters, equals(2.0));
    });

    test('deleteProfile removes profile and falls back cleanly if active', () async {
      garageProvider.bindProviders(
        obdProvider: obdProvider,
        tripProvider: tripProvider,
      );

      // Add second profile and set as active
      await garageProvider.saveProfile(customDiesel, setAsActive: true);
      expect(garageProvider.activeProfileId, equals(customDiesel.id));

      // Delete active profile -> should fall back to remaining Suzuki Swift
      await garageProvider.deleteProfile(customDiesel.id);
      expect(garageProvider.profiles.length, equals(1));
      expect(garageProvider.activeProfileId, equals('default_swift_m15a'));
      expect(obdProvider.vehicleProfile.id, equals('default_swift_m15a'));
      expect(tripProvider.activeVehicleProfile.id, equals('default_swift_m15a'));
    });

    test('deleteProfile of last profile re-seeds default Suzuki Swift', () async {
      expect(garageProvider.profiles.length, equals(1));
      await garageProvider.deleteProfile('default_swift_m15a');

      expect(garageProvider.profiles.length, equals(1));
      expect(garageProvider.activeProfile.id, equals('default_swift_m15a'));
    });
  });

  group('GarageProvider Maintenance Tracking', () {
    test('markMaintenanceServiced updates odometer and timestamp', () async {
      garageProvider.bindProviders(
        obdProvider: obdProvider,
        tripProvider: tripProvider,
      );

      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await garageProvider.markMaintenanceServiced(
        maintenanceItemId: 'oil_filter',
        atOdometerKm: 158500.0,
      );
      final after = DateTime.now().add(const Duration(seconds: 1));

      final active = garageProvider.activeProfile;
      final oilItem = active.maintenanceItems.firstWhere((i) => i.id == 'oil_filter');

      expect(oilItem.lastServiceOdometerKm, equals(158500.0));
      expect(oilItem.lastServiceDate, isNotNull);
      expect(oilItem.lastServiceDate!.isAfter(before), isTrue);
      expect(oilItem.lastServiceDate!.isBefore(after), isTrue);
      expect(oilItem.remainingKm(158500.0), equals(10000.0));
      expect(oilItem.isOverdue(158500.0), isFalse);
    });
  });

  group('GarageProvider Auto-Data Specification Parsing', () {
    test('parseAutoDataUrl successfully parses specifications with mock fetcher', () async {
      final specs = await garageProvider.parseAutoDataUrl(
        'https://www.auto-data.net/en/bmw-3-series-e90-320d-177hp-9900',
        httpFetcher: (_) async => sampleHtml,
      );

      expect(specs, isNotNull);
      expect(specs!.brand, equals('BMW'));
      expect(specs.model, equals('3 Series'));
      expect(specs.year, equals(2007));
      expect(specs.displacementLiters, equals(2.0));
      expect(specs.fuelTypeKey, equals('diesel'));
      expect(specs.fuelTankCapacityLiters, equals(61.0));
      expect(specs.maxHorsepower, equals(177));
      expect(specs.redlineRpm, equals(4800));
      expect(specs.curbWeightKg, equals(1430));
      expect(garageProvider.urlParseError, isNull);
      expect(garageProvider.isParsingUrl, isFalse);
    });

    test('parseAutoDataUrl handles invalid URL format gracefully', () async {
      final specs = await garageProvider.parseAutoDataUrl(
        'https://not-auto-data.com/some-car',
      );

      expect(specs, isNull);
      expect(garageProvider.urlParseError, isNotNull);
      expect(garageProvider.urlParseError, contains('Invalid auto-data.net vehicle URL'));
      expect(garageProvider.isParsingUrl, isFalse);

      // Clear error
      garageProvider.clearUrlParseError();
      expect(garageProvider.urlParseError, isNull);
    });

    test('parseAutoDataUrl handles network fetch error gracefully', () async {
      final specs = await garageProvider.parseAutoDataUrl(
        'https://www.auto-data.net/en/some-car-1234',
        httpFetcher: (_) async => throw const SocketException('Network unreachable'),
      );

      expect(specs, isNull);
      expect(garageProvider.urlParseError, isNotNull);
      expect(garageProvider.urlParseError, contains('Failed to fetch specs'));
      expect(garageProvider.isParsingUrl, isFalse);
    });
  });

  group('GarageProvider Virtual Tank Operations', () {
    test('refuelFull resets virtual tank to capacity and updates lastRefuelDate', () async {
      // Partially drain the tank first
      await garageProvider.deductFuel(20.0);
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(25.0));

      final refuelDate = DateTime(2026, 10, 19, 12, 0);
      await garageProvider.refuelFull(atDate: refuelDate);

      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(45.0));
      expect(garageProvider.activeProfile.lastRefuelDate, equals(refuelDate));
      expect(garageProvider.activeProfile.virtualFuelPercent, equals(100.0));
    });

    test('refuelAmount increments fuel level clamped at tank capacity', () async {
      await garageProvider.deductFuel(30.0); // 15L remaining
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(15.0));

      await garageProvider.refuelAmount(10.0);
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(25.0));

      // Overfilling clamps to 45.0
      await garageProvider.refuelAmount(50.0);
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(45.0));
    });

    test('deductFuel subtracts fuel burned clamped at 0.0', () async {
      await garageProvider.deductFuel(15.0);
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(30.0));

      // Subtraction exceeding current liters clamps to 0.0
      await garageProvider.deductFuel(50.0);
      expect(garageProvider.activeProfile.virtualTankCurrentLiters, equals(0.0));
      expect(garageProvider.activeProfile.virtualFuelPercent, equals(0.0));
    });

    test('setFuelLevelSource switches between virtualTank, obdPid, and none', () async {
      expect(garageProvider.activeProfile.fuelLevelSource, equals(FuelLevelSource.virtualTank));

      await garageProvider.setFuelLevelSource(FuelLevelSource.obdPid);
      expect(garageProvider.activeProfile.fuelLevelSource, equals(FuelLevelSource.obdPid));

      // In obdPid mode, deductFuel is ignored
      await garageProvider.deductFuel(10.0);
      expect(garageProvider.activeProfile.fuelLevelSource, equals(FuelLevelSource.obdPid));

      await garageProvider.setFuelLevelSource(FuelLevelSource.none);
      expect(garageProvider.activeProfile.fuelLevelSource, equals(FuelLevelSource.none));
    });
  });
}

