import '../../elm/elm_response.dart';

/// Decodes Absolute Throttle Position (OBD-II PID 0111).
///
/// Formula: (A * 100) / 255
/// Returns throttle position percentage from 0.0% to 100.0%.
double decodeThrottlePosition(ElmResponse response) {
  if (response.type != ElmResponseType.data || response.lines.isEmpty) {
    throw const FormatException('Throttle position response does not contain OBD data');
  }

  final bytes = response.lines.first.toUpperCase().split(RegExp(r'\s+'));

  if (bytes.length < 3) {
    throw FormatException(
      'Throttle position response expected at least 3 bytes, got ${bytes.length}',
    );
  }

  if (bytes[0] != '41' || bytes[1] != '11') {
    throw FormatException(
      'Throttle position response expected header 41 11, got ${bytes[0]} ${bytes[1]}',
    );
  }

  final a = int.parse(bytes[2], radix: 16);
  return (a * 100.0) / 255.0;
}
