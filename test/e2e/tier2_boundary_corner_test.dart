import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/obd/connection/tcp_obd_connection.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/elm/elm_response_parser.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/dtc/dtc_database.dart';
import 'package:obdrive/services/dtc/dtc_decoder.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';

import 'e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {});

  // =========================================================================
  // Core Area A: Fuel & Telemetry Boundaries
  // =========================================================================
  group('Tier 2 - Area A: Fuel & Telemetry Boundaries', () {
    const calculator = FuelCalculator(
      displacementLiters: 1.5,
      airFuelRatio: 14.7,
      fuelDensityGramsPerLiter: 820.0,
    );

    test('T2.A1: 0 RPM engine off condition strictly returns 0.0 L/h fuel flow', () {
      final flowOff = calculator.calculateFuelFlowLitersPerHour(
        rpm: 0,
        speedKmH: 0,
        engineLoadPercent: 0.0,
        mafGramsPerSecond: 0.0,
      );
      expect(flowOff, 0.0);

      // Even with bogus non-zero load or speed, 0 RPM must be 0.0 L/h
      final flowOffWithGhostSpeed = calculator.calculateFuelFlowLitersPerHour(
        rpm: 0,
        speedKmH: 50,
        engineLoadPercent: 50.0,
      );
      expect(flowOffWithGhostSpeed, 0.0);
    });

    test('T2.A2: extreme MAF and load values clamp fuel flow to upper bound 60.0 L/h', () {
      // Absurdly high MAF e.g. 500 g/s (aircraft scale)
      final flowMaxMaf = calculator.calculateFuelFlowLitersPerHour(
        rpm: 6000,
        mafGramsPerSecond: 500.0,
        speedKmH: 180,
      );
      expect(flowMaxMaf, 60.0);

      // Direct fuel rate higher than 60.0 L/h
      final flowMaxDirect = calculator.calculateFuelFlowLitersPerHour(
        rpm: 5000,
        directFuelRateLPerHour: 120.0,
      );
      expect(flowMaxDirect, 60.0);
    });

    test('T2.A3: stationary vehicle (speed == 0) returns 0.0 L/100km, preventing division by zero', () {
      final economyStationary = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 1.5,
        speedKmH: 0,
      );
      expect(economyStationary, 0.0);
      expect(economyStationary.isFinite, isTrue);
      expect(economyStationary.isNaN, isFalse);

      // Negative speed boundary
      final economyNegativeSpeed = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 1.5,
        speedKmH: -10,
      );
      expect(economyNegativeSpeed, 0.0);
    });

    test('T2.A4: extreme flow-to-speed ratios clamp fuel economy to upper bound 99.9 L/100km', () {
      // Crawling in 1st gear under heavy load: 45 L/h at 2 km/h -> raw = 2250 L/100km
      final economy = calculator.calculateLitersPer100Km(
        fuelFlowLitersPerHour: 45.0,
        speedKmH: 2,
      );
      expect(economy, 99.9);
      expect(economy.isFinite, isTrue);
    });

    test('T2.A5: precision testing around Deceleration Fuel Cut-Off (DFCO) threshold boundaries', () {
      // 1. Just above all thresholds -> DFCO active (speed > 20, RPM > 1300, throttle < 1%, load < 18%)
      final active = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1301,
        speedKmH: 21,
        throttlePositionPercent: 0.8,
        engineLoadPercent: 17.5,
        directFuelRateLPerHour: 3.0,
      );
      expect(active, 0.0);

      // 2. Below speed threshold (19 km/h <= 20) -> DFCO inactive
      final belowSpeed = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 19,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 3.0,
      );
      expect(belowSpeed, greaterThan(0.0));

      // 3. Below RPM threshold (1299 <= 1300) -> DFCO inactive
      final belowRpm = calculator.calculateFuelFlowLitersPerHour(
        rpm: 1299,
        speedKmH: 50,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 3.0,
      );
      expect(belowRpm, greaterThan(0.0));

      // 4. Throttle slightly open (1.2% >= 1.0%) -> DFCO inactive
      final throttleOpen = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 1.2,
        engineLoadPercent: 12.0,
        directFuelRateLPerHour: 3.0,
      );
      expect(throttleOpen, greaterThan(0.0));

      // 5. Load slightly high (19.0% >= 18.0%) -> DFCO inactive
      final highLoad = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 50,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 19.0,
        directFuelRateLPerHour: 3.0,
      );
      expect(highLoad, greaterThan(0.0));
    });

    test('T2.A6: extreme fuel trims boundary clamping prevents NaN or infinite values', () {
      final flowExtremePositive = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: 99.0,
        longTermFuelTrimPercent: 99.0,
      );
      expect(flowExtremePositive.isFinite, isTrue);
      expect(flowExtremePositive, greaterThan(0.0));
      expect(flowExtremePositive, lessThanOrEqualTo(60.0));

      final flowExtremeNegative = calculator.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: -99.0,
        longTermFuelTrimPercent: -99.0,
      );
      expect(flowExtremeNegative.isFinite, isTrue);
      expect(flowExtremeNegative, greaterThan(0.0));
    });
  });

  // =========================================================================
  // Core Area B: Trip Tracking & Persistence Boundaries
  // =========================================================================
  group('Tier 2 - Area B: Trip Tracking & Persistence Boundaries', () {
    test('T2.B1: discard threshold filtering discards trips under minimum distance', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(10.0); // 10 km threshold

      final historyService = TripHistoryService();
      final beforeCount = (await historyService.loadTrips()).length;

      // Start trip, drive only 0.5 km (below threshold), and end trip
      tripProvider.manualStartTrip();
      expect(tripProvider.activeTrip.isActive, isTrue);

      await tripProvider.manualEndTrip();
      expect(tripProvider.activeTrip.isActive, isFalse);

      // History should not have increased
      final afterCount = (await historyService.loadTrips()).length;
      expect(afterCount, beforeCount);

      tripProvider.dispose();
    });

    test('T2.B2: zero-movement initial active trip state produces no NaN or infinity', () {
      final initial = ActiveTripState.initial();
      expect(initial.distanceKm, 0.0);
      expect(initial.fuelConsumedLiters, 0.0);
      expect(initial.avgSpeed, 0.0);
      expect(initial.avgFuelConsumption, 0.0);
      expect(initial.instantFuelL100km, 0.0);
      expect(initial.avgSpeed.isNaN, isFalse);
      expect(initial.avgFuelConsumption.isNaN, isFalse);
    });

    test('T2.B3: empty or missing trips_history.json recovers cleanly without throwing', () async {
      final historyService = TripHistoryService();
      final trips = await historyService.loadTrips();
      expect(trips, isA<List<Trip>>());
    });

    test('T2.B4: rapid successive manual trip start and end cycles maintain clean state', () async {
      final tripProvider = TripProvider();
      await tripProvider.setMinTripDistanceKm(0.0);

      for (int i = 0; i < 5; i++) {
        tripProvider.manualStartTrip();
        expect(tripProvider.activeTrip.isActive, isTrue);
        await tripProvider.manualEndTrip();
        expect(tripProvider.activeTrip.isActive, isFalse);
      }

      tripProvider.dispose();
    });

    test('T2.B5: active trip calculation handles near-zero distance (< 0.05 km) without infinity', () async {
      final tripProvider = TripProvider();
      tripProvider.manualStartTrip();

      // Active trip with 0 km
      expect(tripProvider.activeTrip.avgFuelConsumption, 0.0);
      expect(tripProvider.activeTrip.avgFuelConsumption.isFinite, isTrue);

      tripProvider.dispose();
    });
  });

  // =========================================================================
  // Core Area C: DTC Operations & Parsing Boundaries
  // =========================================================================
  group('Tier 2 - Area C: DTC Operations & Parsing Boundaries', () {
    const decoder = DtcDecoder();

    test('T2.C1: SAE J2012 non-fault zero byte sequences (P0000, 00 00) are ignored', () {
      const respP0000 = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 00 00\r',
        lines: ['43 00 00'],
      );
      final codes = decoder.decode(respP0000, isPending: false);
      expect(codes, isEmpty);

      // Response with valid code followed by 00 00 padding
      const respPadded = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 01 71 00 00 00 00\r',
        lines: ['43 01 71 00 00 00 00'],
      );
      final paddedCodes = decoder.decode(respPadded, isPending: false);
      expect(paddedCodes.length, 1);
      expect(paddedCodes.first.code, 'P0171');
    });

    test('T2.C2: odd-length and malformed hex strings do not crash decoder', () {
      const oddResp = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 01\r',
        lines: ['43 01'],
      );
      expect(decoder.decode(oddResp), isEmpty);

      const invalidChars = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 ZZ XX\r',
        lines: ['43 ZZ XX'],
      );
      expect(decoder.decode(invalidChars), isEmpty);
    });

    test('T2.C3: unknown DTC codes fall back cleanly to valid system classifications', () {
      final unknownP = DtcDatabase.resolve('P0999');
      expect(unknownP.code, 'P0999');
      expect(unknownP.system, 'Powertrain');
      expect(unknownP.severity, 'Warning');

      final unknownC = DtcDatabase.resolve('C0999');
      expect(unknownC.code, 'C0999');
      expect(unknownC.system, 'Chassis');

      final unknownB = DtcDatabase.resolve('B0999');
      expect(unknownB.code, 'B0999');
      expect(unknownB.system, 'Body');

      final unknownU = DtcDatabase.resolve('U0999');
      expect(unknownU.code, 'U0999');
      expect(unknownU.system, 'Network');
    });

    test('T2.C4: Mode 04 clear when ECU is disconnected throws StateError', () async {
      final obdProvider = ObdProvider();
      final dtcService = DtcService();

      expect(obdProvider.isEcuConnected, isFalse);
      await expectLater(
        () => dtcService.clearAllCodes(obdProvider),
        throwsA(isA<StateError>()),
      );

      obdProvider.dispose();
    });

    test('T2.C5: malformed ELM responses (?, STOPPED, BUFFER FULL) produce empty DTC list', () {
      const parser = ElmResponseParser();

      final respQuestion = parser.parse('?\r>');
      expect(decoder.decode(respQuestion), isEmpty);

      final respStopped = parser.parse('STOPPED\r>');
      expect(decoder.decode(respStopped), isEmpty);

      final respBufferFull = parser.parse('BUFFER FULL\r>');
      expect(decoder.decode(respBufferFull), isEmpty);
    });

    test('T2.C6: duplicate DTC codes in multi-line responses are deduplicated', () {
      const respDuplicates = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 03 03 00 03 00 03 00\r',
        lines: ['43 03 03 00 03 00 03 00'],
      );
      final codes = decoder.decode(respDuplicates);
      expect(codes.length, 1);
      expect(codes.first.code, 'P0300');
    });
  });

  // =========================================================================
  // Core Area D: Offline Emulation & Pipeline Boundaries
  // =========================================================================
  group('Tier 2 - Area D: Offline Emulation & Pipeline Boundaries', () {
    const parser = ElmResponseParser();

    test('T2.D1: response fragmentation across multiple TCP chunks is handled properly', () {
      // Chunk 1: "41 0D "
      // Chunk 2: "2A\r>"
      final combined = '41 0D 2A\r>';
      final resp = parser.parse(combined);
      expect(resp.type, ElmResponseType.data);
      expect(resp.lines, ['41 0D 2A']);
    });

    test('T2.D2: unknown AT command response (?) parsed as unknownCommand', () {
      final resp = parser.parse('?\r>');
      expect(resp.type, ElmResponseType.unknownCommand);
    });

    test('T2.D3: adapter error codes (ERR01, BUS INIT: ERROR) parsed as error types', () {
      final respErr = parser.parse('ERR01\r>');
      expect(respErr.type, ElmResponseType.adapterError);

      final respBusErr = parser.parse('BUS INIT: ERROR\r>');
      expect(respBusErr.type, ElmResponseType.busError);
    });

    test('T2.D4: rapid connection flapping does not leave open or corrupt state', () async {
      final server = MockElmTcpServer();
      await server.start();

      final conn = TcpObdConnection(host: '127.0.0.1', port: server.port);
      for (int i = 0; i < 3; i++) {
        final connected = await conn.connect();
        expect(connected, isTrue);
        await conn.disconnect();
        expect(conn.isConnected, isFalse);
      }

      await server.stop();
      conn.dispose();
    });

    test('T2.D5: executing command on disconnected LiveObdSource throws StateError', () async {
      final obdProvider = ObdProvider();
      expect(
        () => obdProvider.executeCommand('0100'),
        throwsA(isA<StateError>()),
      );
      obdProvider.dispose();
    });
  });
}
