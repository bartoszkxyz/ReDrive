import '../../elm/elm_response.dart';

List<String> _extractBytes(ElmResponse response, String expectedPid, int minBytes) {
  if (response.type != ElmResponseType.data || response.lines.isEmpty) {
    throw FormatException('PID $expectedPid response does not contain OBD data');
  }

  final bytes = response.lines.first.toUpperCase().split(RegExp(r'\s+'));
  if (bytes.length < minBytes) {
    throw FormatException(
      'PID $expectedPid response expected at least $minBytes bytes, got ${bytes.length}',
    );
  }

  if (bytes[0] != '41' || bytes[1] != expectedPid) {
    throw FormatException(
      'PID $expectedPid response expected header 41 $expectedPid, got ${bytes[0]} ${bytes[1]}',
    );
  }

  return bytes;
}

/// Decodes Intake Air Temperature (OBD-II PID 010F).
/// Formula: A - 40 (°C)
double decodeIntakeAirTemperature(ElmResponse response) {
  final bytes = _extractBytes(response, '0F', 3);
  final a = int.parse(bytes[2], radix: 16);
  return (a - 40).toDouble();
}

/// Decodes Intake Manifold Absolute Pressure (OBD-II PID 010B).
/// Formula: A (kPa)
double decodeIntakeManifoldPressure(ElmResponse response) {
  final bytes = _extractBytes(response, '0B', 3);
  final a = int.parse(bytes[2], radix: 16);
  return a.toDouble();
}

/// Decodes Timing Advance (OBD-II PID 010E).
/// Formula: (A / 2) - 64 (°)
double decodeTimingAdvance(ElmResponse response) {
  final bytes = _extractBytes(response, '0E', 3);
  final a = int.parse(bytes[2], radix: 16);
  return (a / 2.0) - 64.0;
}

/// Decodes Short Term Fuel Trim - Bank 1 (OBD-II PID 0106).
/// Formula: (A - 128) * 100 / 128 (%)
double decodeShortTermFuelTrim1(ElmResponse response) {
  final bytes = _extractBytes(response, '06', 3);
  final a = int.parse(bytes[2], radix: 16);
  return ((a - 128) * 100.0) / 128.0;
}

/// Decodes Long Term Fuel Trim - Bank 1 (OBD-II PID 0107).
/// Formula: (A - 128) * 100 / 128 (%)
double decodeLongTermFuelTrim1(ElmResponse response) {
  final bytes = _extractBytes(response, '07', 3);
  final a = int.parse(bytes[2], radix: 16);
  return ((a - 128) * 100.0) / 128.0;
}

/// Decodes Fuel Rail Pressure (OBD-II PID 010A).
/// Formula: A * 3 (kPa)
double decodeFuelPressure(ElmResponse response) {
  final bytes = _extractBytes(response, '0A', 3);
  final a = int.parse(bytes[2], radix: 16);
  return (a * 3.0).toDouble();
}

/// Decodes Fuel Tank Level Input (OBD-II PID 012F).
/// Formula: (A * 100) / 255 (%)
double decodeFuelTankLevel(ElmResponse response) {
  final bytes = _extractBytes(response, '2F', 3);
  final a = int.parse(bytes[2], radix: 16);
  return (a * 100.0) / 255.0;
}

/// Decodes Absolute Barometric Pressure (OBD-II PID 0133).
/// Formula: A (kPa)
double decodeBarometricPressure(ElmResponse response) {
  final bytes = _extractBytes(response, '33', 3);
  final a = int.parse(bytes[2], radix: 16);
  return a.toDouble();
}

/// Decodes Control Module Voltage (OBD-II PID 0142).
/// Formula: ((256 * A) + B) / 1000 (V)
double decodeControlModuleVoltage(ElmResponse response) {
  final bytes = _extractBytes(response, '42', 4);
  final a = int.parse(bytes[2], radix: 16);
  final b = int.parse(bytes[3], radix: 16);
  return ((256.0 * a) + b) / 1000.0;
}

/// Decodes Ambient Air Temperature (OBD-II PID 0146).
/// Formula: A - 40 (°C)
double decodeAmbientAirTemperature(ElmResponse response) {
  final bytes = _extractBytes(response, '46', 3);
  final a = int.parse(bytes[2], radix: 16);
  return (a - 40).toDouble();
}

/// Decodes Engine Oil Temperature (OBD-II PID 015C).
/// Formula: A - 40 (°C)
double decodeEngineOilTemperature(ElmResponse response) {
  final bytes = _extractBytes(response, '5C', 3);
  final a = int.parse(bytes[2], radix: 16);
  return (a - 40).toDouble();
}

/// Decodes Run Time Since Engine Start (OBD-II PID 011F).
/// Formula: (256 * A) + B (seconds)
double decodeRunTimeSinceStart(ElmResponse response) {
  final bytes = _extractBytes(response, '1F', 4);
  final a = int.parse(bytes[2], radix: 16);
  final b = int.parse(bytes[3], radix: 16);
  return ((256.0 * a) + b).toDouble();
}
