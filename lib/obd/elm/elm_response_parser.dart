import 'elm_response.dart';

class ElmResponseParser {
  const ElmResponseParser();

  static const Map<String, ElmResponseType> _exactTypes = {
    'OK': ElmResponseType.ok,
    'NO DATA': ElmResponseType.noData,
    'STOPPED': ElmResponseType.stopped,
    'UNABLE TO CONNECT': ElmResponseType.unableToConnect,

    'BUS INIT: ERROR': ElmResponseType.busError,
    'BUS ERROR': ElmResponseType.busError,
    'BUS BUSY': ElmResponseType.busError,
    'CAN ERROR': ElmResponseType.busError,

    'BUFFER FULL': ElmResponseType.adapterError,
    'DATA ERROR': ElmResponseType.adapterError,
    '<DATA ERROR': ElmResponseType.adapterError,
    'RX ERROR': ElmResponseType.adapterError,
    'FB ERROR': ElmResponseType.adapterError,
    'LV RESET': ElmResponseType.adapterError,

    '?': ElmResponseType.unknownCommand,
  };

  static final RegExp _adapterErrorCodePattern = RegExp(r'^ERR[0-9A-F]{2}$');
  static final RegExp _adapterVoltagePattern = RegExp(
    r'^\d+(?:\.\d+)?\s*V$',
    caseSensitive: false,
  );

  static bool _isObdDataLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;

    // 1. Unspaced pure hex (e.g. "44", "4300", "4100BE3FB813", "4303000171")
    if (RegExp(r'^(?:[0-9A-Fa-f]{2})+$').hasMatch(trimmed)) {
      return true;
    }

    // 2. Spaced tokens (can include 2-digit hex bytes, CAN headers like 7E8, or ISO-TP prefixes like 0:, 1:)
    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.isEmpty) return false;

    // Must contain at least one valid 2-digit hex byte to be an OBD data line
    final hasHexByte = tokens.any(
      (t) => RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t),
    );
    if (!hasHexByte) return false;

    return tokens.every((token) {
      if (RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(token)) return true;
      if (RegExp(r'^[0-9A-Fa-f]{3}$').hasMatch(token)) return true; // 11-bit CAN header (e.g. 7E8)
      if (RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(token)) return true; // 29-bit CAN header
      if (RegExp(r'^[0-9A-Fa-f]+:$').hasMatch(token)) return true; // ISO-TP frame prefix (0:, 1:, ...)
      return false;
    });
  }

  static bool _isSearchingLine(String line) {
    return line.toUpperCase().startsWith('SEARCHING');
  }

  static bool _isIgnoredStatusLine(String line) {
    final upper = line.toUpperCase().trim();
    if (upper.startsWith('SEARCHING')) {
      return true;
    }
    // Filter out successful or progress bus inits e.g. "BUS INIT: OK", "BUS INIT: ...OK", "BUS INIT: ..."
    // BUT preserve "BUS INIT: ERROR"
    if (upper.startsWith('BUS INIT') && !upper.contains('ERROR')) {
      return true;
    }
    // Filter out progress dots like "..." or "..OK"
    if (RegExp(r'^\.+(?:OK)?$', caseSensitive: false).hasMatch(upper)) {
      return true;
    }
    return false;
  }

  static bool _isAdapterInfoLine(String line) {
    final upper = line.toUpperCase().trim();
    if (upper.isEmpty) return false;
    return upper.contains("ELM") ||
        upper.contains("ICAR") ||
        upper.contains("VGATE") ||
        upper.contains("OBD") ||
        upper.contains("STN") ||
        upper.contains("VIECAR") ||
        upper.contains("KONNWEI") ||
        upper.contains("VEEPEAK") ||
        upper.contains("SCAN") ||
        upper.contains("CHIP") ||
        RegExp(r'V[0-9]+\.[0-9]+', caseSensitive: false).hasMatch(upper);
  }

  ElmResponse parse(String raw) {
    final lines = raw
        .replaceAll('>', '')
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final wasSearching = lines.any(_isSearchingLine);

    final responseLines = lines
        .where((line) => !_isIgnoredStatusLine(line))
        .toList(growable: false);

    if (responseLines.isNotEmpty) {
      final lastLine = responseLines.last.toUpperCase();
      final ElmResponseType? type = _exactTypes[lastLine];

      if (type != null) {
        return ElmResponse(
          type: type,
          raw: raw,
          lines: responseLines,
          wasSearching: wasSearching,
        );
      }

      if (_adapterErrorCodePattern.hasMatch(lastLine)) {
        return ElmResponse(
          type: ElmResponseType.adapterError,
          raw: raw,
          lines: responseLines,
          wasSearching: wasSearching,
        );
      }

      if (_isAdapterInfoLine(responseLines.last)) {
        return ElmResponse(
          type: ElmResponseType.adapterInfo,
          raw: raw,
          lines: responseLines,
          wasSearching: wasSearching,
        );
      }

      if (_adapterVoltagePattern.hasMatch(responseLines.last)) {
        return ElmResponse(
          type: ElmResponseType.adapterVoltage,
          raw: raw,
          lines: responseLines,
          wasSearching: wasSearching,
        );
      }

      if (responseLines.every(_isObdDataLine)) {
        return ElmResponse(
          type: ElmResponseType.data,
          raw: raw,
          lines: responseLines,
          wasSearching: wasSearching,
        );
      }
    }

    return ElmResponse(
      type: ElmResponseType.malformed,
      raw: raw,
      lines: responseLines,
      wasSearching: wasSearching,
    );
  }
}
