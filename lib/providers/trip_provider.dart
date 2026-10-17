import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/dtc/dtc_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_anomaly_detector.dart';
import 'package:redrive/services/trip/trip_history_service.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';
import 'package:redrive/services/settings/app_preferences.dart';
import 'package:redrive/services/background_service.dart';
import 'package:redrive/services/logging/log_service.dart';

/// Real-time state of the currently active driving trip.
class ActiveTripState {
  final bool isActive;
  final DateTime startTime;
  final Duration duration;
  final double distanceKm;
  final double fuelConsumedLiters;
  final double avgFuelConsumption; // L/100km
  final double instantFuelL100km;   // L/100km
  final double instantFuelLPerHour; // L/h
  final double avgSpeed;
  final double maxSpeed;
  final int maxRpm;
  final int currentSpeed;
  final int currentRpm;
  final int problemCount;
  final int suspicionCount;
  final List<TripAnomalyEpisode> anomalies;
  final List<String> recordedDtcs;

  const ActiveTripState({
    required this.isActive,
    required this.startTime,
    required this.duration,
    required this.distanceKm,
    required this.fuelConsumedLiters,
    required this.avgFuelConsumption,
    required this.instantFuelL100km,
    required this.instantFuelLPerHour,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.maxRpm,
    required this.currentSpeed,
    required this.currentRpm,
    this.problemCount = 0,
    this.suspicionCount = 0,
    this.anomalies = const [],
    this.recordedDtcs = const [],
  });

  factory ActiveTripState.initial() => ActiveTripState(
        isActive: false,
        startTime: DateTime.now(),
        duration: Duration.zero,
        distanceKm: 0.0,
        fuelConsumedLiters: 0.0,
        avgFuelConsumption: 0.0,
        instantFuelL100km: 0.0,
        instantFuelLPerHour: 0.0,
        avgSpeed: 0.0,
        maxSpeed: 0.0,
        maxRpm: 0,
        currentSpeed: 0,
        currentRpm: 0,
        problemCount: 0,
        suspicionCount: 0,
        anomalies: const [],
        recordedDtcs: const [],
      );
}

/// Provider managing real-time fuel consumption calculation, active trip accumulation,
/// anomaly detection, timeseries recording, and past trip persistence.
class TripProvider extends ChangeNotifier {
  final TripHistoryService _historyService;
  final TripTimeseriesService _timeseriesService;
  final TripAnomalyDetector _anomalyDetector;
  final DtcService _dtcService;
  final FuelCalculator _fuelCalculator;
  DateTime Function() _clock;

  List<Trip> _pastTrips = [];
  List<Trip> get pastTrips => _pastTrips;

  ActiveTripState _activeTrip = ActiveTripState.initial();
  ActiveTripState get activeTrip => _activeTrip;

  TripTimeseriesService get timeseriesService => _timeseriesService;
  TripAnomalyDetector get anomalyDetector => _anomalyDetector;

  String? _activeTripId;
  DateTime? _lastUpdateTime;
  DateTime? _lastDtcScanTime;
  DateTime? _engineOffTime;
  DateTime? _disconnectTime;
  int _rpmSum = 0;
  int _sampleCount = 0;
  int _lastSpeed = 0;
  double? _lastFuelFlowLPerHour;

  StreamSubscription<ObdData>? _obdDataSubscription;
  ObdProvider? _boundObd;

  double _minTripDistanceKm = 0.1;
  double get minTripDistanceKm => _minTripDistanceKm;

  bool _autoTripEnabled = true;
  bool get autoTripEnabled => _autoTripEnabled;

  Timer? _ticker;

  final Completer<void> _initCompleter = Completer<void>();

  /// Completes when asynchronous startup tasks (_loadPreferences and _loadHistory)
  /// finish, ensuring deterministic state across tests and callers.
  Future<void> get initialized => _initCompleter.future;

