import '../../obd/elm/elm_response.dart';
import '../../models/dtc_code.dart';
import 'dtc_database.dart';

/// Decodes SAE J2012 Diagnostic Trouble Codes (DTCs) from Mode 03 / Mode 07 ELM responses.
class DtcDecoder {
  const DtcDecoder();

  /// Parses raw ELM response lines from Mode 03 or Mode 07.
  List<DtcCode> decode(ElmResponse response, {bool isPending = false}) {
    if (response.type != ElmResponseType.data || response.lines.isEmpty) {
      return const [];
    }

    final rawCodes = <String>{};

    for (final line in response.lines) {
      final clean = line.trim().toUpperCase();
      if (clean.isEmpty || clean == 'NO DATA' || clean == 'NODATA') continue;

      final expectedHeader = isPending ? '47' : '43';

      // 1. Spaced format (e.g. "43 03 00 01 71" or CAN "7E8 06 43 02 03 00 01 71")
      final tokens = clean.split(RegExp(r'\s+'));
      final headerIndex = tokens.indexOf(expectedHeader);
      if (headerIndex != -1) {
        var byteTokens = tokens.sublist(headerIndex + 1);
        // In CAN OBD-II with ECU headers (e.g. "7E8 06 43 02 ..."), the first byte is the DTC count
        if (headerIndex > 0 && byteTokens.isNotEmpty) {
          byteTokens = byteTokens.sublist(1);
        }
        for (int i = 0; i + 1 < byteTokens.length; i += 2) {
          final b1 = int.tryParse(byteTokens[i], radix: 16);
          final b2 = int.tryParse(byteTokens[i + 1], radix: 16);
          if (b1 == null || b2 == null || (b1 == 0 && b2 == 0)) continue;
          final code = _bytesToDtcString(b1, b2);
          if (code.isNotEmpty) rawCodes.add(code);
        }
        continue;
      }

      // 2. Compact hex format (e.g. "4303000171")
      final hexOnly = clean.replaceAll(RegExp(r'[^0-9A-F]'), '');
      final compactHeaderIdx = hexOnly.indexOf(expectedHeader);
      if (compactHeaderIdx != -1) {
        var payload = hexOnly.substring(compactHeaderIdx + 2);
        // If preceded by CAN ECU headers, first 2 hex chars are DTC count
        if (compactHeaderIdx > 0 && payload.length >= 2) {
          payload = payload.substring(2);
        }
        for (int i = 0; i + 3 < payload.length; i += 4) {
          final b1 = int.tryParse(payload.substring(i, i + 2), radix: 16);
          final b2 = int.tryParse(payload.substring(i + 2, i + 4), radix: 16);
          if (b1 == null || b2 == null || (b1 == 0 && b2 == 0)) continue;
          final code = _bytesToDtcString(b1, b2);
          if (code.isNotEmpty) rawCodes.add(code);
        }
      }
    }

    return rawCodes.map((c) => DtcDatabase.resolve(c, isPending: isPending)).toList();
  }

  /// Converts two OBD-II DTC bytes into a standard 5-character string (e.g. "P0300", "U0100").
  static String _bytesToDtcString(int b1, int b2) {
    final prefixType = (b1 >> 6) & 0x03;
    final prefix = switch (prefixType) {
      0 => 'P', // Powertrain
      1 => 'C', // Chassis
      2 => 'B', // Body
      3 => 'U', // Network
      _ => 'P',
    };

    final d2 = ((b1 >> 4) & 0x03).toString();
    final d3 = (b1 & 0x0F).toRadixString(16).toUpperCase();
    final d4 = ((b2 >> 4) & 0x0F).toRadixString(16).toUpperCase();
    final d5 = (b2 & 0x0F).toRadixString(16).toUpperCase();

    final code = '$prefix$d2$d3$d4$d5';
    // Ignore P0000
    if (code == 'P0000') return '';
    return code;
  }
}
