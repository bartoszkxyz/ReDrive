import '../../models/dtc_code.dart';
import '../../providers/obd_provider.dart';
import 'dtc_database.dart';
import 'dtc_decoder.dart';

/// Service managing vehicle diagnostic trouble code (DTC) reading and clearing.
class DtcService {
  final DtcDecoder _decoder = const DtcDecoder();

  // Simulated state for Demo mode
  List<DtcCode> _demoCodes = [
    DtcDatabase.resolve('P0300'),
    DtcDatabase.resolve('P0171'),
    DtcDatabase.resolve('P0420', isPending: true),
  ];

  /// Reads confirmed (Mode 03) and pending (Mode 07) trouble codes.
  Future<List<DtcCode>> scanAllCodes(ObdProvider obdProvider) async {
    if (obdProvider.mode == ObdMode.demo) {
      // Simulate real ECU scan delay
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      return List.unmodifiable(_demoCodes);
    }

    if (!obdProvider.isEcuConnected) {
      throw StateError('Vehicle ECU is not connected.');
    }

    final results = <DtcCode>[];

    // Query Mode 03 (Stored Confirmed Trouble Codes)
    try {
      final response03 = await obdProvider.executeCommand('03');
      final confirmed = _decoder.decode(response03, isPending: false);
      results.addAll(confirmed);
    } catch (_) {
      // Continue to try Mode 07
    }

    // Query Mode 07 (Pending Trouble Codes)
    try {
      final response07 = await obdProvider.executeCommand('07');
      final pending = _decoder.decode(response07, isPending: true);
      for (final p in pending) {
        if (!results.contains(p)) {
          results.add(p);
        }
      }
    } catch (_) {
      // Ignore if Mode 07 is not supported
    }

    return results;
  }

  /// Clears trouble codes and resets Check Engine Light (Mode 04).
  Future<bool> clearAllCodes(ObdProvider obdProvider) async {
    if (obdProvider.mode == ObdMode.demo) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      _demoCodes = [];
      return true;
    }

    if (!obdProvider.isEcuConnected) {
      throw StateError('Vehicle ECU is not connected.');
    }

    try {
      final response = await obdProvider.executeCommand('04');
      // Mode 04 returns "44" or "OK"
      final success = response.raw.contains('44') || response.raw.contains('OK');
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Resets demo faults if in demo mode
  void resetDemoCodes() {
    _demoCodes = [
      DtcDatabase.resolve('P0300'),
      DtcDatabase.resolve('P0171'),
      DtcDatabase.resolve('P0420', isPending: true),
    ];
  }
}
