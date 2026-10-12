import '../../elm/elm_response.dart';

/// Decodes the supported PID bitmap from Mode 01 responses.
///
/// Supports standard range discovery:
/// - [basePid] = 0x00 for PIDs 0x01..0x20 (command '0100')
/// - [basePid] = 0x20 for PIDs 0x21..0x40 (command '0120')
/// - [basePid] = 0x40 for PIDs 0x41..0x60 (command '0140')
Set<int> decodeSupportedPids(ElmResponse response, {int basePid = 0x00}) {
  if (response.type != ElmResponseType.data || response.lines.isEmpty) {
    throw const FormatException(
      'Supported PID response does not contain OBD data',
    );
  }

  final bytes = response.lines.first.trim().split(RegExp(r'\s+'));

  if (bytes.length < 6) {
    throw const FormatException(
      'Supported PID response contains too few bytes',
    );
  }

  final expectedPid = basePid.toRadixString(16).padLeft(2, '0').toUpperCase();

  if (bytes[0] != '41' || bytes[1].toUpperCase() != expectedPid) {
    throw FormatException(
      'Invalid supported PID response: ${response.lines.first}',
    );
  }

  final bitmap = [
    int.parse(bytes[2], radix: 16),
    int.parse(bytes[3], radix: 16),
    int.parse(bytes[4], radix: 16),
    int.parse(bytes[5], radix: 16),
  ];

  final supported = <int>{};

  for (int position = 0; position < 32; position++) {
    final byteIndex = position ~/ 8;
    final positionInByte = position % 8;
    final bitIndex = 7 - positionInByte;

    final isSupported = ((bitmap[byteIndex] >> bitIndex) & 1) == 1;

    if (isSupported) {
      final pid = basePid + position + 1;
      supported.add(pid);
    }
  }

  return supported;
}
