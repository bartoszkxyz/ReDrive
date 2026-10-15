import 'dart:async';
import '../elm/elm_client.dart';
import '../elm/elm_response.dart';
import '../pid/pid_definition.dart';
import '../pid/pid_key.dart';
import '../pid/pid_registry.dart';

enum WatchSource { visibleScreen, backgroundMonitoring, logging, session }

/// Priority tier determining polling frequency over the OBD-II serial bus.
enum PidPriorityTier {
  /// Fast tier: polled on every loop (RPM, Speed, Throttle, MAF).
  high,
  /// Normal tier: polled every 2nd loop (Load, STFT, MAP, Timing, Fuel Rate, Loop Status).
  normal,
  /// Slow tier: polled every 8th loop (Coolant, IAT, Fuel Tank, LTFT, Voltage, Temp sensors).
  low,
}

/// Controls periodic polling of requested OBD-II PIDs.
///
/// Combines watchlists from multiple consumers such as
/// (screen, logs, session and other), schedules PID requests,
/// stores the latest values, and emits decoded updates.
class PollingController {
  final ElmClient _elmClient;
  final PidRegistry _registry;
  final Set<PidKey> _supportedEcuKeys;

  final Map<WatchSource, Set<PidKey>> _watchlists = {};
  final Map<PidKey, num> _latestValues = {};
  int _cycleCount = 0;

  final _updatesController =
      StreamController<({PidKey key, num value})>.broadcast();

  bool _isPolling = false;

  PollingController({
    required ElmClient elmClient,
    required PidRegistry registry,
    required Set<PidKey> supportedEcuKeys,
  }) : _elmClient = elmClient,
       _registry = registry,
       _supportedEcuKeys = supportedEcuKeys;

  bool get isPolling => _isPolling;
  Map<PidKey, num> get latestValues => Map.unmodifiable(_latestValues);
  Stream<({PidKey key, num value})> get updates => _updatesController.stream;
  int get cycleCount => _cycleCount;

  static PidPriorityTier priorityFor(PidKey key) {
    switch (key) {
      case PidKey.engineRpm:
      case PidKey.vehicleSpeed:
      case PidKey.throttlePosition:
      case PidKey.mafAirFlowRate:
        return PidPriorityTier.high;

      case PidKey.engineLoad:
      case PidKey.shortTermFuelTrim1:
      case PidKey.timingAdvance:
      case PidKey.intakeManifoldPressure:
      case PidKey.engineFuelRate:
      case PidKey.fuelSystemStatus:
        return PidPriorityTier.normal;

      case PidKey.coolantTemperature:
      case PidKey.intakeAirTemperature:
      case PidKey.adapterVoltage:
      case PidKey.fuelTankLevel:
      case PidKey.longTermFuelTrim1:
      case PidKey.fuelPressure:
      case PidKey.barometricPressure:
      case PidKey.controlModuleVoltage:
      case PidKey.ambientAirTemperature:
      case PidKey.engineOilTemperature:
      case PidKey.runTimeSinceStart:
        return PidPriorityTier.low;
    }
  }

  void setWatchlist(WatchSource source, Set<PidKey> keys) {
    if (keys.isEmpty) {
      _watchlists.remove(source);
    } else {
      _watchlists[source] = Set.unmodifiable(keys);
    }
  }

  Set<PidKey> computeEffectiveKeys() {
    final allRequested = <PidKey>{};
    for (final keys in _watchlists.values) {
      allRequested.addAll(keys);
    }

    final effective = <PidKey>{};
    for (final key in allRequested) {
      final definition = _registry.find(key);
      if (definition == null) continue;

      if (definition.source == PidSource.adapter ||
          _supportedEcuKeys.contains(key)) {
        effective.add(key);
      }
    }

    return effective;
  }

  /// Determines which keys to poll this cycle based on tiered priority.
  /// Uninitialized keys are always included to ensure fast initial discovery.
  List<PidKey> computeScheduledKeys(Set<PidKey> effectiveKeys) {
    return effectiveKeys.where((key) {
      if (!_latestValues.containsKey(key)) return true;
      final tier = priorityFor(key);
      switch (tier) {
        case PidPriorityTier.high:
          return true;
        case PidPriorityTier.normal:
          return _cycleCount % 2 == 0;
        case PidPriorityTier.low:
          return _cycleCount % 8 == 0;
      }
    }).toList();
  }

  void start() {
    if (!_isPolling) {
      _isPolling = true;

      unawaited(_runPollingLoop());
    }
  }

  void stop() {
    _isPolling = false;
  }

  Future<void> _runPollingLoop() async {
    while (_isPolling) {
      final effective = computeEffectiveKeys();

      if (effective.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));

        continue;
      }

      _cycleCount++;
      final keys = computeScheduledKeys(effective);

      for (final key in keys) {
        if (!_isPolling) break;

        final definition = _registry.find(key);
        if (definition == null) continue;

        try {
          var response = await _elmClient.execute(definition.command);
          if (!_isPolling) return;

          const retryableTypes = <ElmResponseType>{
            ElmResponseType.busError,
            ElmResponseType.adapterError,
            ElmResponseType.stopped,
            ElmResponseType.unableToConnect,
            ElmResponseType.malformed,
          };

          if (retryableTypes.contains(response.type)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (!_isPolling) return;

            response = await _elmClient.execute(definition.command);
            if (!_isPolling) return;
          }

          if (response.type == ElmResponseType.noData) {
            continue;
          }

          if (response.type != ElmResponseType.data &&
              response.type != ElmResponseType.adapterVoltage) {
            throw StateError(
              'Polling ${definition.command} failed: ${response.type}',
            );
          }
          final value = definition.decoder(response);

          _latestValues[key] = value;

          if (!_updatesController.isClosed) {
            _updatesController.add((key: key, value: value));
          }
        } catch (error, stackTrace) {
          if (!_isPolling) return;

          _isPolling = false;

          if (!_updatesController.isClosed) {
            _updatesController.addError(error, stackTrace);
          }

          return;
        }
      }
    }
  }

  Future<void> dispose() async {
    stop();
    await _updatesController.close();
  }
}
