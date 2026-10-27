import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/obd/elm/elm_client.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/elm/elm_response_parser.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/dtc/dtc_decoder.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';
import 'package:obdrive/services/settings/app_preferences.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../obd/fakes/fake_obd_connection.dart';

class _MockObdProviderForDtc extends ObdProvider {
  ObdMode _mockMode = ObdMode.real;
  bool _mockEcuConnected = true;
  ObdData _mockData = const ObdData();
  String _mockExecuteResponse = '44\r>';
  int executeCallCount = 0;
  final List<String> executedCommands = [];
  Completer<void>? commandDelayCompleter;
  Future<ElmResponse> Function(String cmd)? customExecuteHandler;

  @override
  ObdMode get mode => _mockMode;

  @override
  bool get isEcuConnected => _mockEcuConnected;

  @override
  ObdData get data => _mockData;

  void setMockState({
    ObdMode mode = ObdMode.real,
    bool isEcuConnected = true,
    int speed = 0,
    int rpm = 0,
    String executeResponse = '44\r>',
  }) {
    _mockMode = mode;
    _mockEcuConnected = isEcuConnected;
    _mockData = _mockData.copyWith(speed: speed, rpm: rpm);
    _mockExecuteResponse = executeResponse;
    executeCallCount = 0;
    executedCommands.clear();
    commandDelayCompleter = null;
    customExecuteHandler = null;
  }

