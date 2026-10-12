import '../../elm/elm_response.dart';

/// Decodes Mass Air Flow Sensor Rate (OBD-II PID 0110).
///
/// Formula: (256 * A + B) / 100
/// Returns intake air mass flow rate in grams per second (g/s).
double decodeMafAirFlowRate(ElmResponse response) {
  if (response.type != ElmResponseType.data || response.lines.isEmpty) {
    throw const FormatException('MAF response does not contain OBD data');
  }

  final bytes = response.lines.first.toUpperCase().split(RegExp(r'\s+'));

  if (bytes.length < 4) {
    throw FormatException(
      'MAF response expected at least 4 bytes, got ${bytes.length}',
    );
  }

  if (bytes[0] != '41' || bytes[1] != '10') {
    throw FormatException(
      'MAF response expected header 41 10, got ${bytes[0]} ${bytes[1]}',
    );
  }

  final a = int.parse(bytes[2], radix: 16);
  final b = int.parse(bytes[3], radix: 16);

  return (a * 256.0 + b) / 100.0;
}
