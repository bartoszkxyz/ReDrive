import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Analytical calculation oracles providing mathematical ground truth.
class AnalyticalOracles {
  /// Theoretical fuel flow in L/h based on MAF, AFR, and density.
  static double theoreticalFuelFlow({
    required double mafGramsPerSecond,
    double airFuelRatio = 14.7,
    double fuelDensityGramsPerLiter = 820.0,
  }) {
    if (mafGramsPerSecond <= 0) return 0.0;
    final airGramsPerFuelLiter = airFuelRatio * fuelDensityGramsPerLiter;
    return (mafGramsPerSecond * 3600.0) / airGramsPerFuelLiter;
  }

  /// Theoretical fuel economy in L/100km.
  static double theoreticalLitersPer100Km({
    required double fuelFlowLPerHour,
    required double speedKmH,
  }) {
    if (speedKmH <= 0 || fuelFlowLPerHour <= 0) return 0.0;
    return ((fuelFlowLPerHour / speedKmH) * 100.0).clamp(0.0, 99.9);
  }

  /// Theoretical trapezoidal distance integration across speed time-slices.
  static double theoreticalTrapezoidalDistance(
    List<({double speedKmH, double dtSeconds})> slices, {
    double initialSpeed = 0.0,
  }) {
    double totalKm = 0.0;
    double lastSpeed = initialSpeed;
    for (final slice in slices) {
      final avgSpeed = (lastSpeed + slice.speedKmH) / 2.0;
      totalKm += (avgSpeed * slice.dtSeconds) / 3600.0;
      lastSpeed = slice.speedKmH;
    }
    return totalKm;
  }

  /// Theoretical cumulative fuel integration across fuel flow time-slices.
  static double theoreticalCumulativeFuel(
    List<({double fuelFlowLPerHour, double dtSeconds})> slices,
  ) {
    double totalLiters = 0.0;
    for (final slice in slices) {
      totalLiters += (slice.fuelFlowLPerHour * slice.dtSeconds) / 3600.0;
    }
    return totalLiters;
  }
}

/// Helper converting standard 5-character DTC string to 2-byte hex representation.
String dtcToHexBytes(String code) {
  if (code.length != 5) return '00 00';
  final prefix = code[0].toUpperCase();
  final d2 = int.tryParse(code[1], radix: 16) ?? 0;
  final d3 = int.tryParse(code[2], radix: 16) ?? 0;
  final d4 = int.tryParse(code[3], radix: 16) ?? 0;
  final d5 = int.tryParse(code[4], radix: 16) ?? 0;

  final prefixBits = switch (prefix) {
    'P' => 0,
    'C' => 1,
    'B' => 2,
    'U' => 3,
    _ => 0,
  };

  final b1 = (prefixBits << 6) | ((d2 & 0x03) << 4) | (d3 & 0x0F);
  final b2 = ((d4 & 0x0F) << 4) | (d5 & 0x0F);

  return '${b1.toRadixString(16).padLeft(2, '0').toUpperCase()} ${b2.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

/// In-process loopback TCP server emulating Suzuki Swift 3 M15A ELM327 v2.3 adapter.
class MockElmTcpServer {
  ServerSocket? _server;
  Socket? _clientSocket;
  final List<String> receivedCommands = [];

  int get port => _server?.port ?? 0;

  // Dynamic sensor state
  int rpm = 1500;
  int speed = 60;
  int coolant = 85;
  int iat = 25;
  double load = 35.0;
  double throttle = 25.0;
  double maf = 10.0;
  double? directFuelRate;

  // DTC state
  List<String> storedDtcs = ['P0300', 'P0171'];
  List<String> pendingDtcs = ['P0420'];
  bool clearReceived = false;

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

  void _handleCommand(String cmd, Socket socket) {
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
      reply('41 40 44 04 00 00\r\n>');
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
      storedDtcs.clear();
      pendingDtcs.clear();
      reply('44\r\n>');
    } else {
      reply('NO DATA\r\n>');
    }
  }

  Future<void> stop() async {
    try {
      await _clientSocket?.close();
    } catch (_) {}
    try {
      await _server?.close();
    } catch (_) {}
    _clientSocket = null;
    _server = null;
  }
}

/// Shared test environment fixtures.
class E2ETestFixture {
  static Future<void> setup() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  }

  static Future<void> tearDown() async {}
}
