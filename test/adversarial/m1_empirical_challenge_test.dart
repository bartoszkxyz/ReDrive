import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/obd/connection/tcp_obd_connection.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/obd/pid/pid_key.dart';
import 'package:obdrive/obd/pid/pid_registry.dart';
import 'package:obdrive/obd/polling/polling_controller.dart';
import 'package:obdrive/obd/source/obd_source_state.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';

import '../e2e/e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Adversarial M1 Area 1: ObdData Model, CopyWith & Serialization', () {
    test('1.1: default constructor establishes well-defined baseline zeros across all 11 fields', () {
      const data = ObdData();

      expect(data.rpm, 0);
      expect(data.speed, 0);
      expect(data.coolantTemp, 0);
      expect(data.intakeAirTemp, 0);
      expect(data.voltage, 0.0);
      expect(data.engineLoad, 0.0);
      expect(data.throttlePosition, 0.0);
      expect(data.maf, 0.0);
      expect(data.engineFuelRate, 0.0);
      expect(data.instantFuelLPerHour, 0.0);
      expect(data.instantFuelL100km, 0.0);
    });

    test('1.2: copyWith exhaustively preserves all 10 un-modified fields when mutating any individual field', () {
      const initial = ObdData(
        rpm: 2500,
        speed: 80,
        coolantTemp: 88,
        intakeAirTemp: 27,
        voltage: 14.1,
        engineLoad: 35.5,
        throttlePosition: 22.0,
        maf: 12.4,
        engineFuelRate: 4.8,
        instantFuelLPerHour: 4.75,
        instantFuelL100km: 5.94,
      );

      // Mutate rpm only
      final mRpm = initial.copyWith(rpm: 3200);
      expect(mRpm.rpm, 3200);
      expect(mRpm.speed, initial.speed);
      expect(mRpm.coolantTemp, initial.coolantTemp);
      expect(mRpm.intakeAirTemp, initial.intakeAirTemp);
      expect(mRpm.voltage, initial.voltage);
      expect(mRpm.engineLoad, initial.engineLoad);
      expect(mRpm.throttlePosition, initial.throttlePosition);
      expect(mRpm.maf, initial.maf);
      expect(mRpm.engineFuelRate, initial.engineFuelRate);
      expect(mRpm.instantFuelLPerHour, initial.instantFuelLPerHour);
      expect(mRpm.instantFuelL100km, initial.instantFuelL100km);

      // Mutate intakeAirTemp only
      final mIat = initial.copyWith(intakeAirTemp: 35);
      expect(mIat.intakeAirTemp, 35);
      expect(mIat.rpm, initial.rpm);
      expect(mIat.speed, initial.speed);
      expect(mIat.coolantTemp, initial.coolantTemp);
      expect(mIat.voltage, initial.voltage);
      expect(mIat.engineLoad, initial.engineLoad);
      expect(mIat.throttlePosition, initial.throttlePosition);
      expect(mIat.maf, initial.maf);
      expect(mIat.engineFuelRate, initial.engineFuelRate);
      expect(mIat.instantFuelLPerHour, initial.instantFuelLPerHour);
      expect(mIat.instantFuelL100km, initial.instantFuelL100km);

      // Mutate speed only
      final mSpeed = initial.copyWith(speed: 110);
      expect(mSpeed.speed, 110);
      expect(mSpeed.intakeAirTemp, initial.intakeAirTemp);

      // Mutate coolantTemp only
      final mCoolant = initial.copyWith(coolantTemp: 95);
      expect(mCoolant.coolantTemp, 95);
      expect(mCoolant.intakeAirTemp, initial.intakeAirTemp);

      // Mutate voltage only
      final mVolt = initial.copyWith(voltage: 13.8);
      expect(mVolt.voltage, 13.8);
      expect(mVolt.intakeAirTemp, initial.intakeAirTemp);

      // Mutate load only
      final mLoad = initial.copyWith(engineLoad: 72.0);
      expect(mLoad.engineLoad, 72.0);
      expect(mLoad.intakeAirTemp, initial.intakeAirTemp);

      // Mutate throttle only
      final mThrottle = initial.copyWith(throttlePosition: 50.0);
      expect(mThrottle.throttlePosition, 50.0);
      expect(mThrottle.intakeAirTemp, initial.intakeAirTemp);

      // Mutate maf only
      final mMaf = initial.copyWith(maf: 25.0);
      expect(mMaf.maf, 25.0);
      expect(mMaf.intakeAirTemp, initial.intakeAirTemp);

      // Mutate engineFuelRate only
      final mFuelRate = initial.copyWith(engineFuelRate: 8.5);
      expect(mFuelRate.engineFuelRate, 8.5);
      expect(mFuelRate.intakeAirTemp, initial.intakeAirTemp);

      // Mutate instantFuelLPerHour only
      final mInstFlow = initial.copyWith(instantFuelLPerHour: 6.2);
      expect(mInstFlow.instantFuelLPerHour, 6.2);
      expect(mInstFlow.intakeAirTemp, initial.intakeAirTemp);

      // Mutate instantFuelL100km only
      final mInstEcon = initial.copyWith(instantFuelL100km: 6.8);
      expect(mInstEcon.instantFuelL100km, 6.8);
      expect(mInstEcon.intakeAirTemp, initial.intakeAirTemp);
    });

    test('1.3: copyWith survives extreme, zero, and negative engineering ranges', () {
      const data = ObdData();

      // Winter cold start: IAT and Coolant at -40°C
      final subZero = data.copyWith(
        intakeAirTemp: -40,
        coolantTemp: -35,
        voltage: 11.2,
      );
      expect(subZero.intakeAirTemp, -40);
      expect(subZero.coolantTemp, -35);
      expect(subZero.voltage, 11.2);

      // Desert high-temp heat soak: IAT at 120°C
      final heatSoak = subZero.copyWith(
        intakeAirTemp: 120,
        coolantTemp: 115,
      );
      expect(heatSoak.intakeAirTemp, 120);
      expect(heatSoak.coolantTemp, 115);
      expect(heatSoak.voltage, 11.2); // preserved
    });

    test('1.4: toString snapshot serializes cleanly and contains all 11 fields including IAT', () {
      const sample = ObdData(
        rpm: 3000,
        speed: 100,
        coolantTemp: 90,
        intakeAirTemp: 32,
        voltage: 14.2,
        engineLoad: 45.0,
        throttlePosition: 20.0,
        maf: 15.5,
        engineFuelRate: 5.2,
        instantFuelLPerHour: 5.15,
        instantFuelL100km: 5.15,
      );

      final str = sample.toString();
      expect(str, contains('rpm: 3000'));
      expect(str, contains('speed: 100 km/h'));
      expect(str, contains('coolantTemp: 90°C'));
      expect(str, contains('iat: 32°C'));
      expect(str, contains('voltage: 14.2 V'));
      expect(str, contains('load: 45.0%'));
      expect(str, contains('throttle: 20.0%'));
      expect(str, contains('maf: 15.50 g/s'));
      expect(str, contains('directFuelRate: 5.20 L/h'));
      expect(str, contains('fuelRate: 5.15 L/h'));
      expect(str, contains('fuelEconomy: 5.2 L/100km'));
    });
  });

  group('Adversarial M1 Area 2: Stress Simulated Telemetry Stream & IAT Pipeline', () {
    test('2.1: ObdProvider and PidRegistry configuration contracts include IAT in core/session sets', () {
      final registry = PidRegistry();
      expect(PidRegistry.coreKeys, contains(PidKey.intakeAirTemperature));
      expect(ObdProvider.defaultSessionKeys, contains(PidKey.intakeAirTemperature));
      expect(registry.allKeys, contains(PidKey.intakeAirTemperature));

      final iatDef = registry.find(PidKey.intakeAirTemperature);
      expect(iatDef, isNotNull);
      expect(iatDef!.command, '010F');
      expect(iatDef.pid, 0x0F);
    });

    test('2.2: Live stream ingestion decodes and routes IAT updates to data model, getPidValue, and listeners', () async {
      final server = MockElmTcpServer();
      server.rpm = 2000;
      server.speed = 60;
      server.iat = 35; // 35°C
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final provider = ObdProvider();
      provider.attachConnection(connection);
      provider.setWatchlist(WatchSource.visibleScreen, {
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
        PidKey.intakeAirTemperature,
      });

      unawaited(provider.startRealMode());

      await _waitUntil(
        () => provider.state == ObdSourceState.polling,
        'polling state',
      );

      final receivedDataPoints = <ObdData>[];
      final sub = provider.dataStream.listen(receivedDataPoints.add);

      // Wait for IAT to be polled and ingested
      await _waitUntil(
        () => provider.data.intakeAirTemp == 35,
        'IAT update to 35C',
      );

      expect(provider.data.intakeAirTemp, 35);
      expect(provider.getPidValue(PidKey.intakeAirTemperature), 35.0);
      expect(provider.latestPidValues[PidKey.intakeAirTemperature], 35.0);
      expect(receivedDataPoints.any((d) => d.intakeAirTemp == 35), isTrue);

      // Now dynamically change IAT to cold winter condition: -10°C
      server.iat = -10;

      await _waitUntil(
        () => provider.data.intakeAirTemp == -10,
        'IAT update to -10C',
      );

      expect(provider.data.intakeAirTemp, -10);
      expect(provider.getPidValue(PidKey.intakeAirTemperature), -10.0);
      expect(provider.latestPidValues[PidKey.intakeAirTemperature], -10.0);

      await sub.cancel();
      await provider.stopRealMode();
      await connection.disconnect();
      await server.stop();
      provider.dispose();
    });

    test('2.3: Stress test — high frequency cyclic PID ingestion maintains stream integrity', () async {
      final server = MockElmTcpServer();
      server.rpm = 1200;
      server.speed = 40;
      server.coolant = 75;
      server.iat = 22;
      server.load = 30.0;
      server.throttle = 15.0;
      server.maf = 8.0;
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final provider = ObdProvider();
      provider.attachConnection(connection);
      provider.setWatchlist(WatchSource.visibleScreen, {
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
        PidKey.coolantTemperature,
        PidKey.intakeAirTemperature,
        PidKey.engineLoad,
        PidKey.throttlePosition,
        PidKey.mafAirFlowRate,
      });

      unawaited(provider.startRealMode());

      await _waitUntil(
        () => provider.state == ObdSourceState.polling,
        'polling state',
      );

      int notifyCount = 0;
      provider.addListener(() {
        notifyCount++;
      });

      // Rapidly update dynamic values in cyclic waves on server
      for (int i = 0; i < 15; i++) {
        server.iat = 20 + (i % 15);
        server.rpm = 1000 + (i * 70);
        server.speed = 30 + (i * 2);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      await _waitUntil(() => notifyCount >= 10, 'Notified at least 10 times');
      expect(provider.data.rpm, greaterThan(1000));
      expect(provider.data.intakeAirTemp, greaterThanOrEqualTo(20));

      await provider.stopRealMode();
      await connection.disconnect();
      await server.stop();
      provider.dispose();
    });
  });

  group('Adversarial M1 Area 3: Dynamic DFCO Phases & Fuel Economy Non-Accrual', () {
    const calculator = FuelCalculator(displacementLiters: 1.5);

    test('3.1: FuelCalculator DFCO boundary conditions (overrun vs boundary edge values)', () {
      // Nominal DFCO in gear: 60 km/h, 2400 RPM, closed throttle 0%, load 12%
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: 2400,
          speedKmH: 60,
          throttlePositionPercent: 0.0,
          engineLoadPercent: 12.0,
        ),
        0.0,
      );

      // Suzuki Swift absolute idle throttle DFCO (10% - 14%)
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: 2400,
          speedKmH: 60,
          throttlePositionPercent: 10.0,
          engineLoadPercent: 12.0,
        ),
        0.0,
      );
      expect(
        calculator.calculateFuelFlowLitersPerHour(
          rpm: 2400,
          speedKmH: 60,
          throttlePositionPercent: 14.0,
          engineLoadPercent: 12.0,
        ),
        0.0,
      );

      // Boundary tests where DFCO is NOT triggered (must return positive fuel flow):
      // a) Speed boundary: exactly 20 km/h (speed must be > 20)
      final atSpeed20 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2400,
        speedKmH: 20,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
      );
      expect(atSpeed20, greaterThan(0.0));

      // b) RPM boundary: exactly 1300 RPM (rpm must be > 1300)
      final atRpm1300 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1300,
        speedKmH: 60,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
      );
      expect(atRpm1300, greaterThan(0.0));

      // c) Throttle boundary: between 1.0% and 9.9% (not closed, not absolute idle)
      final atThrottle5 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2400,
        speedKmH: 60,
        throttlePositionPercent: 5.0,
        engineLoadPercent: 12.0,
      );
      expect(atThrottle5, greaterThan(0.0));

      // d) Throttle boundary: 14.1% (throttle pedal depressed beyond idle stop)
      final atThrottle14Point1 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2400,
        speedKmH: 60,
        throttlePositionPercent: 14.1,
        engineLoadPercent: 12.0,
      );
      expect(atThrottle14Point1, greaterThan(0.0));

      // e) Engine load boundary: exactly 18.0% (engineLoadPercent must be < 18.0)
      final atLoad18 = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2400,
        speedKmH: 60,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 18.0,
      );
      expect(atLoad18, greaterThan(0.0));
    });

    test('3.2: DFCO overrides Direct Fuel Rate (PID 015E) and trims to deliver strictly 0.0 L/h', () {
      final dfcoWithDirectRate = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        speedKmH: 55,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 11.0,
        directFuelRateLPerHour: 3.5, // Even if ECU reports raw rate
        shortTermFuelTrimPercent: 15.0, // With high positive trim
        longTermFuelTrimPercent: 10.0,
      );
      expect(dfcoWithDirectRate, 0.0);

      final dfcoL100km = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: dfcoWithDirectRate,
        speedKmH: 55,
      );
      expect(dfcoL100km, 0.0);
    });

    test('3.3: Dynamic driving simulation with TripProvider: DFCO coast-down freezes fuel consumption accrual while accumulating distance', () async {
      final server = MockElmTcpServer();
      server.speed = 60;
      server.rpm = 2400;
      server.throttle = 25.0;
      server.load = 35.0;
      server.maf = 12.0;
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);
      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      tripProvider.bindToObd(obdProvider);

      obdProvider.setWatchlist(WatchSource.visibleScreen, {
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
        PidKey.throttlePosition,
        PidKey.engineLoad,
        PidKey.mafAirFlowRate,
      });

      unawaited(obdProvider.startRealMode());

      await _waitUntil(
        () => obdProvider.state == ObdSourceState.polling,
        'polling state',
      );

      // Wait for trip start & initial cruising accumulation
      await _waitUntil(
        () =>
            tripProvider.activeTrip.isActive &&
            tripProvider.activeTrip.distanceKm > 0.0 &&
            tripProvider.activeTrip.fuelConsumedLiters > 0.0,
        'Active cruising trip with distance > 0 and fuel > 0',
      );

      final cruise1 = tripProvider.activeTrip;
      expect(cruise1.instantFuelLPerHour, greaterThan(0.0));
      expect(cruise1.fuelConsumedLiters, greaterThan(0.0));

      // Phase 2: Enter dynamic DFCO overrun (closed throttle 0.0%, light load 11.0%, speed 55 km/h, RPM 2000)
      server.throttle = 0.0;
      server.load = 11.0;
      server.rpm = 2000;
      server.speed = 55;

      // Wait until DFCO instantaneous values reflect 0.0
      await _waitUntil(
        () => tripProvider.activeTrip.instantFuelLPerHour == 0.0,
        'DFCO instant fuel drop to 0.0',
      );

      final dfcoBaselineFuel = tripProvider.activeTrip.fuelConsumedLiters;
      final dfcoBaselineDistance = tripProvider.activeTrip.distanceKm;
      expect(dfcoBaselineFuel, greaterThan(0.0));
      expect(tripProvider.activeTrip.instantFuelLPerHour, 0.0);
      expect(tripProvider.activeTrip.instantFuelL100km, 0.0);

      // Simulate extended coast-down in DFCO
      await Future<void>.delayed(const Duration(milliseconds: 200));
      server.speed = 50;

      await _waitUntil(
        () => tripProvider.activeTrip.distanceKm > dfcoBaselineDistance,
        'Distance accumulation during DFCO',
      );

      final activeDfco = tripProvider.activeTrip;
      expect(activeDfco.instantFuelLPerHour, 0.0);
      expect(activeDfco.instantFuelL100km, 0.0);

      // Invariants verified:
      // 1. Distance increased during coasting
      expect(activeDfco.distanceKm, greaterThan(dfcoBaselineDistance));

      // 2. Cumulative fuel consumed did NOT accrue (remains frozen within float precision)
      expect(activeDfco.fuelConsumedLiters, closeTo(dfcoBaselineFuel, 0.000001));

      // Clean up
      await obdProvider.stopRealMode();
      await connection.disconnect();
      await server.stop();
      tripProvider.dispose();
      obdProvider.dispose();
    });
  });

  group('Adversarial M1 Area 4: Full Pipeline TCP Loopback Ingestion with Live Server', () {
    test('4.1: Live MockElmTcpServer loopback verifies IAT hex parsing into ObdProvider', () async {
      final server = MockElmTcpServer();
      server.rpm = 2100;
      server.speed = 55;
      server.coolant = 87;
      server.iat = 38; // 38°C (raw: 38 + 40 = 78 -> 0x4E)
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      obdProvider.setWatchlist(WatchSource.visibleScreen, {
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
        PidKey.coolantTemperature,
        PidKey.intakeAirTemperature,
      });

      unawaited(obdProvider.startRealMode());

      await _waitUntil(
        () => obdProvider.state == ObdSourceState.polling,
        'polling state',
      );

      // Wait for at least one IAT read
      await _waitUntil(
        () => obdProvider.data.intakeAirTemp == 38,
        'loopback IAT ingestion',
      );

      expect(obdProvider.data.intakeAirTemp, 38);
      expect(obdProvider.getPidValue(PidKey.intakeAirTemperature), 38.0);
      expect(server.receivedCommands, contains('010F'));

      await obdProvider.stopRealMode();
      await connection.disconnect();
      await server.stop();
      obdProvider.dispose();
    });
  });
}

Future<void> _waitUntil(bool Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
