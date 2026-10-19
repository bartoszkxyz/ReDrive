import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/models/vehicle_profile.dart';

void main() {
  group('FuelType enum', () {
    test('provides accurate labels for all fuel types', () {
      expect(FuelType.gasoline.label, 'Gasoline');
      expect(FuelType.lpg.label, 'LPG');
      expect(FuelType.diesel.label, 'Diesel');
      expect(FuelType.hybrid.label, 'Hybrid');
    });

    test('provides stoichiometric air-fuel ratios (AFR)', () {
      expect(FuelType.gasoline.defaultStoichAfr, 14.7);
      expect(FuelType.lpg.defaultStoichAfr, 15.5);
      expect(FuelType.diesel.defaultStoichAfr, 14.5);
      expect(FuelType.hybrid.defaultStoichAfr, 14.7);
    });

    test('provides default density in grams per liter', () {
      expect(FuelType.gasoline.defaultDensityGramsPerLiter, 820.0);
      expect(FuelType.lpg.defaultDensityGramsPerLiter, 540.0);
      expect(FuelType.diesel.defaultDensityGramsPerLiter, 840.0);
      expect(FuelType.hybrid.defaultDensityGramsPerLiter, 820.0);
    });

    test('fromString parses case-insensitively and maps synonyms', () {
      expect(FuelType.fromString('gasoline'), FuelType.gasoline);
      expect(FuelType.fromString('GASOLINE'), FuelType.gasoline);
      expect(FuelType.fromString('petrol'), FuelType.gasoline);
      expect(FuelType.fromString('Petrol'), FuelType.gasoline);
      expect(FuelType.fromString('  PETROL  '), FuelType.gasoline);

      expect(FuelType.fromString('lpg'), FuelType.lpg);
      expect(FuelType.fromString('LPG'), FuelType.lpg);

      expect(FuelType.fromString('diesel'), FuelType.diesel);
      expect(FuelType.fromString('DIESEL'), FuelType.diesel);

      expect(FuelType.fromString('hybrid'), FuelType.hybrid);
      expect(FuelType.fromString('Hybrid'), FuelType.hybrid);

      // Unknown or null defaults to gasoline
      expect(FuelType.fromString(null), FuelType.gasoline);
      expect(FuelType.fromString(''), FuelType.gasoline);
      expect(FuelType.fromString('electric'), FuelType.gasoline);
    });
  });

  group('FuelLevelSource enum', () {
    test('provides accurate labels for all fuel level sources', () {
      expect(FuelLevelSource.obdPid.label, 'OBD-II Sensor (PID 2F)');
      expect(FuelLevelSource.virtualTank.label, 'Virtual Fuel Tank');
      expect(FuelLevelSource.none.label, 'Disabled / None');
    });

    test('fromString parses case-insensitively and maps synonyms', () {
      expect(FuelLevelSource.fromString('obdpid'), FuelLevelSource.obdPid);
      expect(FuelLevelSource.fromString('obd_pid'), FuelLevelSource.obdPid);
      expect(FuelLevelSource.fromString('obd'), FuelLevelSource.obdPid);
      expect(FuelLevelSource.fromString('OBDPID'), FuelLevelSource.obdPid);
      expect(FuelLevelSource.fromString('OBD_PID'), FuelLevelSource.obdPid);
      expect(FuelLevelSource.fromString('OBD'), FuelLevelSource.obdPid);
      expect(FuelLevelSource.fromString('  obd_pid  '), FuelLevelSource.obdPid);

      expect(FuelLevelSource.fromString('virtualtank'), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('virtual_tank'), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('virtual'), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('VIRTUALTANK'), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('VIRTUAL_TANK'), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('VIRTUAL'), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('  virtual_tank  '), FuelLevelSource.virtualTank);

      expect(FuelLevelSource.fromString('none'), FuelLevelSource.none);
      expect(FuelLevelSource.fromString('disabled'), FuelLevelSource.none);
      expect(FuelLevelSource.fromString('NONE'), FuelLevelSource.none);
      expect(FuelLevelSource.fromString('DISABLED'), FuelLevelSource.none);
      expect(FuelLevelSource.fromString('  disabled  '), FuelLevelSource.none);

      // Unknown or null defaults to virtualTank
      expect(FuelLevelSource.fromString(null), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString(''), FuelLevelSource.virtualTank);
      expect(FuelLevelSource.fromString('unknown_source'), FuelLevelSource.virtualTank);
    });
  });

  group('MaintenanceItem model', () {
    final baseDate = DateTime(2026, 1, 15, 10, 0);

    final item = MaintenanceItem(
      id: 'oil_filter',
      name: 'Engine Oil & Filter',
      intervalKm: 10000.0,
      lastServiceOdometerKm: 150000.0,
      lastServiceDate: baseDate,
    );

    test('nextDueOdometerKm sums last service odometer and interval', () {
      expect(item.nextDueOdometerKm, 160000.0);
    });

    test('remainingKm calculates correct distance to next due', () {
      expect(item.remainingKm(155000.0), 5000.0);
      expect(item.remainingKm(160000.0), 0.0);
      expect(item.remainingKm(161500.0), -1500.0);
    });

    test('progress calculates normalized ratio clamped between 0.0 and 2.0', () {
      expect(item.progress(150000.0), 0.0);
      expect(item.progress(155000.0), 0.5);
      expect(item.progress(160000.0), 1.0);
      expect(item.progress(165000.0), 1.5);
      expect(item.progress(175000.0), 2.0); // clamped at 2.0
      expect(item.progress(140000.0), 0.0); // clamped at 0.0

      const zeroInterval = MaintenanceItem(
        id: 'zero',
        name: 'Zero Interval',
        intervalKm: 0.0,
      );
      expect(zeroInterval.progress(100.0), 1.0);
    });

    test('isOverdue triggers when remaining distance is zero or negative', () {
      expect(item.isOverdue(159999.0), isFalse);
      expect(item.isOverdue(160000.0), isTrue);
      expect(item.isOverdue(160500.0), isTrue);
    });

    test('isDueSoon identifies upcoming service within threshold', () {
      // remaining: 5000km > 1000km -> not due soon
      expect(item.isDueSoon(155000.0), isFalse);
      // remaining: 800km <= 1000km -> due soon
      expect(item.isDueSoon(159200.0), isTrue);
      // remaining: exactly 1000km -> due soon
      expect(item.isDueSoon(159000.0), isTrue);
      // remaining: 0km -> overdue, so isDueSoon must be false
      expect(item.isDueSoon(160000.0), isFalse);
      // overdue -> false
      expect(item.isDueSoon(160500.0), isFalse);

      // Custom threshold
      expect(item.isDueSoon(157000.0, thresholdKm: 3500.0), isTrue);
    });

    test('markServiced updates odometer and service date', () {
      final serviceDate = DateTime(2026, 6, 20);
      final updated = item.markServiced(
        atOdometerKm: 160200.0,
        atDate: serviceDate,
      );

      expect(updated.id, item.id);
      expect(updated.name, item.name);
      expect(updated.intervalKm, item.intervalKm);
      expect(updated.lastServiceOdometerKm, 160200.0);
      expect(updated.lastServiceDate, serviceDate);
      expect(updated.nextDueOdometerKm, 170200.0);
      expect(updated.isOverdue(160200.0), isFalse);
    });

    test('markServiced uses current timestamp when atDate is omitted', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final updated = item.markServiced(atOdometerKm: 161000.0);
      final after = DateTime.now().add(const Duration(seconds: 1));

      expect(updated.lastServiceOdometerKm, 161000.0);
      expect(updated.lastServiceDate, isNotNull);
      expect(updated.lastServiceDate!.isAfter(before), isTrue);
      expect(updated.lastServiceDate!.isBefore(after), isTrue);
    });

    test('copyWith creates modified copy preserving other fields', () {
      final copy = item.copyWith(name: 'Premium Oil & Filter', intervalKm: 8000.0);
      expect(copy.id, item.id);
      expect(copy.name, 'Premium Oil & Filter');
      expect(copy.intervalKm, 8000.0);
      expect(copy.lastServiceOdometerKm, item.lastServiceOdometerKm);
      expect(copy.lastServiceDate, item.lastServiceDate);
    });

    test('JSON serialization and deserialization preserves all values', () {
      final json = item.toJson();
      expect(json['id'], 'oil_filter');
      expect(json['name'], 'Engine Oil & Filter');
      expect(json['intervalKm'], 10000.0);
      expect(json['lastServiceOdometerKm'], 150000.0);
      expect(json['lastServiceDate'], baseDate.toIso8601String());

      final restored = MaintenanceItem.fromJson(json);
      expect(restored, equals(item));
      expect(restored.hashCode, equals(item.hashCode));
    });

    test('JSON deserialization handles null lastServiceDate gracefully', () {
      const itemWithoutDate = MaintenanceItem(
        id: 'cabin_filter',
        name: 'Cabin Filter',
        intervalKm: 15000.0,
        lastServiceOdometerKm: 50000.0,
      );

      final json = itemWithoutDate.toJson();
      expect(json.containsKey('lastServiceDate'), isFalse);

      final restored = MaintenanceItem.fromJson(json);
      expect(restored.lastServiceDate, isNull);
      expect(restored, equals(itemWithoutDate));
    });

    test('equality and hashCode verify value semantics', () {
      final itemA = MaintenanceItem(
        id: 'oil',
        name: 'Oil',
        intervalKm: 10000.0,
        lastServiceOdometerKm: 1000.0,
        lastServiceDate: baseDate,
      );
      final itemB = MaintenanceItem(
        id: 'oil',
        name: 'Oil',
        intervalKm: 10000.0,
        lastServiceOdometerKm: 1000.0,
        lastServiceDate: baseDate,
      );
      final itemC = itemA.copyWith(intervalKm: 12000.0);

      expect(itemA, equals(itemB));
      expect(itemA.hashCode, equals(itemB.hashCode));
      expect(itemA, isNot(equals(itemC)));
      expect(itemA.toString(), contains('oil'));
    });
  });

  group('VehicleProfile model', () {
    test('constructor defaults reflect standard passenger car specifications', () {
      const profile = VehicleProfile(
        id: 'test_car',
        name: 'Test Vehicle',
      );

      expect(profile.id, 'test_car');
      expect(profile.name, 'Test Vehicle');
      expect(profile.vin, isNull);
      expect(profile.year, isNull);
      expect(profile.displacementLiters, 1.5);
      expect(profile.fuelType, FuelType.gasoline);
      expect(profile.fuelTankCapacityLiters, 45.0);
      expect(profile.idleThrottleBaselinePercent, 13.0);
      expect(profile.wotThrottleBaselinePercent, 85.0);
      expect(profile.nominalVoltage, 14.2);
      expect(profile.redlineRpm, 6500);
      expect(profile.optimalShiftRpm, 3200);
      expect(profile.coolantOverheatTempC, 102);
      expect(profile.maxHorsepower, 102);
      expect(profile.curbWeightKg, 1015);
      expect(profile.baseOdometerKm, 0.0);
      expect(profile.sourceAutoDataUrl, isNull);
      expect(profile.maintenanceItems, isEmpty);
      expect(profile.fuelLevelSource, FuelLevelSource.virtualTank);
      expect(profile.virtualTankCurrentLiters, isNull);
      expect(profile.lastRefuelDate, isNull);
    });

    test('effectiveOdometerKm adds cumulative trip distance to base odometer', () {
      const profile = VehicleProfile(
        id: 'car1',
        name: 'Car 1',
        baseOdometerKm: 154200.0,
      );

      expect(profile.effectiveOdometerKm(0.0), 154200.0);
      expect(profile.effectiveOdometerKm(152.7), 154352.7);
    });

    test('defaultMaintenanceItems returns 4 standard maintenance checkpoints', () {
      final items = VehicleProfile.defaultMaintenanceItems(baseOdometerKm: 120000.0);
      expect(items, hasLength(4));

      expect(items[0].id, 'oil_filter');
      expect(items[0].name, 'Engine Oil & Filter');
      expect(items[0].intervalKm, 10000.0);
      expect(items[0].lastServiceOdometerKm, 120000.0);

      expect(items[1].id, 'air_cabin_filter');
      expect(items[1].name, 'Air & Cabin Filters');
      expect(items[1].intervalKm, 15000.0);
      expect(items[1].lastServiceOdometerKm, 120000.0);

      expect(items[2].id, 'spark_plugs');
      expect(items[2].name, 'Spark Plugs');
      expect(items[2].intervalKm, 30000.0);
      expect(items[2].lastServiceOdometerKm, 120000.0);

      expect(items[3].id, 'valve_clearance');
      expect(items[3].name, 'Valve Clearance Check');
      expect(items[3].intervalKm, 40000.0);
      expect(items[3].lastServiceOdometerKm, 120000.0);
    });

    test('defaultSuzukiSwiftM15A preset matches benchmark vehicle specifications', () {
      final swift = VehicleProfile.defaultSuzukiSwiftM15A();

      expect(swift.id, 'default_swift_m15a');
      expect(swift.name, 'Suzuki Swift 3 (M15A 1.5L)');
      expect(swift.year, 2007);
      expect(swift.displacementLiters, 1.5);
      expect(swift.fuelType, FuelType.gasoline);
      expect(swift.fuelTankCapacityLiters, 45.0);
      expect(swift.idleThrottleBaselinePercent, 13.0);
      expect(swift.wotThrottleBaselinePercent, 85.0);
      expect(swift.nominalVoltage, 14.2);
      expect(swift.redlineRpm, 6500);
      expect(swift.optimalShiftRpm, 3200);
      expect(swift.coolantOverheatTempC, 102);
      expect(swift.maxHorsepower, 102);
      expect(swift.curbWeightKg, 1015);
      expect(swift.baseOdometerKm, 150000.0);
      expect(swift.maintenanceItems, hasLength(4));
      expect(swift.maintenanceItems.first.lastServiceOdometerKm, 150000.0);
      expect(swift.fuelLevelSource, FuelLevelSource.virtualTank);
      expect(swift.virtualTankCurrentLiters, 45.0);
      expect(swift.lastRefuelDate, isNull);
    });

    test('refuelFull fills virtual tank to capacity and records timestamp', () {
      final refuelDate = DateTime(2026, 4, 1, 10, 30);
      const profile = VehicleProfile(
        id: 'car1',
        name: 'Car 1',
        fuelTankCapacityLiters: 45.0,
        virtualTankCurrentLiters: 12.0,
      );

      final fullExplicit = profile.refuelFull(atDate: refuelDate);
      expect(fullExplicit.virtualTankCurrentLiters, 45.0);
      expect(fullExplicit.lastRefuelDate, refuelDate);

      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final fullImplicit = profile.refuelFull();
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(fullImplicit.virtualTankCurrentLiters, 45.0);
      expect(fullImplicit.lastRefuelDate, isNotNull);
      expect(fullImplicit.lastRefuelDate!.isAfter(before), isTrue);
      expect(fullImplicit.lastRefuelDate!.isBefore(after), isTrue);
    });

    test('refuelAmount adds liters and clamps between 0.0 and capacity', () {
      final refuelDate = DateTime(2026, 4, 2, 11, 0);
      const untracked = VehicleProfile(
        id: 'car1',
        name: 'Car 1',
        fuelTankCapacityLiters: 50.0,
      );

      // Starting from null treats current as 0.0
      final initial = untracked.refuelAmount(20.0, atDate: refuelDate);
      expect(initial.virtualTankCurrentLiters, 20.0);
      expect(initial.lastRefuelDate, refuelDate);

      // Adding to existing fuel
      final topUp = initial.refuelAmount(15.0);
      expect(topUp.virtualTankCurrentLiters, 35.0);

      // Overflow clamped to capacity
      final overflow = topUp.refuelAmount(25.0);
      expect(overflow.virtualTankCurrentLiters, 50.0);

      // Negative value clamped to 0.0
      final negative = initial.refuelAmount(-30.0);
      expect(negative.virtualTankCurrentLiters, 0.0);
    });

    test('deductFuel reduces fuel clamped to capacity or returns unmodified if untracked', () {
      const untracked = VehicleProfile(
        id: 'car_untracked',
        name: 'Untracked',
        fuelTankCapacityLiters: 45.0,
      );
      // Untracked profile is unchanged
      final afterBurnUntracked = untracked.deductFuel(5.0);
      expect(afterBurnUntracked.virtualTankCurrentLiters, isNull);

      const tracked = VehicleProfile(
        id: 'car_tracked',
        name: 'Tracked',
        fuelTankCapacityLiters: 45.0,
        virtualTankCurrentLiters: 20.0,
      );
      final burned = tracked.deductFuel(5.5);
      expect(burned.virtualTankCurrentLiters, 14.5);

      // Burning more than remaining clamps to 0.0
      final empty = tracked.deductFuel(25.0);
      expect(empty.virtualTankCurrentLiters, 0.0);

      // Burning negative fuel (fuel added) clamps to tank capacity
      final excess = tracked.deductFuel(-35.0);
      expect(excess.virtualTankCurrentLiters, 45.0);
    });

    test('virtualFuelPercent calculates clamped percentage or null when invalid', () {
      const untracked = VehicleProfile(
        id: 'car',
        name: 'Car',
        fuelTankCapacityLiters: 50.0,
      );
      expect(untracked.virtualFuelPercent, isNull);

      const zeroCapacity = VehicleProfile(
        id: 'car',
        name: 'Car',
        fuelTankCapacityLiters: 0.0,
        virtualTankCurrentLiters: 10.0,
      );
      expect(zeroCapacity.virtualFuelPercent, isNull);

      const half = VehicleProfile(
        id: 'car',
        name: 'Car',
        fuelTankCapacityLiters: 50.0,
        virtualTankCurrentLiters: 25.0,
      );
      expect(half.virtualFuelPercent, 50.0);

      const full = VehicleProfile(
        id: 'car',
        name: 'Car',
        fuelTankCapacityLiters: 50.0,
        virtualTankCurrentLiters: 50.0,
      );
      expect(full.virtualFuelPercent, 100.0);

      const overfilled = VehicleProfile(
        id: 'car',
        name: 'Car',
        fuelTankCapacityLiters: 50.0,
        virtualTankCurrentLiters: 60.0,
      );
      expect(overfilled.virtualFuelPercent, 100.0);

      const negative = VehicleProfile(
        id: 'car',
        name: 'Car',
        fuelTankCapacityLiters: 50.0,
        virtualTankCurrentLiters: -5.0,
      );
      expect(negative.virtualFuelPercent, 0.0);
    });

    test('copyWith creates modified instance with field overrides', () {
      final swift = VehicleProfile.defaultSuzukiSwiftM15A();
      final refuelDate = DateTime(2026, 4, 15, 9, 0);
      final modified = swift.copyWith(
        fuelType: FuelType.lpg,
        baseOdometerKm: 165000.0,
        vin: 'TSMZC21S000123456',
        fuelLevelSource: FuelLevelSource.obdPid,
        virtualTankCurrentLiters: 38.0,
        lastRefuelDate: refuelDate,
      );

      expect(modified.id, swift.id);
      expect(modified.fuelType, FuelType.lpg);
      expect(modified.baseOdometerKm, 165000.0);
      expect(modified.vin, 'TSMZC21S000123456');
      expect(modified.displacementLiters, 1.5);
      expect(modified.redlineRpm, 6500);
      expect(modified.fuelLevelSource, FuelLevelSource.obdPid);
      expect(modified.virtualTankCurrentLiters, 38.0);
      expect(modified.lastRefuelDate, refuelDate);
    });

    test('JSON serialization and deserialization produces identical model', () {
      final swift = VehicleProfile.defaultSuzukiSwiftM15A();
      final json = swift.toJson();

      expect(json['id'], 'default_swift_m15a');
      expect(json['name'], 'Suzuki Swift 3 (M15A 1.5L)');
      expect(json['year'], 2007);
      expect(json['displacementLiters'], 1.5);
      expect(json['fuelType'], 'gasoline');
      expect(json['fuelTankCapacityLiters'], 45.0);
      expect(json['idleThrottleBaselinePercent'], 13.0);
      expect(json['wotThrottleBaselinePercent'], 85.0);
      expect(json['nominalVoltage'], 14.2);
      expect(json['redlineRpm'], 6500);
      expect(json['optimalShiftRpm'], 3200);
      expect(json['coolantOverheatTempC'], 102);
      expect(json['maxHorsepower'], 102);
      expect(json['curbWeightKg'], 1015);
      expect(json['baseOdometerKm'], 150000.0);
      expect(json['fuelLevelSource'], 'virtualTank');
      expect(json['virtualTankCurrentLiters'], 45.0);
      expect(json.containsKey('lastRefuelDate'), isFalse);
      expect(json['maintenanceItems'], isA<List>());
      expect((json['maintenanceItems'] as List).length, 4);

      final restored = VehicleProfile.fromJson(json);
      expect(restored, equals(swift));
      expect(restored.hashCode, equals(swift.hashCode));
    });

    test('JSON roundtrip preserves custom fuel level source and lastRefuelDate', () {
      final refuelDate = DateTime(2026, 4, 10, 15, 30);
      final profile = VehicleProfile.defaultSuzukiSwiftM15A().copyWith(
        fuelLevelSource: FuelLevelSource.none,
        virtualTankCurrentLiters: 22.5,
        lastRefuelDate: refuelDate,
      );

      final json = profile.toJson();
      expect(json['fuelLevelSource'], 'none');
      expect(json['virtualTankCurrentLiters'], 22.5);
      expect(json['lastRefuelDate'], refuelDate.toIso8601String());

      final restored = VehicleProfile.fromJson(json);
      expect(restored, equals(profile));
      expect(restored.fuelLevelSource, FuelLevelSource.none);
      expect(restored.virtualTankCurrentLiters, 22.5);
      expect(restored.lastRefuelDate, refuelDate);
    });

    test('JSON deserialization handles missing or malformed fields safely', () {
      final minimalJson = <String, dynamic>{
        'id': 'custom_car',
        'name': 'Custom Car',
      };

      final profile = VehicleProfile.fromJson(minimalJson);
      expect(profile.id, 'custom_car');
      expect(profile.name, 'Custom Car');
      expect(profile.displacementLiters, 1.5);
      expect(profile.fuelType, FuelType.gasoline);
      expect(profile.fuelTankCapacityLiters, 45.0);
      expect(profile.redlineRpm, 6500);
      expect(profile.curbWeightKg, 1015);
      expect(profile.maintenanceItems, isEmpty);
      expect(profile.fuelLevelSource, FuelLevelSource.virtualTank);
      expect(profile.virtualTankCurrentLiters, isNull);
      expect(profile.lastRefuelDate, isNull);
    });

    test('equality and hashCode semantics', () {
      final a = VehicleProfile.defaultSuzukiSwiftM15A();
      final b = VehicleProfile.defaultSuzukiSwiftM15A();
      final c = a.copyWith(maxHorsepower: 125);
      final d = a.copyWith(virtualTankCurrentLiters: 20.0);
      final e = a.copyWith(fuelLevelSource: FuelLevelSource.obdPid);
      final f = a.copyWith(lastRefuelDate: DateTime(2026, 5, 1));

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
      expect(a, isNot(equals(e)));
      expect(a, isNot(equals(f)));
      expect(a.hashCode, isNot(equals(d.hashCode)));
      expect(a.hashCode, isNot(equals(e.hashCode)));
      expect(a.hashCode, isNot(equals(f.hashCode)));
      expect(a.toString(), contains('Suzuki Swift 3'));
      expect(a.toString(), contains('virtualTank: 45.0L'));
    });
  });
}
