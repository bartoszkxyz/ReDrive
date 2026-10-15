import '../../obd/elm/elm_response.dart';
import '../../models/dtc_code.dart';
import 'dtc_database.dart';

/// Decodes SAE J2012 Diagnostic Trouble Codes (DTCs) from Mode 03 / Mode 07 ELM responses.
class DtcDecoder {
  const DtcDecoder();

  /// Parses raw ELM response lines or raw hex strings from Mode 03 or Mode 07.
  List<DtcCode> decode(
    dynamic response, {
    bool isPending = false,
    String? serviceId,
  }) {
    List<String> lines;
    if (response is ElmResponse) {
      if (response.type != ElmResponseType.data || response.lines.isEmpty) {
        return const [];
      }
      lines = response.lines;
    } else if (response is String) {
      lines = response
          .replaceAll('>', '')
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(growable: false);
    } else {
      return const [];
    }

    final effectivePending =
        (serviceId == '47' || serviceId == '07') ? true : isPending;
    final expectedHeader = (serviceId == '43' || serviceId == '03')
        ? '43'
        : (effectivePending ? '47' : '43');

    final messages = _assembleMessages(lines, expectedHeader);
    final rawCodes = <String>{};
    for (final m in messages) {
      _extractCodes(m, rawCodes);
    }

    return rawCodes
        .map((c) => DtcDatabase.resolve(c, isPending: effectivePending))
        .toList();
  }

  static final RegExp _byteRe = RegExp(r'^[0-9A-F]{2}$');
  static final RegExp _indexRe = RegExp(r'^[0-9A-F]{1,2}:$');
  static final RegExp _canId11Re = RegExp(r'^7E[8-9A-F]$');
  static final RegExp _canId29Re = RegExp(r'^[0-9A-F]{8}$');
  static final RegExp _pureHexRe = RegExp(r'^[0-9A-F]+$');

  /// Reassembles per-frame lines into logical service messages. A header
  /// (43/47) is only ever recognised at the start of a message payload.
  List<_Msg> _assembleMessages(List<String> lines, String header) {
    final done = <_Msg>[];
    final activeCan = <String, _Msg>{};
    _Msg? activeIndexed;

    for (final line in lines) {
      final clean = line.trim().toUpperCase();
      if (clean.isEmpty) continue;
      var tokens = clean.split(RegExp(r'\s+'));

      // Compact hex (single pure-hex token, e.g. "4303000171").
      if (tokens.length == 1) {
        final t = tokens[0];
        if (_pureHexRe.hasMatch(t) && t.length >= 4 && t.startsWith(header)) {
          final bytes = <int>[];
          for (var i = 0; i + 1 < t.length; i += 2) {
            bytes.add(int.parse(t.substring(i, i + 2), radix: 16));
          }
          done.add(_Msg(bytes.sublist(1), countByte: null));
        }
        continue;
      }

      // ELM multi-line "N:" indexed (headers off, already reassembled).
      if (_indexRe.hasMatch(tokens[0])) {
        final index = int.parse(tokens[0].substring(0, tokens[0].length - 1),
            radix: 16);
        final bytes = _parseBytes(tokens.sublist(1));
        if (bytes == null) continue;
        if (index == 0) {
          if (bytes.isNotEmpty && bytes[0] == int.parse(header, radix: 16)) {
            activeIndexed = _Msg(bytes.sublist(1), countByte: true);
            done.add(activeIndexed);
          } else {
            activeIndexed = null;
          }
        } else if (activeIndexed != null) {
          activeIndexed.bytes.addAll(bytes);
        }
        continue;
      }

      // Raw CAN with headers (ATH1): "7E8 06 43 ..." / "18DAF110 06 43 ..."
      if (_canId11Re.hasMatch(tokens[0]) || _canId29Re.hasMatch(tokens[0])) {
        final id = tokens[0];
        final bytes = _parseBytes(tokens.sublist(1));
        if (bytes == null || bytes.isEmpty) continue;
        final headerByte = int.parse(header, radix: 16);
        if (bytes[0] == headerByte) {
          // No PCI byte shown (0x4x is not a valid ISO-TP PCI).
          final m = _Msg(bytes.sublist(1), countByte: true);
          done.add(m);
          activeCan[id] = m;
          continue;
        }
        final type = bytes[0] >> 4;
        if (type == 0) {
          final len = bytes[0] & 0x0F;
          final payload = bytes.sublist(1);
          final used = payload.length > len ? payload.sublist(0, len) : payload;
          activeCan.remove(id);
          if (used.isNotEmpty && used[0] == headerByte) {
            done.add(_Msg(used.sublist(1), countByte: true));
          }
        } else if (type == 1 && bytes.length >= 3) {
          final total = ((bytes[0] & 0x0F) << 8) | bytes[1];
          final payload = bytes.sublist(2);
          if (payload.isNotEmpty && payload[0] == headerByte) {
            final m = _Msg(payload.sublist(1), countByte: true)
              ..remaining = total - payload.length;
            done.add(m);
            activeCan[id] = m;
          } else {
            activeCan.remove(id);
          }
        } else if (type == 2) {
          final m = activeCan[id];
          if (m != null && m.remaining > 0) {
            final payload = bytes.sublist(1);
            final take =
                payload.length > m.remaining ? m.remaining : payload.length;
            m.bytes.addAll(payload.sublist(0, take));
            m.remaining -= take;
          }
        }
        continue;
      }

      // Plain line (headers off / K-Line), optionally with K-Line header.
      var kHeader = false;
      if (tokens.length >= 4 && tokens[0] == '48' && tokens[1] == '6B') {
        tokens = tokens.sublist(3);
        kHeader = true;
      }
      final bytes = _parseBytes(tokens);
      if (bytes == null || bytes.isEmpty) continue;
      if (bytes[0] != int.parse(header, radix: 16)) continue;
      var rest = bytes.sublist(1);
      if (kHeader) {
        // K-Line: no count byte; odd tail is the checksum.
        if (rest.length.isOdd) rest = rest.sublist(0, rest.length - 1);
        done.add(_Msg(rest, countByte: false));
      } else {
        done.add(_Msg(rest, countByte: null));
      }
    }
    return done;
  }