  @override
  Future<ElmResponse> executeCommand(String command) async {
    executedCommands.add(command);
    if (commandDelayCompleter != null) {
      await commandDelayCompleter!.future;
    }
    if (customExecuteHandler != null) {
      return customExecuteHandler!(command);
    }
    const parser = ElmResponseParser();
    if (command == '010D') {
      final hexSpeed = _mockData.speed.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
      return parser.parse('41 0D $hexSpeed\r>');
    }
    if (command == '010C') {
      final raw = (_mockData.rpm * 4).clamp(0, 65535);
      final a = (raw >> 8).toRadixString(16).padLeft(2, '0').toUpperCase();
      final b = (raw & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      return parser.parse('41 0C $a $b\r>');
    }
    executeCallCount++;
    return parser.parse(_mockExecuteResponse);
  }
}

Trip _buildTrip(String id, {DateTime? startTime, double distanceKm = 10.0, double fuelLiters = 0.8}) {
  final start = startTime ?? DateTime(2026, 10, 15, 8, 0);
  return Trip(
    id: id,
    startTime: start,
    endTime: start.add(const Duration(minutes: 15)),
    duration: const Duration(minutes: 15),
    distanceKm: distanceKm,
    fuelConsumedLiters: fuelLiters,
    avgFuelConsumption: distanceKm > 0 ? (fuelLiters / distanceKm) * 100.0 : 0.0,
    avgSpeed: 40.0,
    maxSpeed: 70.0,
    maxRpm: 2500,
    avgRpm: 1800,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // 1. Fuel Calculation Under Extreme Load, Negative MAF, Sensor NaN/Infinity
  // ---------------------------------------------------------------------------
  group('1. Fuel Calculation Adversarial Hardening', () {
    const calc = FuelCalculator(
      displacementLiters: 1.5,
      airFuelRatio: 14.7,
      fuelDensityGramsPerLiter: 820.0,
    );

    test('1.1: Engine off (RPM <= 0) strictly returns 0.0 L/h regardless of other sensors', () {
      expect(calc.calculateFuelFlowLitersPerHour(rpm: 0, mafGramsPerSecond: 50.0, directFuelRateLPerHour: 30.0), 0.0);
      expect(calc.calculateFuelFlowLitersPerHour(rpm: -500, mafGramsPerSecond: 20.0, engineLoadPercent: 80.0), 0.0);
      expect(calc.calculateFuelFlowLitersPerHour(rpm: -1), 0.0);
    });

    test('1.2: Negative or zero MAF falls back cleanly to speed-density fallback with finite output', () {
      final negativeMafFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: -15.0,
        engineLoadPercent: 40.0,
      );
      final zeroMafFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 0.0,
        engineLoadPercent: 40.0,
      );
      final nullMafFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: null,
        engineLoadPercent: 40.0,
      );

      expect(negativeMafFlow, isPositive);
      expect(negativeMafFlow.isFinite, isTrue);
      expect(negativeMafFlow, inInclusiveRange(0.0, 60.0));
      expect(negativeMafFlow, equals(nullMafFlow));
      expect(zeroMafFlow, equals(nullMafFlow));
    });

    test('1.3: Extreme load values (-500% to +10000%) clamped safely into [0.0, 60.0]', () {
      final underLoad = calc.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        engineLoadPercent: -500.0,
      );
      expect(underLoad, inInclusiveRange(0.0, 60.0));
      expect(underLoad.isFinite, isTrue);

      final overLoad = calc.calculateFuelFlowLitersPerHour(
        rpm: 6000,
        engineLoadPercent: 10000.0,
      );
      expect(overLoad, inInclusiveRange(0.0, 60.0));
      // Load is clamped to [10.0, 100.0]%, so at 6000 RPM, 100% load yields ~21.5 L/h
      expect(overLoad, closeTo(21.5, 0.5));

      // Direct fuel rate or extreme MAF clamps strictly to 60.0 L/h
      final extremeDirect = calc.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        directFuelRateLPerHour: 100.0,
      );
      expect(extremeDirect, equals(60.0));

      final extremeMaf = calc.calculateFuelFlowLitersPerHour(
        rpm: 2500,
        mafGramsPerSecond: 500.0,
      );
      expect(extremeMaf, equals(60.0));
    });

    test('1.4: Extreme fuel trims (-300% to +500%) clamped within multiplier range [0.5, 1.5]', () {
      final normalFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: 0.0,
        longTermFuelTrimPercent: 0.0,
      );

      final richClampFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: -150.0,
        longTermFuelTrimPercent: -150.0,
      );
      expect(richClampFlow, closeTo(normalFlow * 0.5, 1e-4));

      final leanClampFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: 250.0,
        longTermFuelTrimPercent: 250.0,
      );
      expect(leanClampFlow, closeTo(normalFlow * 1.5, 1e-4));
    });

    test('1.5: NaN and Infinity clamping in FuelCalculator yields finite bounded results', () {
      // NaN MAF skips Tier 2 and falls back to speed-density
      final nanMafFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: double.nan,
        engineLoadPercent: 30.0,
      );
      expect(nanMafFlow.isNaN, isFalse);
      expect(nanMafFlow.isFinite, isTrue);
      expect(nanMafFlow, inInclusiveRange(0.0, 60.0));

      // Infinite direct fuel rate clamped to 60.0
      final infDirectFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        directFuelRateLPerHour: double.infinity,
      );
      expect(infDirectFlow, equals(60.0));

      // Negative infinite direct fuel rate skipped and falls back
      final negInfDirectFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        directFuelRateLPerHour: double.negativeInfinity,
        mafGramsPerSecond: 10.0,
      );
      expect(negInfDirectFlow.isFinite, isTrue);
      expect(negInfDirectFlow, inInclusiveRange(0.0, 60.0));

      // NaN trims clamped to upper bound
      final nanTrimFlow = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        mafGramsPerSecond: 10.0,
        shortTermFuelTrimPercent: double.nan,
      );
      expect(nanTrimFlow.isNaN, isFalse);
      expect(nanTrimFlow.isFinite, isTrue);
      expect(nanTrimFlow, inInclusiveRange(0.0, 60.0));

      // Fuel economy with NaN/Infinity
      expect(calc.calculateLitersPer100Km(fuelFlowLitersPerHour: double.nan, speedKmH: 60), equals(99.9));
      expect(calc.calculateLitersPer100Km(fuelFlowLitersPerHour: double.infinity, speedKmH: 60), equals(99.9));
      expect(calc.calculateLitersPer100Km(fuelFlowLitersPerHour: 5.0, speedKmH: 0), equals(0.0));
      expect(calc.calculateLitersPer100Km(fuelFlowLitersPerHour: -2.0, speedKmH: 60), equals(0.0));
      expect(calc.calculateLitersPer100Km(fuelFlowLitersPerHour: 50.0, speedKmH: -10), equals(0.0));
    });

    test('1.6: Boundary DFCO transitions strictly conform to physical engine parameters', () {
      // Just below DFCO speed threshold (20 km/h) -> fuel not cut off
      final atSpeed20 = calc.calculateFuelFlowLitersPerHour(
        rpm: 2000,
        speedKmH: 20,
        throttlePositionPercent: 0.0,
        engineLoadPercent: 12.0,
      );
      expect(atSpeed20, isPositive);

      // Above DFCO speed (21 km/h) and RPM (1301) with closed throttle -> strictly 0.0
      final dfcoRelative = calc.calculateFuelFlowLitersPerHour(
        rpm: 1301,
        speedKmH: 21,
        throttlePositionPercent: 0.5,
        engineLoadPercent: 12.0,
      );
      expect(dfcoRelative, equals(0.0));

      // Swift absolute idle closed throttle range (10% - 14%) -> strictly 0.0
      final dfcoAbsolute = calc.calculateFuelFlowLitersPerHour(
        rpm: 1800,
        speedKmH: 50,
        throttlePositionPercent: 12.5,
        engineLoadPercent: 11.0,
      );
      expect(dfcoAbsolute, equals(0.0));

      // Slightly opened throttle (14.2%) -> DFCO exits
      final dfcoExited = calc.calculateFuelFlowLitersPerHour(
        rpm: 1800,
        speedKmH: 50,
        throttlePositionPercent: 14.2,
        engineLoadPercent: 11.0,
      );
      expect(dfcoExited, isPositive);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Trip Tracking Under Stress: Flapping, Corrupted UTF-8, Atomic Collisions
  // ---------------------------------------------------------------------------
  group('2. Trip Tracking Stress & Storage Hardening', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.setMinTripDistanceKm(0.1);
      await AppPreferences.setAutoTripEnabled(true);
      tempDir = Directory.systemTemp.createTempSync('tier5_trip_stress_');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('2.1: Rapid start/stop flapping (50 rapid transitions) maintains state invariants', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final provider = TripProvider(historyService: service);
      await provider.initialized;

      final startSimTime = DateTime(2026, 10, 15, 10, 0);

      // 50 rapid toggles between engine on and engine off
      for (var i = 0; i < 50; i++) {
        final t = startSimTime.add(Duration(milliseconds: i * 200));
        if (i % 2 == 0) {
          provider.processDataPoint(
            const ObdData(speed: 40, rpm: 2000, maf: 12.0, engineLoad: 30.0),
            timestamp: t,
          );
        } else {
          provider.processDataPoint(
            const ObdData(speed: 0, rpm: 0, maf: 0.0, engineLoad: 0.0),
            timestamp: t,
          );
        }
        final state = provider.activeTrip;
        expect(state.distanceKm.isNaN, isFalse);
        expect(state.fuelConsumedLiters.isNaN, isFalse);
        expect(state.avgFuelConsumption.isNaN, isFalse);
        expect(state.duration.isNegative, isFalse);
      }

      provider.dispose();
    });

    test('2.2: Corrupted non-UTF8 binary stream is quarantined and restored without crashing', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final trip1 = _buildTrip('trip_alpha', distanceKm: 15.0, fuelLiters: 1.1);
      await service.saveTrip(trip1);

      final primaryFile = File('${tempDir.path}/trips_history.json');
      expect(primaryFile.existsSync(), isTrue);

      // Overwrite primary file with invalid, non-decodable raw byte sequence
      final invalidUtf8Bytes = Uint8List.fromList([
        0xFF, 0xFE, 0xC0, 0xC1, 0x80, 0x81, 0xF5, 0xF8, 0x00, 0x1F, 0x7F
      ]);
      await primaryFile.writeAsBytes(invalidUtf8Bytes, flush: true);

      // Must not throw FormatException; should recover from mirror backup (.bak)
      final loaded = await service.loadTrips();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'trip_alpha');

      // Verify a timestamped corrupt file was preserved
      final corruptFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt_'))
          .toList();
      expect(corruptFiles, hasLength(1));
      expect(await corruptFiles.first.readAsBytes(), equals(invalidUtf8Bytes));
    });

    test('2.3: Salvages uncorrupted trip objects from partially damaged JSON payload', () async {
      final service = TripHistoryService(customDirectory: tempDir);
      final primaryFile = File('${tempDir.path}/trips_history.json');

      final damagedPayload = '''
[
  CORRUPTED_HEADER_STREAM_GARBAGE_WITHOUT_BALANCED_BRACE...
  {"id": "trip_salvaged_99", "startTime": "2026-10-15T09:00:00.000Z", "endTime": "2026-10-15T09:20:00.000Z", "durationSeconds": 1200, "distanceKm": 14.5, "fuelConsumedLiters": 1.05, "avgFuelConsumption": 7.24, "avgSpeed": 43.5, "maxSpeed": 72.0, "maxRpm": 2600, "avgRpm": 1850}
  CORRUPTED_TRAILING_STREAM_GARBAGE...
''';
      await primaryFile.writeAsString(damagedPayload, flush: true);

      // Remove .bak file so salvage path is exercised directly
      final bakFile = File('${tempDir.path}/trips_history.json.bak');
      if (bakFile.existsSync()) bakFile.deleteSync();

      final salvagedTrips = await service.loadTrips();
      expect(salvagedTrips, hasLength(1));
      expect(salvagedTrips.first.id, 'trip_salvaged_99');
      expect(salvagedTrips.first.distanceKm, 14.5);
    });

    test('2.4: Atomic file rename collision: 20 concurrent async writes preserve all trips', () async {
      final service = TripHistoryService(customDirectory: tempDir);

      // Launch 20 concurrent asynchronous saveTrip calls
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        final trip = _buildTrip('concurrent_trip_$i', distanceKm: 5.0 + i, fuelLiters: 0.3 + (i * 0.05));
        futures.add(service.saveTrip(trip));
      }

      await Future.wait(futures);

      final trips = await service.loadTrips();
      expect(trips, hasLength(20));
      final ids = trips.map((t) => t.id).toSet();
      for (var i = 0; i < 20; i++) {
        expect(ids.contains('concurrent_trip_$i'), isTrue, reason: 'Missing concurrent_trip_$i');
      }

      // Check primary JSON validity
      final primaryFile = File('${tempDir.path}/trips_history.json');
      final decoded = jsonDecode(await primaryFile.readAsString()) as List;
      expect(decoded.length, 20);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. DTC Parser Under ISO-TP Fragmentation, Mixed CAN IDs, Safety Race
  // ---------------------------------------------------------------------------
  group('3. DTC Parser & Stationary Safety Concurrency Hardening', () {
    const decoder = DtcDecoder();

    test('3.1: ISO-TP multi-frame fragmentation across tiny 1-byte chunks parses completely', () async {
      final connection = FakeObdConnection();
      final client = ElmClient(connection: connection);

      // Execute command '03'
      final executeFuture = client.execute('03');

      // Response to simulate: CAN multi-frame containing P0133, P0171, P0300, P0420
      const fullResponse = '7E8 10 0B 43 04 01 33 01 71\r\n7E8 21 03 00 04 20 00 00\r\n>';

      // Stream data in 1-byte chunks
      for (var i = 0; i < fullResponse.length; i++) {
        connection.emit(fullResponse[i]);
        await Future<void>.delayed(Duration.zero);
      }

      final response = await executeFuture;
      expect(response.type, ElmResponseType.data);

      final dtcs = decoder.decode(response);
      expect(dtcs.length, 4);
      expect(dtcs.map((d) => d.code), containsAll(['P0133', 'P0171', 'P0300', 'P0420']));

      await client.dispose();
      await connection.dispose();
    });

    test('3.2: Mixed interleaved CAN IDs (7E8 Engine + 7E9 Transmission) reassembled without collision', () {
      // 7E8 has P0171, P0300; 7E9 has P0700, P0720
      const interleavedFrames = [
        '7E8 10 09 43 02 01 71 03 00',
        '7E9 10 09 43 02 07 00 07 20',
        '7E8 21 00 00 00 00 00 00',
        '7E9 21 00 00 00 00 00 00',
      ];

      final dtcs = decoder.decode(interleavedFrames.join('\r\n'));
      expect(dtcs.length, 4);
      final codes = dtcs.map((d) => d.code).toSet();
      expect(codes, containsAll(['P0171', 'P0300', 'P0700', 'P0720']));
    });

    test('3.3: Adversarial malformed ISO-TP payloads discard cleanly without throwing', () {
      final malformedPayloads = [
        '7E8 21 01 71 03 00 00 00\r>', // Orphan consecutive frame without first frame
        '7E8 10 FF 43 01 01 71\r>', // First frame with huge length but truncated stream
        '7E8 10 05 43 10 01 71\r>', // Count byte 16, but only 1 DTC present
        '7E8 01 43 00\r>', // Short single frame
        '43 01 71\r>', // Truncated plain frame
        '', // Empty
        '?? INVALID HEX ??\r>',
      ];

      for (final payload in malformedPayloads) {
        expect(() => decoder.decode(payload), returnsNormally);
      }
    });

    test('3.4: Mode 04 stationary safety interlock blocks 15 concurrent calls while moving (04 never sent)', () async {
      final provider = _MockObdProviderForDtc();
      final service = DtcService();

      provider.setMockState(
        speed: 55, // Vehicle moving at 55 km/h
        rpm: 2100,
        executeResponse: '44\r>',
      );

      final futures = <Future<bool>>[];
      for (var i = 0; i < 15; i++) {
        futures.add(service.clearAllCodes(provider));
      }

      for (final future in futures) {
        await expectLater(
          future,
          throwsA(
            isA<DtcSafetyException>()
                .having((e) => e.speed, 'speed', 55)
                .having((e) => e.rpm, 'rpm', 2100),
          ),
        );
      }

      // Invariant: '04' was NEVER transmitted to the ECU
      expect(provider.executedCommands.contains('04'), isFalse);
      expect(provider.executeCallCount, 0);
    });

    test('3.5: Mode 04 deduplicates concurrent stationary calls so Mode 04 is sent exactly once', () async {
      final provider = _MockObdProviderForDtc();
      final service = DtcService();

      provider.setMockState(
        speed: 0,
        rpm: 0,
        executeResponse: '44\r>',
      );

      // Launch 15 concurrent calls to clearAllCodes while stationary
      final futures = List.generate(15, (_) => service.clearAllCodes(provider));
      final results = await Future.wait(futures);

      expect(results.every((r) => r == true), isTrue);
      // Invariant: Mode 04 deduplicated across in-flight requests, executed exactly once
      expect(provider.executeCallCount, 1);
      expect(provider.executedCommands.where((c) => c == '04').length, 1);
    });

    test('3.6: Fails closed when live sensor query returns error/timeout (04 never sent)', () async {
      final provider = _MockObdProviderForDtc();
      final service = DtcService();

      provider.setMockState(
        speed: 0,
        rpm: 0,
        executeResponse: 'BUS ERROR\r>',
      );

      // Force speed query 010D to return BUS ERROR
      provider.customExecuteHandler = (cmd) async {
        if (cmd == '010D') {
          return const ElmResponseParser().parse('BUS ERROR\r>');
        }
        return const ElmResponseParser().parse('44\r>');
      };

      final result = await service.clearAllCodes(provider);
      expect(result, isFalse, reason: 'Must fail closed when speed is unverifiable');
      expect(provider.executedCommands.contains('04'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Socket Emulator Stress: Rapid Reconnect & Pipelined Commands
  // ---------------------------------------------------------------------------
  group('4. Socket Emulator Stress & Protocol Pipeline', () {
    late Process emulatorProcess;
    late int emulatorPort;

    setUpAll(() async {
      // Find an available port
      final tempServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      emulatorPort = tempServer.port;
      await tempServer.close();

      // Launch tools/elm327_emulator.py
      emulatorProcess = await Process.start(
        'python3',
        ['tools/elm327_emulator.py', '--port', '$emulatorPort', '--delay', '0.0'],
      );

      // Wait until port is accepting connections
      var connected = false;
      for (var attempt = 0; attempt < 25; attempt++) {
        try {
          final s = await Socket.connect(InternetAddress.loopbackIPv4, emulatorPort, timeout: const Duration(milliseconds: 200));
          await s.close();
          connected = true;
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      expect(connected, isTrue, reason: 'tools/elm327_emulator.py failed to start on port $emulatorPort');
    });

    tearDownAll(() async {
      emulatorProcess.kill(ProcessSignal.sigkill);
      await emulatorProcess.exitCode;
    });

    test('4.1: Rapid successive TCP connect/disconnect cycles (15 cycles) execute without socket failure', () async {
      for (var i = 0; i < 15; i++) {
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, emulatorPort, timeout: const Duration(seconds: 2));
        socket.add(utf8.encode('ATZ\r'));
        await socket.flush();

        final completer = Completer<String>();
        var buffer = '';
        socket.listen((data) {
          buffer += utf8.decode(data);
          if (buffer.contains('>')) {
            if (!completer.isCompleted) completer.complete(buffer);
          }
        });

        final resp = await completer.future.timeout(const Duration(seconds: 2));
        expect(resp, contains('ELM327 v2.3'));
        await socket.close();
      }
    });

    test('4.2: Pipelined batch commands in single TCP packet receive all ordered responses and prompts', () async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, emulatorPort, timeout: const Duration(seconds: 2));

      // Batch 6 commands into a single TCP write
      const batch = 'ATE0\rATL0\r0100\r010C\r010D\r03\r';
      socket.add(utf8.encode(batch));
      await socket.flush();

      var rxBuffer = '';
      final completer = Completer<void>();

      socket.listen((data) {
        rxBuffer += utf8.decode(data);
        // Expect 6 prompt characters (one per command)
        final promptCount = RegExp(r'>').allMatches(rxBuffer).length;
        if (promptCount >= 6 && !completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future.timeout(const Duration(seconds: 3));

      expect(rxBuffer, contains('OK'));
      expect(rxBuffer, contains('41 00 BE 3F B8 13'));
      expect(rxBuffer, contains('41 0C'));
      expect(rxBuffer, contains('41 0D'));
      expect(rxBuffer, contains('43'));

      await socket.close();
    });

    test('4.3: Mode 03 / Mode 04 / Mode 07 lifecycle through live socket emulator', () async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, emulatorPort, timeout: const Duration(seconds: 2));

      var rxBuffer = '';
      Completer<String>? pendingCompleter;

      socket.listen((data) {
        rxBuffer += utf8.decode(data);
        if (rxBuffer.contains('>') && pendingCompleter != null && !pendingCompleter!.isCompleted) {
          final out = rxBuffer;
          rxBuffer = '';
          pendingCompleter!.complete(out);
        }
      });

      Future<String> sendAndRead(String cmd) async {
        pendingCompleter = Completer<String>();
        rxBuffer = '';
        socket.add(utf8.encode('$cmd\r'));
        await socket.flush();
        return pendingCompleter!.future.timeout(const Duration(seconds: 2));
      }

      // Query initial stored DTCs (should have P0171, P0300)
      final dtc03 = await sendAndRead('03');
      expect(dtc03, contains('43 02 01 71 03 00'));

      // Query initial pending DTCs (should have P0420)
      final dtc07 = await sendAndRead('07');
      expect(dtc07, contains('47 01 04 20'));

      // Clear all DTCs via Mode 04
      final clear04 = await sendAndRead('04');
      expect(clear04, contains('44'));

      // Verify stored DTCs are now 43 00
      final dtc03After = await sendAndRead('03');
      expect(dtc03After, contains('43 00'));

      // Verify pending DTCs are now 47 00
      final dtc07After = await sendAndRead('07');
      expect(dtc07After, contains('47 00'));

      await socket.close();
    });

    test('4.4: Concurrent dual-socket clients query telemetry concurrently without contention', () async {
      final client1 = await Socket.connect(InternetAddress.loopbackIPv4, emulatorPort, timeout: const Duration(seconds: 2));
      final client2 = await Socket.connect(InternetAddress.loopbackIPv4, emulatorPort, timeout: const Duration(seconds: 2));

      Future<String> query(Socket s, String cmd) async {
        final comp = Completer<String>();
        var buf = '';
        late StreamSubscription sub;
        sub = s.listen((data) {
          buf += utf8.decode(data);
          if (buf.contains('>')) {
            sub.cancel();
            comp.complete(buf);
          }
        });
        s.add(utf8.encode('$cmd\r'));
        await s.flush();
        return comp.future.timeout(const Duration(seconds: 2));
      }

      final f1 = query(client1, '010C');
      final f2 = query(client2, '010D');

      final r1 = await f1;
      final r2 = await f2;

      expect(r1, contains('41 0C'));
      expect(r2, contains('41 0D'));

      await client1.close();
      await client2.close();
    });
  });
}
