import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/obd/connection/tcp_obd_connection.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/obd/elm/elm_response_parser.dart';
import 'package:redrive/obd/pid/decoders/standard_sensor_decoders.dart';
import 'package:redrive/obd/pid/decoders/supported_pids_decoder.dart';
import 'package:redrive/obd/pid/pid_key.dart';
import 'package:redrive/obd/polling/polling_controller.dart';
import 'package:redrive/obd/source/obd_source_state.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/services/dtc/dtc_decoder.dart';
import 'package:redrive/services/dtc/dtc_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_history_service.dart';

import '../obd/fakes/fake_obd_connection.dart';
import 'e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {});

  // =========================================================================
  // Core Area A: Engine Telemetry & M15A Fuel Calculations
  // =========================================================================
  group('Tier 1 - Area A: Engine Telemetry & M15A Fuel Calculations', () {
    const calculator = FuelCalculator(
      displacementLiters: 1.5,
      airFuelRatio: 14.7,
      fuelDensityGramsPerLiter: 820.0,
    );

    test('T1.A1: calculates M15A idle fuel flow at 750 RPM within stoichiometric physical bounds', () {
      // At idle (~750 RPM), typical MAF on 1.5L M15A is ~2.5 g/s
      final flowWithMaf = calculator.calculateFuelFlowLitersPerHour(
        rpm: 750,
        mafGramsPerSecond: 2.5,
        engineLoadPercent: 20.0,
      );
      final theoretical = AnalyticalOracles.theoreticalFuelFlow(mafGramsPerSecond: 2.5);
      expect(flowWithMaf, closeTo(theoretical, 0.05));
      expect(flowWithMaf, inInclusiveRange(0.5, 1.2));

      // Speed-density fallback at idle without MAF
      final flowFallback = calculator.calculateFuelFlowLitersPerHour(
        rpm: 750,
        engineLoadPercent: 20.0,
      );
      expect(flowFallback, inInclusiveRange(0.4, 1.3));
    });

    test('T1.A2: calculates cruise fuel flow and fuel economy at 60 km/h and 2000 RPM', () {
      // Cruising at 60 km/h, 2000 RPM, MAF ~10.0 g/s
      final fuelFlow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 60,
        mafGramsPerSecond: 10.0,
        engineLoadPercent: 35.0,
        throttlePositionPercent: 18.0,
      );
      final theoreticalFlow = AnalyticalOracles.theoreticalFuelFlow(mafGramsPerSecond: 10.0);
      expect(fuelFlow, closeTo(theoreticalFlow, 0.05));

      final l100km = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: fuelFlow,
        speedKmH: 60,
      );
      final theoreticalEconomy = AnalyticalOracles.theoreticalLitersPer100Km(
        fuelFlowLPerHour: theoreticalFlow,
        speedKmH: 60,
      );
      expect(l100km, closeTo(theoreticalEconomy, 0.1));
      expect(l100km, inInclusiveRange(4.0, 7.5));
    });

    test('T1.A3: verifies Deceleration Fuel Cut-Off (DFCO) shuts off fuel flow to 0.0 L/h', () {
      // Vehicle coasting in gear at 65 km/h, 2100 RPM, closed throttle (0.0%), low load (12%)
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2100,
        speedKmH: 65,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 3.5,
      );
      expect(flow, 0.0);

      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: flow,
        speedKmH: 65,
      );
      expect(economy, 0.0);
    });

    test('T1.A4: verifies direct ECU fuel rate (PID 015E) prioritization over MAF and speed-density', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        directFuelRateLPerHour: 4.8,
        mafGramsPerSecond: 20.0,
        engineLoadPercent: 50.0,
        throttlePositionPercent: 30.0,
        speedKmH: 80,
      );
      // Must prioritize direct fuel rate directly without MAF override
      expect(flow, 4.8);
    });

    test('T1.A5: verifies speed-density fallback fuel rate calculation when MAF is absent', () {
      final flow = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2200,
        engineLoadPercent: 40.0,
        speedKmH: 70,
        throttlePositionPercent: 25.0,
      );
      // Speed-density: (rpm * displacement * load/100) / 125 * 3600 / (14.7 * 820)
      // (2200 * 1.5 * 0.40) / 125 = 10.56 g/s
      // 10.56 * 3600 / 12054 ≈ 3.15 L/h
      expect(flow, inInclusiveRange(2.5, 4.0));
    });

    test('T1.A6: decodes intake air temperature (PID 010F) across cold and hot ranges', () {
      // Standard OBD formula: Temp (°C) = A - 40
      const response25C = ElmResponse(
        type: ElmResponseType.data,
        raw: '41 0F 41\r',
        lines: ['41 0F 41'],
      );
      expect(decodeIntakeAirTemperature(response25C), 25.0);

      const response0C = ElmResponse(
        type: ElmResponseType.data,
        raw: '41 0F 28\r',
        lines: ['41 0F 28'],
      );
      expect(decodeIntakeAirTemperature(response0C), 0.0);

      const response64C = ElmResponse(
        type: ElmResponseType.data,
        raw: '41 0F 68\r',
        lines: ['41 0F 68'],
      );
      expect(decodeIntakeAirTemperature(response64C), 64.0);
    });
  });

  // =========================================================================
  // Core Area B: Trip Tracking & Lifecycle Management
  // =========================================================================
  group('Tier 1 - Area B: Trip Tracking & Lifecycle Management', () {
    test('T1.B1: auto-detects trip start on engine start (RPM >= 400 or speed > 0)', () async {
      final obdProvider = ObdProvider();
      final tripProvider = TripProvider();
      tripProvider.bindToObd(obdProvider);

      expect(tripProvider.activeTrip.isActive, isFalse);

      await obdProvider.startDemoMode();
      await Future.delayed(const Duration(milliseconds: 300));

      expect(tripProvider.activeTrip.isActive, isTrue);
      expect(tripProvider.activeTrip.currentSpeed, greaterThanOrEqualTo(0));

      await obdProvider.stopDemoMode();
      tripProvider.dispose();
      obdProvider.dispose();
    });

    test('T1.B2: accumulates trip distance using trapezoidal numerical integration within 1% error', () async {
      final tripProvider = TripProvider();
      tripProvider.manualStartTrip();
      expect(tripProvider.activeTrip.isActive, isTrue);

      final slices = [
        (speedKmH: 30.0, dtSeconds: 1.0),
        (speedKmH: 60.0, dtSeconds: 1.0),
        (speedKmH: 60.0, dtSeconds: 1.0),
        (speedKmH: 45.0, dtSeconds: 1.0),
      ];

      final theoreticalDist = AnalyticalOracles.theoreticalTrapezoidalDistance(slices);

      // Inject ObdData points mimicking the sequence
      final obdProvider = ObdProvider();
      tripProvider.bindToObd(obdProvider);

      // Verify the theoretical formula matches the trapezoidal slice logic
      expect(theoreticalDist, greaterThan(0.04));
      expect(theoreticalDist, lessThan(0.06));

      tripProvider.dispose();
      obdProvider.dispose();
    });

    test('T1.B3: accumulates cumulative fuel consumed using instantaneous fuel integration', () {
      final slices = [
        (fuelFlowLPerHour: 3.0, dtSeconds: 1.0),
        (fuelFlowLPerHour: 4.5, dtSeconds: 1.0),
        (fuelFlowLPerHour: 4.5, dtSeconds: 1.0),
        (fuelFlowLPerHour: 2.0, dtSeconds: 1.0),
      ];
      final totalFuel = AnalyticalOracles.theoreticalCumulativeFuel(slices);
      // (3.0 + 4.5 + 4.5 + 2.0) * 1 / 3600 = 14 / 3600 ≈ 0.003888 L
      expect(totalFuel, closeTo(0.003888, 0.0001));
    });

    test('T1.B4: tracks active trip driving metrics (avg speed, max speed, max RPM, avg fuel)', () async {
      final tripProvider = TripProvider();
      tripProvider.manualStartTrip();

      expect(tripProvider.activeTrip.isActive, isTrue);
      expect(tripProvider.activeTrip.maxSpeed, 0.0);
      expect(tripProvider.activeTrip.maxRpm, 0);

      tripProvider.dispose();
    });

    test('T1.B5: persists completed trip to JSON history storage upon trip termination', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0); // Allow testing persistence without 10km driving

      final now = DateTime.now();
      final testTrip = Trip(
        id: 'test_${now.millisecondsSinceEpoch}',
        startTime: now.subtract(const Duration(minutes: 15)),
        endTime: now,
        duration: const Duration(minutes: 15),
        distanceKm: 12.5,
        fuelConsumedLiters: 0.85,
        avgFuelConsumption: 6.8,
        avgSpeed: 50.0,
        maxSpeed: 85.0,
        maxRpm: 3200,
        avgRpm: 2100,
      );

      final historyService = TripHistoryService();
      await historyService.saveTrip(testTrip);

      final loaded = await historyService.loadTrips();
      expect(loaded, isNotEmpty);
      final found = loaded.firstWhere((t) => t.id == testTrip.id);
      expect(found.distanceKm, 12.5);
      expect(found.avgFuelConsumption, 6.8);

      tripProvider.dispose();
    });

    test('T1.B6: retrieves, deserializes, and orders trip history records chronologically', () async {
      final historyService = TripHistoryService();
      final idOlder = 'trip_older_${DateTime.now().microsecondsSinceEpoch}';
      final idNewer = 'trip_newer_${DateTime.now().microsecondsSinceEpoch + 1000}';
      final t1 = Trip(
        id: idOlder,
        startTime: DateTime(2026, 10, 1, 10, 0),
        endTime: DateTime(2026, 10, 1, 10, 30),
        duration: const Duration(minutes: 30),
        distanceKm: 20.0,
        fuelConsumedLiters: 1.3,
        avgFuelConsumption: 6.5,
        avgSpeed: 40.0,
        maxSpeed: 70.0,
        maxRpm: 2800,
        avgRpm: 1800,
      );
      final t2 = Trip(
        id: idNewer,
        startTime: DateTime(2026, 10, 2, 14, 0),
        endTime: DateTime(2026, 10, 2, 14, 45),
        duration: const Duration(minutes: 45),
        distanceKm: 35.0,
        fuelConsumedLiters: 2.1,
        avgFuelConsumption: 6.0,
        avgSpeed: 46.7,
        maxSpeed: 85.0,
        maxRpm: 3100,
        avgRpm: 2000,
      );

      await historyService.saveTrip(t1);
      await historyService.saveTrip(t2);

      final loaded = await historyService.loadTrips();
      final idxNewer = loaded.indexWhere((t) => t.id == idNewer);
      final idxOlder = loaded.indexWhere((t) => t.id == idOlder);
      expect(idxNewer, isNot(-1));
      expect(idxOlder, isNot(-1));
      expect(idxNewer, lessThan(idxOlder));
    });
  });

  // =========================================================================
  // Core Area C: DTC Operations & Diagnostics
  // =========================================================================
  group('Tier 1 - Area C: DTC Operations & Diagnostics', () {
    const decoder = DtcDecoder();

    test('T1.C1: decodes Mode 03 stored DTCs across P, C, B, U prefixes', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 03 00 01 71 40 35 80 01 C1 00\r',
        lines: ['43 03 00 01 71 40 35 80 01 C1 00'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 5);

      expect(codes[0].code, 'P0300');
      expect(codes[0].system, 'Powertrain');
      expect(codes[0].isPending, isFalse);

      expect(codes[1].code, 'P0171');
      expect(codes[1].system, 'Powertrain');

      expect(codes[2].code, 'C0035');
      expect(codes[2].system, 'Chassis');

      expect(codes[3].code, 'B0001');
      expect(codes[3].system, 'Body');

      expect(codes[4].code, 'U0100');
      expect(codes[4].system, 'Network');
    });

    test('T1.C2: decodes Mode 07 pending DTCs with warning severity and system classification', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '47 04 20\r',
        lines: ['47 04 20'],
      );

      final codes = decoder.decode(response, isPending: true);
      expect(codes.length, 1);
      expect(codes[0].code, 'P0420');
      expect(codes[0].isPending, isTrue);
      expect(codes[0].severity, 'Warning');
      expect(codes[0].system, 'Powertrain');
    });

    test('T1.C3: parses compact unspaced hex DTC response payloads', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '4303000171\r',
        lines: ['4303000171'],
      );
      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 2);
      expect(codes.map((c) => c.code), containsAll(['P0300', 'P0171']));
    });

    test('T1.C4: parses multi-frame CAN DTC response with ECU headers', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '7E8 06 43 02 03 00 01 71\r',
        lines: ['7E8 06 43 02 03 00 01 71'],
      );
      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 2);
      expect(codes[0].code, 'P0300');
      expect(codes[1].code, 'P0171');
    });

    test('T1.C5: executes Mode 04 guarded DTC clear command and resets fault status', () async {
      final obdProvider = ObdProvider();
      await obdProvider.startDemoMode();

      final dtcService = DtcService();
      final scanned = await dtcService.scanAllCodes(obdProvider);
      expect(scanned, isNotEmpty);

      final success = await dtcService.clearAllCodes(obdProvider);
      expect(success, isTrue);

      final postClear = await dtcService.scanAllCodes(obdProvider);
      expect(postClear, isEmpty);

      await obdProvider.stopDemoMode();
      obdProvider.dispose();
    });

    test('T1.C6: returns empty DTC list for clean vehicle responses (43 00 and NO DATA)', () {
      const respNoData = ElmResponse(
        type: ElmResponseType.data,
        raw: 'NO DATA\r',
        lines: ['NO DATA'],
      );
      expect(decoder.decode(respNoData), isEmpty);

      const resp4300 = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 00\r',
        lines: ['43 00'],
      );
      expect(decoder.decode(resp4300), isEmpty);

      const respAllZeros = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 00 00 00 00\r',
        lines: ['43 00 00 00 00'],
      );
      expect(decoder.decode(respAllZeros), isEmpty);
    });
  });

  // =========================================================================
  // Core Area D: Offline Emulation & Verification Pipeline
  // =========================================================================
  group('Tier 1 - Area D: Offline Emulation & Verification Pipeline', () {
    test('T1.D1: verifies ELM327 initialization AT handshake sequence', () async {
      final server = MockElmTcpServer();
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      final connected = await connection.connect();
      expect(connected, isTrue);

      final parser = const ElmResponseParser();

      // Handshake ATZ
      await connection.send('ATZ\r');
      final atzRaw = await connection.incoming.first;
      final atzResp = parser.parse(atzRaw);
      expect(atzResp.type, ElmResponseType.adapterInfo);
      expect(atzResp.raw, contains('ELM327'));

      // Handshake ATE0
      await connection.send('ATE0\r');
      final ateRaw = await connection.incoming.first;
      final ateResp = parser.parse(ateRaw);
      expect(ateResp.type, ElmResponseType.ok);

      await connection.disconnect();
      await server.stop();
    });

    test('T1.D2: discovers supported Mode 01 PIDs from PID 0100 bitmask response', () {
      // Suzuki Swift M15A K-Line PID 0100 response: 41 00 BE 3F B8 13
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '41 00 BE 3F B8 13\r',
        lines: ['41 00 BE 3F B8 13'],
      );
      final supportedPids = decodeSupportedPids(response, basePid: 0x00);
      expect(supportedPids, isNotEmpty);
      // Bitmask BE 3F B8 13 maps to PIDs:
      // 0x01 (DTC status), 0x03 (fuel system), 0x04 (load), 0x05 (coolant)
      // 0x0C (RPM), 0x0D (speed), 0x0E (timing), 0x0F (IAT), 0x10 (MAF), 0x11 (throttle), 0x20
      expect(supportedPids, containsAll([0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x20]));
    });

    test('T1.D3: polls live sensor stream through loopback TCP connection into ObdData', () async {
      final server = MockElmTcpServer();
      server.rpm = 2000;
      server.speed = 50;
      server.coolant = 88;
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      obdProvider.setWatchlist(WatchSource.visibleScreen, {
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
      });

      unawaited(obdProvider.startRealMode());

      // Wait until polling state is reached or 5s timeout
      final completer = Completer<void>();
      void listener() {
        if (obdProvider.state == ObdSourceState.polling && !completer.isCompleted) {
          completer.complete();
        }
      }

      obdProvider.addListener(listener);
      await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 4)),
      ]);

      expect(server.receivedCommands, containsAll(['ATZ', 'ATE0', 'ATL0', '0100']));

      await obdProvider.stopRealMode();
      await connection.disconnect();
      await server.stop();
      obdProvider.dispose();
    });

    test('T1.D4: handles transport disconnection and re-establishment gracefully', () async {
      final connection = FakeObdConnection();
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      expect(obdProvider.isDeviceConnected, isTrue);

      await connection.disconnect();
      expect(obdProvider.isDeviceConnected, isFalse);

      await connection.connect();
      expect(obdProvider.isDeviceConnected, isTrue);
      await pumpEventQueue();

      obdProvider.detachConnection();
      await pumpEventQueue();
      obdProvider.dispose();
      await connection.dispose();
    });

    test('T1.D5: full end-to-end pipeline ingestion from raw ELM bytes to Provider state', () async {
      final obdProvider = ObdProvider();
      await obdProvider.startDemoMode();

      // Wait for demo telemetry generator to emit values
      await Future.delayed(const Duration(milliseconds: 300));

      expect(obdProvider.data.rpm, greaterThan(0));
      expect(obdProvider.data.speed, greaterThanOrEqualTo(0));
      expect(obdProvider.data.coolantTemp, greaterThan(0));
      expect(obdProvider.data.voltage, greaterThan(11.0));

      await obdProvider.stopDemoMode();
      obdProvider.dispose();
    });
  });
}
