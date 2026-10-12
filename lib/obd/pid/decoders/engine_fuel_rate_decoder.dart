import '../../elm/elm_response.dart';

/// Decodes Engine Fuel Rate (OBD-II PID 015E).
///
/// Formula: ((256 * A) + B) / 20  [or ((256 * A) + B) * 0.05]
/// Returns fuel flow rate in Liters per hour (L/h).
double decodeEngineFuelRate(ElmResponse response) {
  if (response.type != ElmResponseType.data || response.lines.isEmpty) {
    throw const FormatException('Engine fuel rate response does not contain OBD data');
  }

  final bytes = response.lines.first.toUpperCase().split(RegExp(r'\s+'));

  if (bytes.length < 4) {
    throw FormatException(
      'Engine fuel rate response expected at least 4 bytes, got ${bytes.length}',
    );
  }

  if (bytes[0] != '41' || bytes[1] != '5E') {
    throw FormatException(
      'Engine fuel rate response expected header 41 5E, got ${bytes[0]} ${bytes[1]}',
    );
  }

  final a = int.parse(bytes[2], radix: 16);
  final b = int.parse(bytes[3], radix: 16);

  return (a * 256.0 + b) / 20.0;
}