  TripProvider({
    TripHistoryService? historyService,
    TripTimeseriesService? timeseriesService,
    TripAnomalyDetector? anomalyDetector,
    DtcService? dtcService,
    FuelCalculator? fuelCalculator,
    DateTime Function()? clock,
  })  : _historyService = historyService ?? TripHistoryService(),
        _timeseriesService = timeseriesService ??
            TripTimeseriesService(
              customDirectory: historyService?.customDirectory ??
                  historyService?.customFile?.parent,
            ),
        _anomalyDetector = anomalyDetector ?? TripAnomalyDetector(),
        _dtcService = dtcService ?? DtcService(),
        _fuelCalculator =
            fuelCalculator ?? const FuelCalculator(displacementLiters: 1.5),
        _clock = clock ?? (() => DateTime.now()) {
    _init();
    // Periodic ticker to smoothly update trip duration, active checkpointing, and auto-stop timeouts
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeTrip.isActive) {
        final now = _clock();

        // Check if engine has been off for > 45 seconds
        if (_engineOffTime != null &&
            now.difference(_engineOffTime!).inSeconds >= 45) {
          _finishTrip(now);
          _engineOffTime = null;
          return;
        }

        // Check if disconnected for > 60 seconds
        if (_disconnectTime != null &&
            now.difference(_disconnectTime!).inSeconds >= 60) {
          _finishTrip(now);
          _disconnectTime = null;
          return;
        }

        final duration = now.difference(_activeTrip.startTime);
        if (!duration.isNegative) {
          _activeTrip = ActiveTripState(
            isActive: true,
            startTime: _activeTrip.startTime,
            duration: duration,
            distanceKm: _activeTrip.distanceKm,
            fuelConsumedLiters: _activeTrip.fuelConsumedLiters,
            avgFuelConsumption: _activeTrip.avgFuelConsumption,
            instantFuelL100km: _activeTrip.instantFuelL100km,
            instantFuelLPerHour: _activeTrip.instantFuelLPerHour,
            avgSpeed: _activeTrip.avgSpeed,
            maxSpeed: _activeTrip.maxSpeed,
            maxRpm: _activeTrip.maxRpm,
            currentSpeed: _activeTrip.currentSpeed,
            currentRpm: _activeTrip.currentRpm,
            problemCount: _activeTrip.problemCount,
            suspicionCount: _activeTrip.suspicionCount,
            anomalies: _activeTrip.anomalies,
            recordedDtcs: _activeTrip.recordedDtcs,
          );
        }

        // Periodic checkpoint & timeseries flush every 5 seconds
        if (now.second % 5 == 0) {
          saveCheckpoint(now);
          unawaited(_timeseriesService.flush());
        }

        if (now.second % 3 == 0) {
          _updateNotificationInfo();
        }

        notifyListeners();
      }
    });
  }

  /// Binds directly to [ObdProvider] telemetry stream.
  /// Telemetry updates are processed exclusively once via [addListener]
  /// to eliminate double-processing and telemetry drift.
  void bindToObd(ObdProvider obdProvider) {
    if (_boundObd == obdProvider) return;

    _obdDataSubscription?.cancel();
    _obdDataSubscription = null;
    _boundObd?.removeListener(_onObdProviderNotification);

    _boundObd = obdProvider;
    obdProvider.addListener(_onObdProviderNotification);

    updateFromObd(obdProvider);
  }

  void _onObdProviderNotification() {
    if (_boundObd != null) {
      updateFromObd(_boundObd!);
    }
  }

  void _updateNotificationInfo() {
    try {
      if (_activeTrip.isActive) {
        final distStr = _activeTrip.distanceKm.toStringAsFixed(1);
        updateServiceNotification(
          title: "ReDrive - Active Trip ($distStr km)",
          content:
              "Speed: ${_activeTrip.currentSpeed} km/h | Fuel: ${_activeTrip.avgFuelConsumption.toStringAsFixed(1)} L/100km",
        );
      } else {
        updateServiceNotification(
          title: "ReDrive Telemetry",
          content: "Waiting for OBD / trip start...",
        );
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    try {
      await _loadPreferences();
      await _loadHistory();
    } catch (e) {
      LogService.e('Failed to initialize TripProvider: $e', tag: 'Trip');
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  Future<void> _loadHistory() async {
    await _recoverActiveCheckpointIfNeeded();
    final loadedTrips = await _historyService.loadTrips();
    final retainedIds = await _timeseriesService.enforceRetentionPolicy(
      loadedTrips.map((t) => t.id).toList(),
    );
    _pastTrips = loadedTrips
        .map((t) => t.copyWith(hasTimeseries: retainedIds.contains(t.id)))
        .toList();
    notifyListeners();
  }

  Future<void> _recoverActiveCheckpointIfNeeded() async {
    try {
      final checkpoint = await _historyService.loadActiveCheckpoint();
      if (checkpoint != null) {
        final lastUpdatedStr = checkpoint['lastUpdated']?.toString();
        final lastUpdated =
            lastUpdatedStr != null ? DateTime.tryParse(lastUpdatedStr) : null;
        final durationSeconds =
            (checkpoint['durationSeconds'] as num?)?.toInt() ?? 0;
        final distanceKm =
            (checkpoint['distanceKm'] as num?)?.toDouble() ?? 0.0;
        final fuelConsumed =
            (checkpoint['fuelConsumedLiters'] as num?)?.toDouble() ?? 0.0;
        final avgFuel =
            (checkpoint['avgFuelConsumption'] as num?)?.toDouble() ?? 0.0;
        final avgSpeed =
            (checkpoint['avgSpeed'] as num?)?.toDouble() ?? 0.0;
        final maxSpeed =
            (checkpoint['maxSpeed'] as num?)?.toDouble() ?? 0.0;
        final maxRpm = (checkpoint['maxRpm'] as num?)?.toInt() ?? 0;
        final sampleCount =
            (checkpoint['sampleCount'] as num?)?.toInt() ?? 0;
        final rpmSum = (checkpoint['rpmSum'] as num?)?.toInt() ?? 0;
        final startTimeStr = checkpoint['startTime']?.toString();
        final startTime = startTimeStr != null
            ? DateTime.tryParse(startTimeStr) ?? _clock()
            : _clock();

        final meetsThreshold = distanceKm >= _minTripDistanceKm;
        final hasMovement = durationSeconds >= 5 || distanceKm > 0.01;
        final recoveredId = checkpoint['id']?.toString() ??
            'recovered_${startTime.millisecondsSinceEpoch}';

        if (meetsThreshold && hasMovement) {
          final hasTs = await _timeseriesService.hasTimeseries(recoveredId);
          final parsedAnomalies = <TripAnomalyEpisode>[];
          final rawAnomalies = checkpoint['anomalies'];
          if (rawAnomalies is Iterable) {
            for (final item in rawAnomalies) {
              if (item is Map<String, dynamic>) {
                parsedAnomalies.add(TripAnomalyEpisode.fromJson(item));
              } else if (item is Map) {
                parsedAnomalies.add(
                  TripAnomalyEpisode.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            }
          }
          final rawDtcs = checkpoint['recordedDtcs'];
          final parsedDtcs = <String>[];
          if (rawDtcs is Iterable) {
            for (final d in rawDtcs) {
              if (d != null) parsedDtcs.add(d.toString());
            }
          }

          final recoveredTrip = Trip(
            id: recoveredId,
            startTime: startTime,
            endTime: lastUpdated ??
                startTime.add(Duration(seconds: durationSeconds)),
            duration: Duration(seconds: durationSeconds),
            distanceKm: distanceKm,
            fuelConsumedLiters: fuelConsumed,
            avgFuelConsumption: avgFuel,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed,
            maxRpm: maxRpm,
            avgRpm: sampleCount > 0 ? (rpmSum / sampleCount).round() : 0,
            problemCount: (checkpoint['problemCount'] as num?)?.toInt() ??
                parsedAnomalies
                    .where((a) => a.severity == AnomalySeverity.problem)
                    .length,
            suspicionCount: (checkpoint['suspicionCount'] as num?)?.toInt() ??
                parsedAnomalies
                    .where((a) => a.severity == AnomalySeverity.suspicion)
                    .length,
            anomalies: parsedAnomalies,
            recordedDtcs: parsedDtcs,
            hasTimeseries: hasTs,
          );
          await _historyService.saveTrip(recoveredTrip);
          LogService.i(
            'Crash recovery: saved interrupted trip ${recoveredTrip.id} (${recoveredTrip.distanceKm.toStringAsFixed(2)} km)',
            tag: 'Trip',
          );
        } else {
          await _timeseriesService.deleteTimeseries(recoveredId);
        }
      }
    } catch (e) {
      LogService.e('Failed to recover active checkpoint: $e', tag: 'Trip');
    } finally {
      // Unconditionally clear active checkpoint file after recovery attempt
      await _historyService.clearActiveCheckpoint();
    }
  }

  Future<void> saveCheckpoint([DateTime? now]) async {
    if (!_activeTrip.isActive) return;
    final timestamp = now ?? _clock();
    final checkpointData = {
      'id': _activeTripId ?? '${_activeTrip.startTime.millisecondsSinceEpoch}',
      'startTime': _activeTrip.startTime.toIso8601String(),
      'lastUpdated': timestamp.toIso8601String(),
      'durationSeconds': _activeTrip.duration.inSeconds,
      'distanceKm': _activeTrip.distanceKm,
      'fuelConsumedLiters': _activeTrip.fuelConsumedLiters,
      'avgFuelConsumption': _activeTrip.avgFuelConsumption,
      'avgSpeed': _activeTrip.avgSpeed,
      'maxSpeed': _activeTrip.maxSpeed,
      'maxRpm': _activeTrip.maxRpm,
      'rpmSum': _rpmSum,
      'sampleCount': _sampleCount,
      'lastSpeed': _lastSpeed,
      'problemCount': _activeTrip.problemCount,
      'suspicionCount': _activeTrip.suspicionCount,
      'anomalies': _activeTrip.anomalies.map((a) => a.toJson()).toList(),
      'recordedDtcs': _activeTrip.recordedDtcs,
    };
    await _historyService.saveActiveCheckpoint(checkpointData);
  }

  Future<void> _loadPreferences() async {
    _minTripDistanceKm = await AppPreferences.getMinTripDistanceKm();
    _autoTripEnabled = await AppPreferences.isAutoTripEnabled();
    notifyListeners();
  }

  /// Sets whether trips should automatically start upon engine detection.
  Future<void> setAutoTripEnabled(bool enabled) async {
    _autoTripEnabled = enabled;
    await AppPreferences.setAutoTripEnabled(enabled);
    notifyListeners();
  }

  /// Sets the minimum distance in km required to record trips to history.
  Future<void> setMinTripDistanceKm(double km) async {
    _minTripDistanceKm = km;
    await AppPreferences.setMinTripDistanceKm(km);
    notifyListeners();
  }

  double get totalDistance =>
      _pastTrips.fold(0.0, (acc, t) => acc + t.distanceKm);

  double get totalFuelConsumed =>
      _pastTrips.fold(0.0, (acc, t) => acc + t.fuelConsumedLiters);

  double get overallAvgFuel {
    final dist = totalDistance;
    if (dist <= 0) return 0.0;
    return (totalFuelConsumed / dist) * 100.0;
  }

  /// Evaluates OBD provider telemetry stream.
  /// Automatically starts trip when engine runs (RPM >= 400 or Speed > 0)
  /// and finalizes trip after engine has remained off for 45 seconds.
  void updateFromObd(ObdProvider obdProvider) {
    final isStreaming =
        obdProvider.isEcuConnected || obdProvider.mode == ObdMode.demo;

    if (isStreaming) {
      _disconnectTime = null;
      final data = obdProvider.data;
      final isEngineRunning =
          data.rpm >= 400 || data.speed > 0 || obdProvider.mode == ObdMode.demo;

      if (isEngineRunning) {
        _engineOffTime = null;
        if (!_activeTrip.isActive && _autoTripEnabled) {
          _startTrip();
        }
      } else {
        // Engine not running (idling at 0 RPM or ignition on without engine started)
        if (_activeTrip.isActive) {
          _engineOffTime ??= _clock();
        }
      }

      if (_activeTrip.isActive) {
        processDataPoint(data);
      }
    } else {
      if (_activeTrip.isActive) {
        _disconnectTime ??= _clock();
      }
    }
  }

  void _startTrip([DateTime? startTime]) {
    final now = startTime ?? _clock();
    _lastUpdateTime = now;
    _lastDtcScanTime = null;
    _lastSpeed = 0;
    _lastFuelFlowLPerHour = null;
    _rpmSum = 0;
    _sampleCount = 0;
    _anomalyDetector.reset();
    _activeTripId = '${now.millisecondsSinceEpoch}';

    _activeTrip = ActiveTripState(
      isActive: true,
      startTime: now,
      duration: Duration.zero,
      distanceKm: 0.0,
      fuelConsumedLiters: 0.0,
      avgFuelConsumption: 0.0,
      instantFuelL100km: 0.0,
      instantFuelLPerHour: 0.0,
      avgSpeed: 0.0,
      maxSpeed: 0.0,
      maxRpm: 0,
      currentSpeed: 0,
      currentRpm: 0,
      problemCount: 0,
      suspicionCount: 0,
      anomalies: const [],
      recordedDtcs: const [],
    );

    unawaited(_timeseriesService.startRecording(_activeTripId!, now));
    _triggerBackgroundDtcScanIfNeeded(now, isTripStart: true);

    _updateNotificationInfo();
    LogService.i(
      "Trip started. Tracking real-time fuel, distance, anomalies, and timeseries.",
      tag: 'Trip',
    );
    notifyListeners();
  }

  /// Processes an individual OBD data telemetry point into the active trip metrics.
  /// Supports optional [timestamp] injection for deterministic simulated sequence testing.
  void processDataPoint(ObdData data, {DateTime? timestamp}) {
    if (timestamp != null) {
      _clock = () => timestamp;
    }
    final now = timestamp ?? _clock();

    // Initialize or align active trip start time on first sample or when inactive
    if (!_activeTrip.isActive) {
      _startTrip(now);
    } else if (_sampleCount == 0 && timestamp != null) {
      _activeTripId = '${timestamp.millisecondsSinceEpoch}';
      unawaited(_timeseriesService.startRecording(_activeTripId!, timestamp));
      _activeTrip = ActiveTripState(
        isActive: true,
        startTime: timestamp,
        duration: Duration.zero,
        distanceKm: 0.0,
        fuelConsumedLiters: 0.0,
        avgFuelConsumption: 0.0,
        instantFuelL100km: 0.0,
        instantFuelLPerHour: 0.0,
        avgSpeed: 0.0,
        maxSpeed: 0.0,
        maxRpm: 0,
        currentSpeed: 0,
        currentRpm: 0,
      );
      _lastUpdateTime = timestamp;
    }

    final dtSeconds = _lastUpdateTime != null
        ? (now.difference(_lastUpdateTime!).inMilliseconds / 1000.0).clamp(0.0, 15.0)
        : 1.0;
    _lastUpdateTime = now;

    final speed = data.speed;
    final rpm = data.rpm;

    // Trapezoidal numerical integration for distance
    final avgSpeedForSlice = (_lastSpeed + speed) / 2.0;
    _lastSpeed = speed;

    // Calculate instantaneous fuel flow (L/h) with STFT & LTFT fuel trim correction
    final instantFuelLPerHour = _fuelCalculator.calculateFuelFlowLitersPerHour(
      rpm: rpm,
      engineLoadPercent: data.engineLoad > 0 ? data.engineLoad : 25.0,
      mafGramsPerSecond: data.maf > 0 ? data.maf : null,
      directFuelRateLPerHour:
          data.engineFuelRate > 0 ? data.engineFuelRate : null,
      throttlePositionPercent: data.throttlePosition,
      speedKmH: speed,
      shortTermFuelTrimPercent: data.shortTermFuelTrim,
      longTermFuelTrimPercent: data.longTermFuelTrim,
    );

    // Symmetrical trapezoidal numerical integration for fuel accumulation
    final avgFuelForSlice = (_lastFuelFlowLPerHour != null)
        ? (_lastFuelFlowLPerHour! + instantFuelLPerHour) / 2.0
        : instantFuelLPerHour;
    _lastFuelFlowLPerHour = instantFuelLPerHour;

    // Calculate instantaneous fuel economy (L/100km)
    final instantFuelL100km = _fuelCalculator.calculateLitersPer100Km(
      fuelFlowLitersPerHour: instantFuelLPerHour,
      speedKmH: speed,
    );

    // Incremental distance and fuel using symmetrical trapezoidal average
    final deltaKm = (avgSpeedForSlice * dtSeconds) / 3600.0;
    final deltaFuelLiters = (avgFuelForSlice * dtSeconds) / 3600.0;

    final newDistance = _activeTrip.distanceKm + deltaKm;
    final newFuelConsumed = _activeTrip.fuelConsumedLiters + deltaFuelLiters;

    final avgFuel = newDistance > 0.05
        ? ((newFuelConsumed / newDistance) * 100.0).clamp(0.0, 99.9)
        : 0.0;

    _sampleCount++;
    _rpmSum += rpm;

    // Evaluate diagnostic anomalies & high-load power-loss rules
    final enrichedData = data.copyWith(
      instantFuelLPerHour: instantFuelLPerHour,
      instantFuelL100km: instantFuelL100km,
    );
    final triggeredProblem = _anomalyDetector.evaluateSample(
      enrichedData,
      timestamp: now,
    );
    if (triggeredProblem) {
      _triggerBackgroundDtcScanIfNeeded(now, isTripStart: false);
    }

    // Record timeseries sample (coalescing rapid per-PID notifications within <350ms on live OBD)
    _timeseriesService.recordSample(
      enrichedData,
      timestamp: now,
      activeProblems: _anomalyDetector.activeProblems,
      activeSuspicions: _anomalyDetector.activeSuspicions,
      replaceLastIfWithinMs: timestamp == null ? 350 : null,
    );

    final rawDuration = now.difference(_activeTrip.startTime);
    final duration = rawDuration.isNegative ? Duration.zero : rawDuration;
    final hours = duration.inMilliseconds / (3600.0 * 1000.0);
    final avgSpeed = hours > 0 ? newDistance / hours : speed.toDouble();

    final maxSpeed =
        speed > _activeTrip.maxSpeed ? speed.toDouble() : _activeTrip.maxSpeed;
    final maxRpm = rpm > _activeTrip.maxRpm ? rpm : _activeTrip.maxRpm;

    _activeTrip = ActiveTripState(
      isActive: true,
      startTime: _activeTrip.startTime,
      duration: duration,
      distanceKm: newDistance,
      fuelConsumedLiters: newFuelConsumed,
      avgFuelConsumption: avgFuel,
      instantFuelL100km: instantFuelL100km,
      instantFuelLPerHour: instantFuelLPerHour,
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
      maxRpm: maxRpm,
      currentSpeed: speed,
      currentRpm: rpm,
      problemCount: _anomalyDetector.problemCount,
      suspicionCount: _anomalyDetector.suspicionCount,
      anomalies: _anomalyDetector.episodes,
      recordedDtcs: _anomalyDetector.recordedDtcs,
    );

    notifyListeners();
  }

  /// Records scanned [DtcCode] items into the active trip's anomaly detector.
  void recordDtcCodes(
    List<DtcCode> codes, {
    DateTime? timestamp,
    bool isTripStart = false,
  }) {
    if (!_activeTrip.isActive) return;
    final now = timestamp ?? _clock();
    _anomalyDetector.recordDtcs(
      codes,
      timestamp: now,
      isTripStart: isTripStart,
    );
    _activeTrip = ActiveTripState(
      isActive: _activeTrip.isActive,
      startTime: _activeTrip.startTime,
      duration: _activeTrip.duration,
      distanceKm: _activeTrip.distanceKm,
      fuelConsumedLiters: _activeTrip.fuelConsumedLiters,
      avgFuelConsumption: _activeTrip.avgFuelConsumption,
      instantFuelL100km: _activeTrip.instantFuelL100km,
      instantFuelLPerHour: _activeTrip.instantFuelLPerHour,
      avgSpeed: _activeTrip.avgSpeed,
      maxSpeed: _activeTrip.maxSpeed,
      maxRpm: _activeTrip.maxRpm,
      currentSpeed: _activeTrip.currentSpeed,
      currentRpm: _activeTrip.currentRpm,
      problemCount: _anomalyDetector.problemCount,
      suspicionCount: _anomalyDetector.suspicionCount,
      anomalies: _anomalyDetector.episodes,
      recordedDtcs: _anomalyDetector.recordedDtcs,
    );
    notifyListeners();
  }

  void _triggerBackgroundDtcScanIfNeeded(
    DateTime now, {
    required bool isTripStart,
  }) {
    final obd = _boundObd;
    if (obd == null || !obd.isEcuConnected || obd.mode != ObdMode.real) {
      return;
    }
    if (!isTripStart &&
        _lastDtcScanTime != null &&
        now.difference(_lastDtcScanTime!).inSeconds < 60) {
      return;
    }
    _lastDtcScanTime = now;
    unawaited(() async {
      try {
        final codes = await _dtcService.scanAllCodes(obd);
        if (_activeTrip.isActive && codes.isNotEmpty) {
          recordDtcCodes(codes, timestamp: _clock(), isTripStart: isTripStart);
        }
      } catch (_) {}
    }());
  }

  @visibleForTesting
  void processDataPointForTesting(ObdData data, [DateTime? timestamp]) {
    processDataPoint(data, timestamp: timestamp);
  }

  Future<void> _finishTrip([DateTime? finishTime]) async {
    final now = finishTime ?? _clock();
    final duration = now.difference(_activeTrip.startTime);
    final tripId =
        _activeTripId ?? '${_activeTrip.startTime.millisecondsSinceEpoch}';

    // Only save trip if distance traveled satisfies the configured minimum distance threshold (default 0.1 km)
    final meetsDistanceThreshold = _activeTrip.distanceKm >= _minTripDistanceKm;
    final hasValidMovement =
        duration.inSeconds >= 5 || _activeTrip.distanceKm > 0.01;
    final keepTrip = meetsDistanceThreshold && hasValidMovement;

    final hasTimeseries = await _timeseriesService.finishTrip(
      tripId,
      keep: keepTrip,
    );

    if (keepTrip) {
      final trip = Trip(
        id: tripId,
        startTime: _activeTrip.startTime,
        endTime: now,
        duration: duration,
        distanceKm: _activeTrip.distanceKm,
        fuelConsumedLiters: _activeTrip.fuelConsumedLiters,
        avgFuelConsumption: _activeTrip.avgFuelConsumption,
        avgSpeed: _activeTrip.avgSpeed,
        maxSpeed: _activeTrip.maxSpeed,
        maxRpm: _activeTrip.maxRpm,
        avgRpm: _sampleCount > 0 ? (_rpmSum / _sampleCount).round() : 0,
        problemCount: _anomalyDetector.problemCount,
        suspicionCount: _anomalyDetector.suspicionCount,
        anomalies: _anomalyDetector.episodes,
        recordedDtcs: _anomalyDetector.recordedDtcs,
        hasTimeseries: hasTimeseries,
      );

      await _historyService.saveTrip(trip);
      await _loadHistory();
      LogService.i(
        "Trip saved to history: ${trip.distanceKm.toStringAsFixed(2)} km, "
        "${trip.duration.inMinutes}m, avg fuel: ${trip.avgFuelConsumption.toStringAsFixed(1)} L/100km, "
        "problems: ${trip.problemCount}, suspicions: ${trip.suspicionCount}",
        tag: 'Trip',
      );
    } else {
      LogService.i(
        "Trip ended but discarded: ${_activeTrip.distanceKm.toStringAsFixed(2)} km "
        "(min threshold is $_minTripDistanceKm km)",
        tag: 'Trip',
      );
    }

    await _historyService.clearActiveCheckpoint();

    _activeTrip = ActiveTripState.initial();
    _activeTripId = null;
    _lastUpdateTime = null;
    _lastDtcScanTime = null;
    _lastSpeed = 0;
    _lastFuelFlowLPerHour = null;
    _engineOffTime = null;
    _disconnectTime = null;
    _anomalyDetector.reset();
    _updateNotificationInfo();
    notifyListeners();
  }

  /// Exports a completed trip's recorded timeseries to local storage (CSV/JSON)
  /// and persists its `isExported` status and `exportedPath` in trip history.
  Future<List<String>> exportTripTimeseries(
    Trip trip, {
    TimeseriesExportFormat format = TimeseriesExportFormat.both,
  }) async {
    final paths = await _timeseriesService.exportTripTimeseries(
      trip: trip,
      format: format,
    );
    if (paths.isNotEmpty) {
      final updated = trip.copyWith(
        isExported: true,
        exportedPath: paths.first,
      );
      await _historyService.saveTrip(updated);
      await _loadHistory();
    }
    return paths;
  }

  /// Manually starts a new driving trip immediately.
  void manualStartTrip([DateTime? startTime]) {
    if (!_activeTrip.isActive) {
      _startTrip(startTime);
    }
  }

  /// Manually ends the active trip and saves it to history.
  Future<void> manualEndTrip([DateTime? finishTime]) async {
    if (_activeTrip.isActive) {
      await _finishTrip(finishTime);
    }
  }

  Future<void> deleteTrip(String id) async {
    await _timeseriesService.deleteTimeseries(id);
    await _historyService.deleteTrip(id);
    await _loadHistory();
  }

  Future<void> clearHistory() async {
    await _timeseriesService.enforceRetentionPolicy(const []);
    await _historyService.clearAll();
    await _loadHistory();
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
    _obdDataSubscription?.cancel();
    _boundObd?.removeListener(_onObdProviderNotification);
    _ticker?.cancel();
    if (_activeTrip.isActive) {
      saveCheckpoint(_clock());
    }
    super.dispose();
  }
}
