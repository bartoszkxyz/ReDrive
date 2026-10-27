import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/obd/connection/tcp_obd_connection.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/providers/trip_provider.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';
import 'package:obdrive/services/settings/app_preferences.dart';
import 'package:obdrive/services/trip/fuel_calculator.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';

import '../e2e/e2e_harness.dart';

/// Specialized loopback TCP server for Tier 5 adversarial stress testing.
///
/// Simulates Suzuki Swift 3 M15A ELM327 adapter with dynamic sensor state,
/// controllable socket termination, Mode 03/07 DTCs, Mode 04 clearing, and PID responses.
class AdversarialElmServer {
  ServerSocket? _server;
  Socket? _clientSocket;
  final List<String> receivedCommands = [];

  int get port => _server?.port ?? 0;

  // Dynamic telemetry
  int rpm = 2000;
  int speed = 60;
  int coolant = 85;
  int iat = 25;
  double load = 35.0;
  double throttle = 25.0;
  double maf = 12.0;
  double? directFuelRate;

  // DTC state
  List<String> storedDtcs = ['P0300', 'P0171'];
  List<String> pendingDtcs = ['P0420'];
  bool clearReceived = false;
  int clearCallCount = 0;

  String _rxBuffer = '';

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      _clientSocket = socket;
      socket.listen(
        (Uint8List data) {
          final text = String.fromCharCodes(data);
          _rxBuffer += text;

          while (_rxBuffer.contains('\r') || _rxBuffer.contains('\n')) {
            final newlineIdx = _rxBuffer.indexOf(RegExp(r'[\r\n]'));
            final cmd = _rxBuffer.substring(0, newlineIdx).trim().toUpperCase();
            _rxBuffer = _rxBuffer.substring(newlineIdx + 1);

            if (cmd.isEmpty) continue;
            receivedCommands.add(cmd);
            _handleCommand(cmd, socket);
          }
        },
        onError: (_) {},
        onDone: () {
          _clientSocket = null;
        },
      );
    });
  }

  int simulatedDelayMs = 10;

  void _handleCommand(String cmd, Socket socket) async {
    if (simulatedDelayMs > 0 && !cmd.startsWith('AT')) {
      await Future<void>.delayed(Duration(milliseconds: simulatedDelayMs));
    }
    void reply(String response) {
      try {
        socket.add(Uint8List.fromList(response.codeUnits));
      } catch (_) {}
    }

    if (cmd == 'ATZ' || cmd == 'ATWS') {
      reply('ELM327 v2.3\r\n>');
    } else if (cmd == 'ATE0' || cmd == 'ATE1' || cmd == 'ATL0' || cmd == 'ATL1') {
      reply('OK\r\n>');
    } else if (cmd == 'ATS0' || cmd == 'ATS1' || cmd == 'ATH0' || cmd == 'ATH1') {
      reply('OK\r\n>');
    } else if (cmd.startsWith('ATSP') || cmd.startsWith('ATAT')) {
      reply('OK\r\n>');
    } else if (cmd == 'ATDP') {
      reply('ISO 14230-4 (KWP FAST)\r\n>');
    } else if (cmd == 'ATDPN') {
      reply('A5\r\n>');
    } else if (cmd == 'ATRV') {
      reply('14.1V\r\n>');
    } else if (cmd.startsWith('AT')) {
      reply('OK\r\n>');
    } else if (cmd == '0100') {
      reply('SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>');
    } else if (cmd == '0120') {
      reply('41 20 80 02 02 01\r\n>');
    } else if (cmd == '0140') {
      reply('41 40 44 04 00 14\r\n>');
    } else if (cmd == '0104') {
      final raw = (load * 255.0 / 100.0).round().clamp(0, 255);
      reply('41 04 ${raw.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '0105') {
      final raw = (coolant + 40).clamp(0, 255);
      reply('41 05 ${raw.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '010C') {
      final raw = (rpm * 4).clamp(0, 65535);
      final a = (raw >> 8) & 0xFF;
      final b = raw & 0xFF;
      reply('41 0C ${a.toRadixString(16).padLeft(2, '0').toUpperCase()} ${b.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '010D') {
      final raw = speed.clamp(0, 255);
      reply('41 0D ${raw.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '010F') {
      final raw = (iat + 40).clamp(0, 255);
      reply('41 0F ${raw.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '0110') {
      final raw = (maf * 100.0).round().clamp(0, 65535);
      final a = (raw >> 8) & 0xFF;
      final b = raw & 0xFF;
      reply('41 10 ${a.toRadixString(16).padLeft(2, '0').toUpperCase()} ${b.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '0111') {
      final raw = (throttle * 255.0 / 100.0).round().clamp(0, 255);
      reply('41 11 ${raw.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
    } else if (cmd == '015E') {
      if (directFuelRate != null && directFuelRate! > 0) {
        final raw = (directFuelRate! * 20.0).round().clamp(0, 65535);
        final a = (raw >> 8) & 0xFF;
        final b = raw & 0xFF;
        reply('41 5E ${a.toRadixString(16).padLeft(2, '0').toUpperCase()} ${b.toRadixString(16).padLeft(2, '0').toUpperCase()}\r\n>');
      } else {
        reply('NO DATA\r\n>');
      }
    } else if (cmd == '03') {
      if (storedDtcs.isEmpty) {
        reply('43 00\r\n>');
      } else {
        final hexPairs = storedDtcs.map(dtcToHexBytes).join(' ');
        reply('43 $hexPairs\r\n>');
      }
    } else if (cmd == '07') {
      if (pendingDtcs.isEmpty) {
        reply('47 00\r\n>');
      } else {
        final hexPairs = pendingDtcs.map(dtcToHexBytes).join(' ');
        reply('47 $hexPairs\r\n>');
      }
    } else if (cmd == '04') {
      clearReceived = true;
      clearCallCount++;
      storedDtcs.clear();
      pendingDtcs.clear();
      reply('44\r\n>');
    } else {
      reply('NO DATA\r\n>');
    }
  }

  /// Abruptly drops the connected client socket simulating a hardware/transport fault.
  void dropClient() {
    try {
      _clientSocket?.destroy();
    } catch (_) {}
    _clientSocket = null;
  }

  Future<void> stop() async {
    dropClient();
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppPreferences.resetCacheForTesting();
    tempDir = await Directory.systemTemp.createTemp('tier5_cross_module_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Tier 5: Cross-Module Integration Stress & Adversarial Hardening', () {
    test(
      'Stress 1: Active trip tracking concurrent with periodic DTC scans without telemetry drops or metric corruption',
      () async {
        final server = AdversarialElmServer()
          ..speed = 80
          ..rpm = 2400
          ..maf = 12.5
          ..load = 32.0
          ..throttle = 22.0
          ..coolant = 88
          ..iat = 28
          ..storedDtcs = ['P0300', 'P0171']
          ..pendingDtcs = ['P0420'];

        await server.start();

        final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
        await connection.connect();

        final obdProvider = ObdProvider();
        obdProvider.attachConnection(connection);

        final historyService = TripHistoryService(customDirectory: tempDir);
        final tripProvider = TripProvider(historyService: historyService);
        await tripProvider.initialized;
        await tripProvider.setMinTripDistanceKm(0.0);
        tripProvider.bindToObd(obdProvider);

        unawaited(obdProvider.startRealMode());

        // Wait for ECU polling connection
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline) && !obdProvider.isEcuConnected) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(obdProvider.isEcuConnected, isTrue);

        // Allow initial polling packets to flow and auto-start trip
        final tripStartDeadline = DateTime.now().add(const Duration(seconds: 3));
        while (DateTime.now().isBefore(tripStartDeadline) && !tripProvider.activeTrip.isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(tripProvider.activeTrip.isActive, isTrue);

        final dtcService = DtcService();

        // Perform multiple sequential DTC scans during continuous active polling
        for (var i = 0; i < 4; i++) {
          final codes = await dtcService.scanAllCodes(obdProvider);
          expect(codes, isNotEmpty);
          expect(codes.any((c) => c.code == 'P0300'), isTrue);
          expect(codes.any((c) => c.code == 'P0171'), isTrue);
          expect(codes.any((c) => c.code == 'P0420'), isTrue);

          // Brief delay between scans while polling continues
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        // Perform rapid concurrent DTC scans while polling is active
        final concurrentResults = await Future.wait([
          dtcService.scanAllCodes(obdProvider),
          dtcService.scanAllCodes(obdProvider),
        ]);

        for (final codes in concurrentResults) {
          expect(codes.map((c) => c.code).toSet(), containsAll({'P0300', 'P0171', 'P0420'}));
        }

        // Verify active trip tracking was not paused, reset, or corrupted
        final active = tripProvider.activeTrip;
        expect(active.isActive, isTrue);
        expect(active.distanceKm, greaterThan(0.0));
        expect(active.fuelConsumedLiters, greaterThan(0.0));

        // Verify numerical invariants: no NaN, no Inf, non-negative
        expect(active.distanceKm.isNaN, isFalse);
        expect(active.distanceKm.isInfinite, isFalse);
        expect(active.fuelConsumedLiters.isNaN, isFalse);
        expect(active.fuelConsumedLiters.isInfinite, isFalse);
        expect(active.avgFuelConsumption.isNaN, isFalse);
        expect(active.avgFuelConsumption.isInfinite, isFalse);
        expect(active.avgFuelConsumption, greaterThanOrEqualTo(0.0));
        expect(active.instantFuelLPerHour, greaterThan(0.0));
        expect(active.avgSpeed, greaterThan(0.0));

        // Verify ObdProvider telemetry was not stalled or dropped
        expect(obdProvider.data.speed, 80);
        expect(obdProvider.data.rpm, 2400);
        expect(obdProvider.data.maf, 12.5);

        // Teardown cleanly
        await obdProvider.stopRealMode();
        obdProvider.detachConnection();
        tripProvider.dispose();
        obdProvider.dispose();
        await connection.disconnect();
        connection.dispose();
        await server.stop();
      },
    );

    test(
      'Stress 2: Attempting Mode 04 clear while vehicle transitions from highway cruise into DFCO mountain coast-down, verifying clear is blocked, followed by complete vehicle stop where clear succeeds',
      () async {
        final server = AdversarialElmServer()
          ..speed = 100
          ..rpm = 2800
          ..throttle = 35.0
          ..load = 40.0
          ..maf = 16.0
          ..storedDtcs = ['P0300', 'P0171']
          ..pendingDtcs = ['P0420'];

        await server.start();

        final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
        await connection.connect();

        final obdProvider = ObdProvider();
        obdProvider.attachConnection(connection);

        final historyService = TripHistoryService(customDirectory: tempDir);
        final tripProvider = TripProvider(historyService: historyService);
        await tripProvider.initialized;
        await tripProvider.setMinTripDistanceKm(0.0);
        tripProvider.bindToObd(obdProvider);

        unawaited(obdProvider.startRealMode());

        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline) && !obdProvider.isEcuConnected) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(obdProvider.isEcuConnected, isTrue);

        final dtcService = DtcService();

        // ---------------------------------------------------------------------
        // Phase 1: Highway Cruise (speed = 100 km/h, RPM = 2800)
        // ---------------------------------------------------------------------
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(obdProvider.data.speed, 100);

        // Attempting Mode 04 clear while cruising must be blocked by motion safety check
        await expectLater(
          dtcService.clearAllCodes(obdProvider),
          throwsA(
            isA<DtcSafetyException>()
                .having((e) => e.speed, 'speed', 100)
                .having((e) => e.rpm, 'rpm', 2800),
          ),
        );
        expect(server.clearReceived, isFalse);

        // Verify DTCs are still fully intact
        final phase1Codes = await dtcService.scanAllCodes(obdProvider);
        expect(phase1Codes.map((c) => c.code).toSet(), containsAll({'P0300', 'P0171', 'P0420'}));

        // ---------------------------------------------------------------------
        // Phase 2: DFCO Mountain Coast-Down (speed = 70 km/h, RPM = 2200, throttle = 0%)
        // Injectors cut off (0.0 L/h), but vehicle is moving at high speed!
        // ---------------------------------------------------------------------
        server.speed = 70;
        server.rpm = 2200;
        server.throttle = 0.0;
        server.load = 8.0;
        server.maf = 0.5;

        // Allow telemetry loop to ingest the new driving state
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(obdProvider.data.speed, 70);
        expect(obdProvider.data.throttlePosition, 0.0);

        // Verify FuelCalculator computes strict 0.0 L/h during DFCO
        const calc = FuelCalculator(displacementLiters: 1.5);
        final dfcoFlow = calc.calculateFuelFlowLitersPerHour(
          speedKmH: 70,
          rpm: 2200,
          throttlePositionPercent: 0.0,
          engineLoadPercent: 8.0,
        );
        expect(dfcoFlow, 0.0);

        // Attempt Mode 04 clear during DFCO coast-down
        // Safety interlock MUST STILL TRIGGER: speed > 0 and RPM > 0 even though throttle is 0!
        await expectLater(
          dtcService.clearAllCodes(obdProvider),
          throwsA(
            isA<DtcSafetyException>()
                .having((e) => e.speed, 'speed', 70)
                .having((e) => e.rpm, 'rpm', 2200),
          ),
        );
        expect(server.clearReceived, isFalse);

        // Verify DTCs are still not cleared
        final phase2Codes = await dtcService.scanAllCodes(obdProvider);
        expect(phase2Codes, isNotEmpty);

        // ---------------------------------------------------------------------
        // Phase 3: Complete Vehicle Stop (speed = 0 km/h, engine off / RPM = 0)
        // Vehicle is safely parked, clear MUST SUCCEED
        // ---------------------------------------------------------------------
        server.speed = 0;
        server.rpm = 0;
        server.throttle = 0.0;
        server.load = 0.0;
        server.maf = 0.0;

        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(obdProvider.data.speed, 0);
        expect(obdProvider.data.rpm, 0);

        // Execute guarded clear when vehicle is stationary
        final clearSuccess = await dtcService.clearAllCodes(obdProvider);
        expect(clearSuccess, isTrue);
        expect(server.clearReceived, isTrue);

        // Verify DTCs are completely wiped on ECU and service
        final phase3Codes = await dtcService.scanAllCodes(obdProvider);
        expect(phase3Codes, isEmpty);
        expect(dtcService.lastScannedCodes, isEmpty);

        // Teardown
        await obdProvider.stopRealMode();
        obdProvider.detachConnection();
        tripProvider.dispose();
        obdProvider.dispose();
        await connection.disconnect();
        connection.dispose();
        await server.stop();
      },
    );

    test(
      'Stress 3: Abrupt transport disconnection during active trip and DTC scan, followed by reconnect, verifying trip state continuity and checkpoint recovery',
      () async {
        final server = AdversarialElmServer()
          ..speed = 60
          ..rpm = 2000
          ..maf = 10.0
          ..storedDtcs = ['P0300', 'P0171']
          ..pendingDtcs = [];

        await server.start();

        final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
        await connection.connect();

        final obdProvider = ObdProvider();
        obdProvider.attachConnection(connection);

        final historyService = TripHistoryService(customDirectory: tempDir);
        final tripProvider = TripProvider(historyService: historyService);
        await tripProvider.initialized;
        await tripProvider.setMinTripDistanceKm(0.0);
        tripProvider.bindToObd(obdProvider);

        unawaited(obdProvider.startRealMode());

        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline) && !obdProvider.isEcuConnected) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(obdProvider.isEcuConnected, isTrue);

        // Let trip start and accumulate initial distance
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(tripProvider.activeTrip.isActive, isTrue);

        // Explicitly write an in-flight checkpoint
        await tripProvider.saveCheckpoint();
        final checkpointData = await historyService.loadActiveCheckpoint();
        expect(checkpointData, isNotNull);
        expect(checkpointData!['distanceKm'], isNotNull);

        final distanceBeforeDrop = tripProvider.activeTrip.distanceKm;
        final fuelBeforeDrop = tripProvider.activeTrip.fuelConsumedLiters;

        // Abruptly drop the transport while simultaneously initiating a DTC scan
        final dtcService = DtcService();
        final scanFuture = dtcService.scanAllCodes(obdProvider);

        // Immediate transport severed
        server.dropClient();

        // The in-flight scan fails gracefully due to stream termination
        await expectLater(
          scanFuture,
          throwsA(anyOf(isA<DtcScanException>(), isA<StateError>(), isA<SocketException>())),
        );

        // Active trip state MUST NOT be lost during temporary disconnection window
        expect(tripProvider.activeTrip.isActive, isTrue);
        expect(tripProvider.activeTrip.distanceKm, greaterThanOrEqualTo(distanceBeforeDrop));
        expect(tripProvider.activeTrip.fuelConsumedLiters, greaterThanOrEqualTo(fuelBeforeDrop));

        // Reconnect to a new or restarted server session
        await server.stop();

        final server2 = AdversarialElmServer()
          ..speed = 70
          ..rpm = 2200
          ..maf = 11.5
          ..storedDtcs = ['P0300']
          ..pendingDtcs = [];
        await server2.start();

        final connection2 = TcpObdConnection(host: '127.0.0.1', port: server2.port);
        await connection2.connect();

        obdProvider.attachConnection(connection2);
        unawaited(obdProvider.startRealMode());

        final deadline2 = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline2) && !obdProvider.isEcuConnected) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(obdProvider.isEcuConnected, isTrue);

        // Telemetry resumes: distance must accumulate monotonically from where it left off
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(tripProvider.activeTrip.isActive, isTrue);
        expect(tripProvider.activeTrip.distanceKm, greaterThan(distanceBeforeDrop));
        expect(tripProvider.activeTrip.fuelConsumedLiters, greaterThan(fuelBeforeDrop));

        // Crash recovery test:
        // Now simulate app process kill while in-flight with accumulated checkpoint
        // Ensure distance meets min threshold (>= 0.10 km) for clean recovery
        final now = DateTime.now();
        tripProvider.processDataPoint(
          const ObdData(speed: 72, rpm: 2200, maf: 11.5),
          timestamp: now,
        );
        tripProvider.processDataPoint(
          const ObdData(speed: 72, rpm: 2200, maf: 11.5),
          timestamp: now.add(const Duration(seconds: 10)),
        );
        expect(tripProvider.activeTrip.distanceKm, greaterThanOrEqualTo(0.1));
        await tripProvider.saveCheckpoint();
        tripProvider.dispose();

        // Fresh TripProvider starts up after restart, pointing to the same history store
        final recoveredTripProvider = TripProvider(historyService: historyService);
        await recoveredTripProvider.initialized;

        //Interrupted trip is recovered into past trips cleanly
        final pastTrips = recoveredTripProvider.pastTrips;
        expect(pastTrips, isNotEmpty);
        final recoveredTrip = pastTrips.first;
        expect(recoveredTrip.distanceKm, greaterThan(0.0));
        expect(recoveredTrip.fuelConsumedLiters, greaterThan(0.0));
        expect(recoveredTrip.avgSpeed, greaterThan(0.0));
        expect(recoveredTrip.avgFuelConsumption, greaterThan(0.0));

        // Checkpoint file was consumed and cleaned up
        final postRecoveryCheckpoint = await historyService.loadActiveCheckpoint();
        expect(postRecoveryCheckpoint, isNull);

        // Teardown
        recoveredTripProvider.dispose();
        await obdProvider.stopRealMode();
        obdProvider.detachConnection();
        obdProvider.dispose();
        await connection2.disconnect();
        connection2.dispose();
        await connection.disconnect();
        connection.dispose();
        await server2.stop();
      },
    );

    test(
      'Stress 4: Extreme trip lifecycle with 0.1 km distance discard threshold filtering, verifying short trips persist cleanly',
      () async {
        final historyService = TripHistoryService(customDirectory: tempDir);

        // Verify default threshold in AppPreferences and TripProvider is 0.1 km
        final prefThreshold = await AppPreferences.getMinTripDistanceKm();
        expect(prefThreshold, 0.1);

        // ---------------------------------------------------------------------
        // Case 4.1: Sub-threshold trip (0.05 km < 0.10 km) must be discarded
        // ---------------------------------------------------------------------
        var currentTime = DateTime(2026, 10, 15, 8, 0, 0);
        final provider1 = TripProvider(
          historyService: historyService,
          clock: () => currentTime,
        );
        await provider1.initialized;
        expect(provider1.minTripDistanceKm, 0.1);

        provider1.manualStartTrip(currentTime);
        expect(provider1.activeTrip.isActive, isTrue);

        // Feed t0 sample, then t1 = t0 + 6s: 30 km/h for 6 seconds = 0.05 km
        provider1.processDataPoint(
          const ObdData(speed: 30, rpm: 1200, maf: 5.0, throttlePosition: 15.0),
          timestamp: currentTime,
        );
        currentTime = currentTime.add(const Duration(seconds: 6));
        provider1.processDataPoint(
          const ObdData(speed: 30, rpm: 1200, maf: 5.0, throttlePosition: 15.0),
          timestamp: currentTime,
        );
        expect(provider1.activeTrip.distanceKm, closeTo(0.05, 0.005));

        // End trip: must be discarded because distance < 0.1 km
        await provider1.manualEndTrip(currentTime);
        expect(provider1.activeTrip.isActive, isFalse);
        expect(provider1.pastTrips, isEmpty);

        final tripsAfterDiscard = await historyService.loadTrips();
        expect(tripsAfterDiscard, isEmpty);
        provider1.dispose();

        // ---------------------------------------------------------------------
        // Case 4.2: Short trip at or above threshold (0.12 km >= 0.10 km) must persist
        // ---------------------------------------------------------------------
        currentTime = DateTime(2026, 10, 15, 8, 10, 0);
        final provider2 = TripProvider(
          historyService: historyService,
          clock: () => currentTime,
        );
        await provider2.initialized;

        provider2.manualStartTrip(currentTime);
        expect(provider2.activeTrip.isActive, isTrue);

        // Feed t0 sample, then t1 = t0 + 12s: 36 km/h for 12 seconds = 0.12 km
        provider2.processDataPoint(
          const ObdData(speed: 36, rpm: 1500, maf: 7.5, throttlePosition: 18.0),
          timestamp: currentTime,
        );
        currentTime = currentTime.add(const Duration(seconds: 12));
        provider2.processDataPoint(
          const ObdData(speed: 36, rpm: 1500, maf: 7.5, throttlePosition: 18.0),
          timestamp: currentTime,
        );
        expect(provider2.activeTrip.distanceKm, closeTo(0.12, 0.005));

        // End trip: must persist because distance >= 0.1 km and duration >= 5s
        await provider2.manualEndTrip(currentTime);
        expect(provider2.activeTrip.isActive, isFalse);
        expect(provider2.pastTrips.length, 1);

        final savedTrip = provider2.pastTrips.first;
        expect(savedTrip.distanceKm, closeTo(0.12, 0.005));
        expect(savedTrip.duration.inSeconds, 12);
        expect(savedTrip.fuelConsumedLiters, greaterThan(0.0));
        expect(savedTrip.avgFuelConsumption, greaterThan(0.0));
        expect(savedTrip.avgSpeed, closeTo(36.0, 1.0));
        expect(savedTrip.maxSpeed, 36.0);
        expect(savedTrip.maxRpm, 1500);

        // Verify atomic JSON persistence survives fresh service instance reload
        final freshService = TripHistoryService(customDirectory: tempDir);
        final reloadedTrips = await freshService.loadTrips();
        expect(reloadedTrips.length, 1);
        expect(reloadedTrips.first.id, savedTrip.id);
        expect(reloadedTrips.first.distanceKm, savedTrip.distanceKm);
        provider2.dispose();

        // ---------------------------------------------------------------------
        // Case 4.3: Rapid succession of mixed short trips (alternating below / above 0.1 km)
        // ---------------------------------------------------------------------
        currentTime = DateTime(2026, 10, 15, 8, 30, 0);
        final provider3 = TripProvider(
          historyService: historyService,
          clock: () => currentTime,
        );
        await provider3.initialized;
        expect(provider3.pastTrips.length, 1); // already contains trip from Case 4.2

        // Trip A: 0.04 km (below 0.1) -> discard
        provider3.manualStartTrip(currentTime);
        provider3.processDataPoint(
          const ObdData(speed: 24, rpm: 1100, maf: 4.0),
          timestamp: currentTime,
        );
        currentTime = currentTime.add(const Duration(seconds: 6));
        provider3.processDataPoint(
          const ObdData(speed: 24, rpm: 1100, maf: 4.0),
          timestamp: currentTime,
        );
        await provider3.manualEndTrip(currentTime);
        expect(provider3.pastTrips.length, 1, reason: 'Trip A (0.04 km) must be discarded');

        // Trip B: 0.15 km (above 0.1) -> persist
        currentTime = currentTime.add(const Duration(minutes: 1));
        provider3.manualStartTrip(currentTime);
        provider3.processDataPoint(
          const ObdData(speed: 36, rpm: 1400, maf: 6.0),
          timestamp: currentTime,
        );
        currentTime = currentTime.add(const Duration(seconds: 15));
        provider3.processDataPoint(
          const ObdData(speed: 36, rpm: 1400, maf: 6.0),
          timestamp: currentTime,
        );
        await provider3.manualEndTrip(currentTime);
        expect(provider3.pastTrips.length, 2, reason: 'Trip B (0.15 km) must persist');

        // Trip C: 0.07 km (below 0.1) -> discard
        currentTime = currentTime.add(const Duration(minutes: 1));
        provider3.manualStartTrip(currentTime);
        provider3.processDataPoint(
          const ObdData(speed: 36, rpm: 1400, maf: 6.0),
          timestamp: currentTime,
        );
        currentTime = currentTime.add(const Duration(seconds: 7));
        provider3.processDataPoint(
          const ObdData(speed: 36, rpm: 1400, maf: 6.0),
          timestamp: currentTime,
        );
        await provider3.manualEndTrip(currentTime);
        expect(provider3.pastTrips.length, 2, reason: 'Trip C (0.07 km) must be discarded');

        // Trip D: 0.22 km (above 0.1) -> persist
        currentTime = currentTime.add(const Duration(minutes: 1));
        provider3.manualStartTrip(currentTime);
        provider3.processDataPoint(
          const ObdData(speed: 36, rpm: 1600, maf: 7.0),
          timestamp: currentTime,
        );
        currentTime = currentTime.add(const Duration(seconds: 22));
        provider3.processDataPoint(
          const ObdData(speed: 36, rpm: 1600, maf: 7.0),
          timestamp: currentTime,
        );
        await provider3.manualEndTrip(currentTime);
        expect(provider3.pastTrips.length, 3, reason: 'Trip D (0.22 km) must persist');

        // Total distance calculation matches persisted trips only
        final expectedTotal = provider3.pastTrips.fold(0.0, (acc, t) => acc + t.distanceKm);
        expect(provider3.totalDistance, closeTo(expectedTotal, 0.001));

        provider3.dispose();

        // ---------------------------------------------------------------------
        // Case 4.4: Crash checkpoint recovery respects 0.1 km threshold
        // ---------------------------------------------------------------------
        // Sub-case A: Checkpoint with 0.05 km (< 0.1 km) -> recovery ignores/clears it
        await historyService.saveActiveCheckpoint({
          'id': 'sub_threshold_checkpoint',
          'startTime': DateTime(2026, 10, 15, 9, 0, 0).toIso8601String(),
          'lastUpdated': DateTime(2026, 10, 15, 9, 0, 10).toIso8601String(),
          'durationSeconds': 10,
          'distanceKm': 0.05,
          'fuelConsumedLiters': 0.003,
          'avgFuelConsumption': 6.0,
          'avgSpeed': 18.0,
          'maxSpeed': 20.0,
          'maxRpm': 1200,
        });

        final recoveryProviderA = TripProvider(historyService: historyService);
        await recoveryProviderA.initialized;
        expect(recoveryProviderA.pastTrips.length, 3, reason: 'Sub-threshold checkpoint discarded');
        expect(await historyService.loadActiveCheckpoint(), isNull);
        recoveryProviderA.dispose();

        // Sub-case B: Checkpoint with 0.18 km (>= 0.1 km) -> recovery persists it
        await historyService.saveActiveCheckpoint({
          'id': 'valid_checkpoint_180m',
          'startTime': DateTime(2026, 10, 15, 9, 30, 0).toIso8601String(),
          'lastUpdated': DateTime(2026, 10, 15, 9, 30, 20).toIso8601String(),
          'durationSeconds': 20,
          'distanceKm': 0.18,
          'fuelConsumedLiters': 0.012,
          'avgFuelConsumption': 6.67,
          'avgSpeed': 32.4,
          'maxSpeed': 40.0,
          'maxRpm': 1800,
          'sampleCount': 20,
          'rpmSum': 32000,
        });

        final recoveryProviderB = TripProvider(historyService: historyService);
        await recoveryProviderB.initialized;
        expect(recoveryProviderB.pastTrips.length, 4, reason: 'Valid checkpoint recovered to past trips');
        final recovered = recoveryProviderB.pastTrips.firstWhere((t) => t.id == 'valid_checkpoint_180m');
        expect(recovered.distanceKm, 0.18);
        expect(recovered.avgRpm, 1600);
        expect(await historyService.loadActiveCheckpoint(), isNull);
        recoveryProviderB.dispose();
      },
    );
  });
}
