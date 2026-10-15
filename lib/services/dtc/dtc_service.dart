import 'package:flutter/foundation.dart';

import '../../models/dtc_code.dart';
import '../../obd/elm/elm_response.dart';
import '../../providers/obd_provider.dart';
import 'dtc_database.dart';
import 'dtc_decoder.dart';

/// Exception thrown when vehicle motion safety check prevents executing Mode 04 DTC clear.
class DtcSafetyException implements Exception {
  final String message;
  final int speed;
  final int rpm;

  const DtcSafetyException(this.message, {this.speed = 0, this.rpm = 0});

  @override
  String toString() =>
      'DtcSafetyException: $message (speed: $speed km/h, RPM: $rpm)';
}

/// Thrown when a Mode 03/07 scan could not be completed (as opposed to a
/// successful scan that found no faults).
class DtcScanException implements Exception {
  final String message;
  const DtcScanException(this.message);

  @override
  String toString() => 'DtcScanException: $message';
}

/// Service managing vehicle diagnostic trouble code (DTC) reading and clearing.
class DtcService {
  final DtcDecoder _decoder = const DtcDecoder();

  // Simulated state for Demo mode
  List<DtcCode> _demoCodes = [
    DtcDatabase.resolve('P0300'),
    DtcDatabase.resolve('P0171'),
    DtcDatabase.resolve('P0420', isPending: true),
  ];

  List<DtcCode> _lastScannedCodes = [];

  /// Returns the most recently scanned diagnostic trouble codes.
  List<DtcCode> get lastScannedCodes => List.unmodifiable(_lastScannedCodes);

  /// Reads confirmed (Mode 03) and pending (Mode 07) trouble codes.
  Future<List<DtcCode>> scanAllCodes(ObdProvider obdProvider) async {
    if (obdProvider.mode == ObdMode.demo) {
      // Simulate real ECU scan delay
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      _lastScannedCodes = List.unmodifiable(_demoCodes);
      return _lastScannedCodes;
    }

    if (!obdProvider.isEcuConnected) {
      throw StateError('Vehicle ECU is not connected.');
    }

    final results = <DtcCode>[];

    // Query Mode 03 (Stored Confirmed Trouble Codes). Failure must surface:
    // it is not the same as "no faults".
    final ElmResponse response03;
    try {
      response03 = await obdProvider.executeCommand('03');
    } catch (e) {
      throw DtcScanException('Mode 03 query failed: $e');
    }
    if (response03.type != ElmResponseType.data) {
      throw DtcScanException(
        'Mode 03 query failed: ${response03.type.name} (${response03.raw.trim()})',
      );
    }
    results.addAll(_decoder.decode(response03, isPending: false));

    // Query Mode 07 (Pending Trouble Codes). Many ECUs answer NO DATA when
    // unsupported, which is tolerated; transport failures are not.
    try {
      final response07 = await obdProvider.executeCommand('07');
      if (response07.type == ElmResponseType.data) {
        for (final p in _decoder.decode(response07, isPending: true)) {
          if (!results.contains(p)) results.add(p);
        }
      }
    } catch (e) {
      throw DtcScanException('Mode 07 query failed: $e');
    }

    _lastScannedCodes = List.unmodifiable(results);
    return results;
  }

  final Map<bool, Future<bool>> _clearInFlight = {};

