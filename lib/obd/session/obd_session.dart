import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/pid/decoders/supported_pids_decoder.dart';
import 'package:obdrive/services/logging/log_service.dart';

import '../elm/elm_client.dart';

enum ObdSessionState { disconnected, initializing, ready, error }

/// Initializes and manages an OBD-II communication session.
///
/// Configures the ELM327 adapter and discovers ECU capabilities
/// required before live polling can begin.
/// returns supportedEcuPids to registry.
class ObdSession {
  final ElmClient _elmClient;
  final String protocolCommand;
  final bool enableAdaptiveTiming;

  ObdSessionState _state = ObdSessionState.disconnected;
  Object? _lastError;

  ObdSession({
    required ElmClient elmClient,
    this.protocolCommand = 'ATSP0',
    this.enableAdaptiveTiming = false,
  }) : _elmClient = elmClient;

  ObdSessionState get state => _state;
  Object? get lastError => _lastError;

  Future<Set<int>> initialize() async {
    _state = ObdSessionState.initializing;
    _lastError = null;
    LogService.i("Starting OBD initialization sequence (protocol: $protocolCommand)...", tag: 'OBD');

    try {
      // When reconnecting to an ELM327 adapter that was previously streaming PIDs,
      // the serial/Bluetooth RFCOMM buffer may contain residual frames (e.g. 41 11 22 > or 13.2V>).
      // We retry ATZ up to 3 times, discarding residual non-adapterInfo frames until the reset completes.
      ElmResponse? zResp;
      for (int attempt = 1; attempt <= 3; attempt++) {
        final resp = await _elmClient.execute(
          'ATZ',
          timeout: const Duration(seconds: 4),
        );
        if (resp.type == ElmResponseType.adapterInfo || resp.type == ElmResponseType.ok) {
          zResp = resp;
          break;
        }
        LogService.w(
          'ATZ attempt $attempt received residual frame: (${resp.type}) ${resp.raw.trim()}. Retrying reset...',
          tag: 'OBD',
        );
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (zResp == null) {
        throw StateError('ATZ reset failed: adapter did not return adapterInfo/OK after 3 attempts');
      }

      LogService.i("Adapter identified: ${zResp.raw.trim()}", tag: 'OBD');

      await _executeAndExpect('ATE0', ElmResponseType.ok);
      await _executeAndExpect('ATL0', ElmResponseType.ok);
      await _executeAndExpect(protocolCommand, ElmResponseType.ok);
      LogService.i("ELM adapter configured with $protocolCommand", tag: 'OBD');

      if (enableAdaptiveTiming) {
        try {
          final atatResp = await _elmClient.execute('ATAT2');
          if (atatResp.type != ElmResponseType.ok) {
            LogService.w("ATAT2 returned ${atatResp.type}, continuing", tag: 'OBD');
          }
          final atstResp = await _elmClient.execute('ATST19');
          if (atstResp.type != ElmResponseType.ok) {
            LogService.w("ATST19 returned ${atstResp.type}, continuing", tag: 'OBD');
          }
        } catch (e) {
          LogService.w("Adaptive timing configuration skipped: $e", tag: 'OBD');
        }
      }

      final supportedPids = <int>{};
      // On K-Line/KWP2000 vehicles like Suzuki Swift, automatic protocol search
      // on 0100 takes 5-10s across protocols. Give it up to 15s to discover the ECU.
      LogService.i("Querying ECU PID 0100 (ECU handshake & protocol search)...", tag: 'OBD');
      final p00Response = await _executeAndExpect(
        '0100',
        ElmResponseType.data,
        timeout: const Duration(seconds: 15),
      );
      supportedPids.addAll(decodeSupportedPids(p00Response, basePid: 0x00));
      LogService.i("ECU responded: discovered ${supportedPids.length} standard PIDs in range 01-20", tag: 'OBD');

      // Standard multi-range PID discovery (SAE J1979)
      if (supportedPids.contains(0x20)) {
        try {
          final p20Response = await _elmClient.execute('0120');
          if (p20Response.type == ElmResponseType.data) {
            final pids20 = decodeSupportedPids(p20Response, basePid: 0x20);
            supportedPids.addAll(pids20);
            LogService.i("Discovered ${pids20.length} additional PIDs in range 21-40", tag: 'OBD');
          }
        } catch (_) {
          // Fallback gracefully if ECU does not respond to 0120
        }
      }

      if (supportedPids.contains(0x40)) {
        try {
          final p40Response = await _elmClient.execute('0140');
          if (p40Response.type == ElmResponseType.data) {
            final pids40 = decodeSupportedPids(p40Response, basePid: 0x40);
            supportedPids.addAll(pids40);
            LogService.i("Discovered ${pids40.length} additional PIDs in range 41-60", tag: 'OBD');
          }
        } catch (_) {
          // Fallback gracefully if ECU does not respond to 0140
        }
      }

      _state = ObdSessionState.ready;
      LogService.i("✅ OBD session ready. Total supported ECU PIDs: ${supportedPids.length}", tag: 'OBD');
      return supportedPids;
    } catch (e) {
      _lastError = e;
      _state = ObdSessionState.error;
      LogService.e("❌ OBD session initialization failed: $e", tag: 'OBD', error: e);
      rethrow;
    }
  }

  Future<ElmResponse> _executeAndExpect(
    String command,
    ElmResponseType expectedType, {
    Duration timeout = const Duration(seconds: 2),
    bool allowOkForAdapterInfo = false,
  }) async {
    final response = await _elmClient.execute(command, timeout: timeout);

    final isExpected = response.type == expectedType ||
        (allowOkForAdapterInfo &&
            expectedType == ElmResponseType.adapterInfo &&
            response.type == ElmResponseType.ok);

    if (!isExpected) {
      final msg = '$command expected $expectedType, got ${response.type} (${response.raw.trim()})';
      LogService.w("OBD command mismatch: $msg", tag: 'OBD');
      throw StateError(msg);
    }

    return response;
  }
}
