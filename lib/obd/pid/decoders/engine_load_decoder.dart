import '../../elm/elm_response.dart';

/// Decodes Calculated Engine Load (OBD-II PID 0104).
///
/// Formula: (A * 100) / 255
/// Returns engine load percentage from 0.0% to 100.0%.
double decodeEngineLoad(ElmResponse response) {
  if (response.type != ElmResponseType.data || response.lines.isEmpty) {
    throw const FormatException('Engine load response does not contain OBD data');
  }

  final bytes = response.lines.first.toUpperCase().split(RegExp(r'\s+'));

  if (bytes.length < 3) {
    throw FormatException(
      'Engine load response expected at least 3 bytes, got ${bytes.length}',
    );
  }

  if (bytes[0] != '41' || bytes[1] != '04') {
    throw FormatException(
      'Engine load response expected header 41 04, got ${bytes[0]} ${bytes[1]}',
    );
  }

  final a = int.parse(bytes[2], radix: 16);
  return (a * 100.0) / 255.0;
}
