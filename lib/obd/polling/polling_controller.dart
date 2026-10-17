import 'dart:async';
import 'package:flutter/foundation.dart';
import '../elm/elm_client.dart';
import '../elm/elm_response.dart';
import '../pid/pid_definition.dart';
import '../pid/pid_key.dart';
import '../pid/pid_registry.dart';

enum WatchSource { visibleScreen, backgroundMonitoring, logging, session }

/// Priority tier determining polling frequency over the OBD-II serial bus.
enum PidPriorityTier {
  /// Fast tier: polled on every loop (RPM, Speed, Throttle, MAF, Load, STFT).
  high,
  /// Normal tier: interleaved medium rate (LTFT, MAP, Timing, Fuel Rate, Loop Status).
  normal,
  /// Slow tier: interleaved low rate (Coolant, IAT, Fuel Tank, Voltage, Temp sensors).
  low,
}

/// Controls periodic polling of requested OBD-II PIDs.
///
/// Combines watchlists from multiple consumers such as
/// (screen, logs, session and other), schedules PID requests,
/// stores the latest values, and emits decoded updates.
class PollingController {
  static const int maxConsecutiveNoData = 5;

  final ElmClient _elmClient;
  final PidRegistry _registry;
  final Set<PidKey> _supportedEcuKeys;

  final Map<WatchSource, Set<PidKey>> _watchlists = {};
  final Map<PidKey, num> _latestValues = {};
  final Map<PidKey, int> _lastPolledCycle = {};
  final Map<PidKey, int> _consecutiveNoData = {};
  final Set<PidKey> _quarantinedKeys = {};
  int _cycleCount = 0;

  final _updatesController =
      StreamController<({PidKey key, num value})>.broadcast();
  final _cycleCompleteController =
      StreamController<Map<PidKey, num>>.broadcast();

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
  Set<PidKey> get quarantinedKeys => Set.unmodifiable(_quarantinedKeys);
  Stream<({PidKey key, num value})> get updates => _updatesController.stream;
  Stream<Map<PidKey, num>> get onCycleComplete =>
      _cycleCompleteController.stream;
  int get cycleCount => _cycleCount;

  /// Whether Smart High-Load Boost is currently active (RPM > 3000 or Rel Throttle > 50%).
  bool get isHighLoadBoostActive {
    final rpm = (_latestValues[PidKey.engineRpm] ?? 0).toDouble();
    final rawThrottle = (_latestValues[PidKey.throttlePosition] ?? 0).toDouble();
    final relThrottle = ((rawThrottle - 13.0) / (85.0 - 13.0) * 100.0).clamp(0.0, 100.0);
    return rpm > 3000 || relThrottle > 50.0;
  }

  @visibleForTesting
  void seedValueForTesting(PidKey key, num value, {int? polledAtCycle}) {
    _latestValues[key] = value;
    if (polledAtCycle != null) {
      _lastPolledCycle[key] = polledAtCycle;
    }
  }

  static PidPriorityTier priorityFor(PidKey key) {
    switch (key) {
      case PidKey.engineRpm:
      case PidKey.vehicleSpeed:
      case PidKey.throttlePosition:
      case PidKey.mafAirFlowRate:
      case PidKey.engineLoad:
      case PidKey.shortTermFuelTrim1:
        return PidPriorityTier.high;

      case PidKey.longTermFuelTrim1:
      case PidKey.timingAdvance:
      case PidKey.intakeManifoldPressure:
      case PidKey.engineFuelRate:
      case PidKey.fuelSystemStatus:
        return PidPriorityTier.normal;

      case PidKey.coolantTemperature:
      case PidKey.intakeAirTemperature:
      case PidKey.adapterVoltage:
      case PidKey.fuelTankLevel:
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
      if (_quarantinedKeys.contains(key)) continue;

      final definition = _registry.find(key);
      if (definition == null) continue;

      if (definition.source == PidSource.adapter ||
          _supportedEcuKeys.contains(key)) {
        effective.add(key);
      }
    }

    return effective;
  }