  List<int>? _parseBytes(List<String> tokens) {
    final out = <int>[];
    for (final t in tokens) {
      if (!_byteRe.hasMatch(t)) return null;
      out.add(int.parse(t, radix: 16));
    }
    return out;
  }

  void _extractCodes(_Msg m, Set<String> out) {
    final data = m.bytes;
    var start = 0;
    int? limit;
    var hasCount = m.countByte;
    if (hasCount == null) {
      // Headerless plain line (structure not recoverable): count byte present
      // if remaining length is odd, or if an even-length payload is exactly
      // one byte short of what its first byte would announce (truncated).
      if (data.isEmpty) return;
      if (data.length.isOdd) {
        hasCount = true;
      } else {
        hasCount = data[0] >= 2 && data[0] * 2 == data.length;
      }
    }
    if (hasCount) {
      if (data.isEmpty) return;
      limit = data[0];
      start = 1;
    }
    var added = 0;
    for (var i = start; i + 1 < data.length; i += 2) {
      if (limit != null && added >= limit) break;
      added++;
      final b1 = data[i];
      final b2 = data[i + 1];
      if (b1 == 0 && b2 == 0) continue;
      final code = _bytesToDtcString(b1, b2);
      if (code.isNotEmpty) out.add(code);
    }
  }

  /// Convenience helper for decoding raw hex responses by service ID ("43" or "47").
  List<DtcCode> decodeRaw(String serviceId, String rawHexResponse) {
    return decode(rawHexResponse, serviceId: serviceId);
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

class _Msg {
  /// Bytes following the service header (43/47).
  final List<int> bytes;

  /// true: first byte is the DTC count; false: none; null: undetermined.
  final bool? countByte;

  /// Remaining ISO-TP bytes expected (raw CAN multi-frame).
  int remaining = 0;

  _Msg(List<int> b, {required this.countByte}) : bytes = List.of(b);
}