  /// Clears trouble codes and resets Check Engine Light (Mode 04).
  ///
  /// Fails closed: live vehicle speed (010D) and RPM (010C) are queried
  /// immediately before Mode 04. If either is unavailable or unparseable the
  /// clear is refused (returns false, nothing sent); if either is non-zero a
  /// [DtcSafetyException] is thrown.
  ///
  /// [speed] / [rpm] are test-only extra constraints: they can only make the
  /// interlock stricter (any non-zero or negative value blocks) and never
  /// replace the live reading. [allowWhileMoving] is test-only and not used
  /// by any UI path.
  ///
  /// Concurrent calls share a single in-flight operation, so Mode 04 is sent
  /// at most once.
  Future<bool> clearAllCodes(
    ObdProvider obdProvider, {
    @visibleForTesting bool allowWhileMoving = false,
    @visibleForTesting int? speed,
    @visibleForTesting int? rpm,
  }) {
    final existing = _clearInFlight[allowWhileMoving];
    if (existing != null) return existing;
    final future = _clearImpl(obdProvider, allowWhileMoving, speed, rpm);
    _clearInFlight[allowWhileMoving] = future;
    future.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_clearInFlight[allowWhileMoving], future)) {
        _clearInFlight.remove(allowWhileMoving);
      }
    });
    return future;
  }

  Future<bool> _clearImpl(
    ObdProvider obdProvider,
    bool allowWhileMoving,
    int? speedOverride,
    int? rpmOverride,
  ) async {
    if (obdProvider.mode == ObdMode.demo) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      _demoCodes = [];
      _lastScannedCodes = [];
      return true;
    }

    if (!obdProvider.isEcuConnected) {
      throw StateError('Vehicle ECU is not connected.');
    }

    if (!allowWhileMoving) {
      // Vehicle motion safety interlock (Requirement R3): live readings.
      final liveSpeed = await _queryLive(obdProvider, '010D', 1);
      final liveRpm = liveSpeed == null
          ? null
          : await _queryLive(obdProvider, '010C', 2);
      if (liveSpeed == null || liveRpm == null) {
        return false; // fail closed: cannot prove vehicle is stationary
      }
      final currentSpeed = liveSpeed;
      final currentRpm = liveRpm ~/ 4; // 010C is in 1/4 rpm units
      final rpmNonZero = liveRpm != 0;
      final moving =
          currentSpeed != 0 ||
          rpmNonZero ||
          (speedOverride != null && speedOverride != 0) ||
          (rpmOverride != null && rpmOverride != 0);
      if (moving) {
        throw DtcSafetyException(
          'Vehicle motion safety check prevents clearing DTCs while speed > 0 or engine running (RPM > 0).',
          speed: currentSpeed,
          rpm: currentRpm,
        );
      }
    }

    try {
      final response = await obdProvider.executeCommand('04');
      final success = _isPositiveMode04(response);
      if (success) {
        _lastScannedCodes = [];
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Queries a Mode 01 PID live; returns the raw-byte sum indicator
  /// (0 only if every data byte is zero) or null if unavailable/unparseable.
  Future<int?> _queryLive(
    ObdProvider obdProvider,
    String cmd,
    int dataBytes,
  ) async {
    try {
      final r = await obdProvider.executeCommand(cmd);
      if (r.type != ElmResponseType.data) return null;
      final pid = cmd.substring(2).toUpperCase();
      for (final line in r.lines) {
        var tokens = line.trim().toUpperCase().split(RegExp(r'\s+'));
        if (tokens.length == 1 && tokens[0].length >= 4) {
          // compact hex
          final t = tokens[0];
          tokens = [
            for (var i = 0; i + 1 < t.length; i += 2) t.substring(i, i + 2),
          ];
        }
        for (var i = 0; i <= 3 && i + 1 < tokens.length; i++) {
          if (tokens[i] == '41' && tokens[i + 1] == pid) {
            if (i + 2 + dataBytes > tokens.length) return null;
            var any = 0;
            for (var j = 0; j < dataBytes; j++) {
              final v = int.tryParse(tokens[i + 2 + j], radix: 16);
              if (v == null) return null;
              any = any * 256 + v;
            }
            return any;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Strict Mode 04 positive response: a frame consisting of '44' at the
  /// start (after optional CAN id / PCI / K-Line header). '7F 04 ..' fails.
  bool _isPositiveMode04(ElmResponse r) {
    if (r.type != ElmResponseType.data) return false;
    var positive = false;
    for (final line in r.lines) {
      var t = line.trim().toUpperCase().split(RegExp(r'\s+'));
      if (t.length == 1 && t[0] == '44') {
        positive = true;
        continue;
      }
      if (t.length > 1 &&
          (RegExp(r'^7E[8-9A-F]$').hasMatch(t[0]) ||
              RegExp(r'^[0-9A-F]{8}$').hasMatch(t[0]))) {
        t = t.sublist(1);
        if (t.isNotEmpty && t[0] == '01') t = t.sublist(1);
      } else if (t.length >= 4 && t[0] == '48' && t[1] == '6B') {
        t = t.sublist(3);
      }
      if (t.isNotEmpty && t[0] == '7F') return false;
      if (t.isNotEmpty && t[0] == '44') positive = true;
    }
    return positive;
  }

  /// Resets demo faults if in demo mode
  void resetDemoCodes() {
    _demoCodes = [
      DtcDatabase.resolve('P0300'),
      DtcDatabase.resolve('P0171'),
      DtcDatabase.resolve('P0420', isPending: true),
    ];
    _lastScannedCodes = [];
  }
}