  /// Determines which keys to poll this cycle using interleaved overdue scheduling
  /// and Smart High-Load Boost.
  /// Uninitialized keys are always included to ensure fast initial discovery.
  List<PidKey> computeScheduledKeys(Set<PidKey> effectiveKeys) {
    if (effectiveKeys.isEmpty) return const [];
    _cycleCount++;

    final scheduled = <PidKey>[];
    final normalCandidates = <PidKey>[];
    final lowCandidates = <PidKey>[];

    for (final key in effectiveKeys) {
      if (!_latestValues.containsKey(key) && !_lastPolledCycle.containsKey(key)) {
        scheduled.add(key);
        continue;
      }

      switch (priorityFor(key)) {
        case PidPriorityTier.high:
          scheduled.add(key);
        case PidPriorityTier.normal:
          normalCandidates.add(key);
        case PidPriorityTier.low:
          lowCandidates.add(key);
      }
    }

    int overdueCycles(PidKey key) =>
        _cycleCount - (_lastPolledCycle[key] ?? 0);

    normalCandidates.sort((a, b) => overdueCycles(b).compareTo(overdueCycles(a)));
    lowCandidates.sort((a, b) => overdueCycles(b).compareTo(overdueCycles(a)));

    final boostActive = isHighLoadBoostActive;

    if (boostActive) {
      // Smart High-Load Boost: yield Tier-3 slow slots to Normal tier (LTFT, Timing, MAP, Loop)
      final dueNormal = normalCandidates
          .where((k) => overdueCycles(k) >= 1)
          .take(3);
      for (final k in dueNormal) {
        scheduled.add(k);
        _lastPolledCycle[k] = _cycleCount;
      }

      // Preserve coolant thermal safety check every 12 cycles during sustained high RPM
      if (lowCandidates.contains(PidKey.coolantTemperature) &&
          overdueCycles(PidKey.coolantTemperature) >= 12) {
        scheduled.add(PidKey.coolantTemperature);
        _lastPolledCycle[PidKey.coolantTemperature] = _cycleCount;
      }
    } else {
      // Standard Interleaved Pacing: up to 2 overdue normal keys + at most 1 overdue low key
      final dueNormal = normalCandidates
          .where((k) => overdueCycles(k) >= 2)
          .take(2);
      for (final k in dueNormal) {
        scheduled.add(k);
        _lastPolledCycle[k] = _cycleCount;
      }

      final dueLow = lowCandidates
          .where((k) => overdueCycles(k) >= 8)
          .take(1);
      for (final k in dueLow) {
        scheduled.add(k);
        _lastPolledCycle[k] = _cycleCount;
      }
    }

    // Fallback: if effectiveKeys only contains normal/low keys and none met the cycle threshold yet,
    // schedule the most overdue key so single-key watchlists never spin idle.
    if (scheduled.isEmpty) {
      final allRemaining = [...normalCandidates, ...lowCandidates]
        ..sort((a, b) => overdueCycles(b).compareTo(overdueCycles(a)));
      if (allRemaining.isNotEmpty) {
        final pick = allRemaining.first;
        scheduled.add(pick);
        _lastPolledCycle[pick] = _cycleCount;
      }
    }

    for (final k in scheduled) {
      _lastPolledCycle[k] = _cycleCount;
    }

    return scheduled;
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

      final keys = computeScheduledKeys(effective);
      var anyUpdatedInCycle = false;

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
            final failures = (_consecutiveNoData[key] ?? 0) + 1;
            _consecutiveNoData[key] = failures;
            if (failures >= maxConsecutiveNoData) {
              _quarantinedKeys.add(key);
            }
            continue;
          }

          if (response.type != ElmResponseType.data &&
              response.type != ElmResponseType.adapterVoltage) {
            throw StateError(
              'Polling ${definition.command} failed: ${response.type}',
            );
          }

          _consecutiveNoData[key] = 0;
          final value = definition.decoder(response);

          _latestValues[key] = value;
          anyUpdatedInCycle = true;

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

      if (_isPolling &&
          anyUpdatedInCycle &&
          !_cycleCompleteController.isClosed) {
        _cycleCompleteController.add(Map<PidKey, num>.unmodifiable(_latestValues));
      }
    }
  }

  Future<void> dispose() async {
    stop();
    await _updatesController.close();
    await _cycleCompleteController.close();
  }
}
