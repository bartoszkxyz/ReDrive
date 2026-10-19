import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/dtc/dtc_service.dart';
import 'package:redrive/services/gps/gps_location_service.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/route_downsampler.dart';
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
  final List<TripRoutePoint> routePoints;

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
    this.routePoints = const [],
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
        routePoints: const [],
      );
}

/// Provider managing real-time fuel consumption calculation, active trip accumulation,
/// anomaly detection, timeseries recording, GPS route tracking, and past trip persistence.
class TripProvider extends ChangeNotifier {
  final TripHistoryService _historyService;
  final TripTimeseriesService _timeseriesService;
  final TripAnomalyDetector _anomalyDetector;
  final DtcService _dtcService;
  final GpsLocationService _gpsService;
  final RouteDownsampler _routeDownsampler;
  FuelCalculator _fuelCalculator;
  DateTime Function() _clock;

  VehicleProfile _activeVehicleProfile = VehicleProfile.defaultSuzukiSwiftM15A();
  VehicleProfile get activeVehicleProfile => _activeVehicleProfile;
  FuelCalculator get fuelCalculator => _fuelCalculator;
  GpsLocationService get gpsService => _gpsService;
  GpsFix? _latestGpsFix;
  GpsFix? get latestGpsFix => _latestGpsFix ?? _gpsService.lastFix;
  List<TripRoutePoint> get activeRoutePoints => _routeDownsampler.points;
  StreamSubscription<GpsFix>? _gpsSubscription;

  /// Updates the latest GPS fix used for route downsampling, timeseries logging,
  /// and anomaly coordinate tagging.
  void updateGpsFix(GpsFix fix) {
    _latestGpsFix = fix;
    _gpsService.injectFix(fix);
  }

  /// Updates the active vehicle profile used for fuel calculation, anomaly thresholds,
  /// and cumulative odometer tracking.
  void applyVehicleProfile(VehicleProfile profile) {
    _activeVehicleProfile = profile;
    _fuelCalculator = FuelCalculator.fromVehicleProfile(
      profile,
      calibrationFactor: _fuelCalculator.calibrationFactor,
    );
    _anomalyDetector.applyVehicleProfile(profile);
    notifyListeners();
  }

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
  TripRoutePoint? _lastCandidateRoutePoint;

  StreamSubscription<ObdData>? _obdDataSubscription;
  ObdProvider? _boundObd;

  double _minTripDistanceKm = 0.1;
  double get minTripDistanceKm => _minTripDistanceKm;

  bool _autoTripEnabled = true;
  bool get autoTripEnabled => _autoTripEnabled;

  /// Optional callback invoked when a completed trip is saved to history.
  Future<void> Function(Trip trip)? onTripFinished;

  /// Optional callback invoked when vehicle transitions to a standstill (0 km/h).
  Future<void> Function()? onSpeedZeroStandstill;

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
    GpsLocationService? gpsService,
    RouteDownsampler? routeDownsampler,
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
        _gpsService = gpsService ?? GpsLocationService(),
        _routeDownsampler = routeDownsampler ?? RouteDownsampler(),
        _fuelCalculator =
            fuelCalculator ?? const FuelCalculator(displacementLiters: 1.5),
        _clock = clock ?? (() => DateTime.now()) {
    _gpsSubscription = _gpsService.fixStream.listen((fix) {
      _latestGpsFix = fix;
    });
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
            routePoints: _activeTrip.routePoints,
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

          final parsedRoutePoints = <TripRoutePoint>[];
          final rawRoutePoints = checkpoint['routePoints'];
          if (rawRoutePoints is Iterable) {
            for (final item in rawRoutePoints) {
              if (item != null) {
                try {
                  parsedRoutePoints.add(TripRoutePoint.fromJson(item));
                } catch (_) {}
              }
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
            routePoints: parsedRoutePoints,
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
      'routePoints': _routeDownsampler.points.map((p) => p.toJson()).toList(),
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

  /// Total vehicle odometer (base odometer from active VehicleProfile + cumulative trip distance).
  double get effectiveOdometerKm => _activeVehicleProfile.effectiveOdometerKm(
        totalDistance + (_activeTrip.isActive ? _activeTrip.distanceKm : 0.0),
      );

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
        GpsFix? demoFix;
        if (obdProvider.mode == ObdMode.demo) {
          final now = _clock();
          final dt = _lastUpdateTime != null
              ? (now.difference(_lastUpdateTime!).inMilliseconds / 1000.0)
                  .clamp(0.1, 15.0)
              : 1.0;
          demoFix = _gpsService.advanceSimulatedRoute(
            speedKmh: data.speed.toDouble(),
            dtSeconds: dt,
            timestamp: now,
          );
        }
        processDataPoint(data, gpsFix: demoFix);
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
    _lastCandidateRoutePoint = null;
    _anomalyDetector.reset();
    _routeDownsampler.reset();
    _gpsService.startPlatformListening();
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
      routePoints: const [],
    );

    unawaited(_timeseriesService.startRecording(_activeTripId!, now));
    _triggerBackgroundDtcScanIfNeeded(now, isTripStart: true);

    _updateNotificationInfo();
    LogService.i(
      "Trip started. Tracking real-time fuel, distance, anomalies, GPS route, and timeseries.",
      tag: 'Trip',
    );
    notifyListeners();
  }

  /// Processes an individual OBD data telemetry point into the active trip metrics.
  /// Supports optional [timestamp] and [gpsFix] injection for deterministic simulated sequence testing.
  void processDataPoint(
    ObdData data, {
    DateTime? timestamp,
    GpsFix? gpsFix,
  }) {
    if (timestamp != null) {
      _clock = () => timestamp;
    }
    final now = timestamp ?? _clock();
    if (gpsFix != null) {
      _latestGpsFix = gpsFix;
    }

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
        routePoints: const [],
      );
      _lastUpdateTime = timestamp;
    }

    final dtSeconds = _lastUpdateTime != null
        ? (now.difference(_lastUpdateTime!).inMilliseconds / 1000.0).clamp(0.0, 15.0)
        : 1.0;
    _lastUpdateTime = now;

    final rawDuration = now.difference(_activeTrip.startTime);
    final duration = rawDuration.isNegative ? Duration.zero : rawDuration;
    final elapsedSeconds = duration.inMicroseconds / 1000000.0;

    final speed = data.speed;
    final rpm = data.rpm;

    // Trapezoidal numerical integration for distance
    final avgSpeedForSlice = (_lastSpeed + speed) / 2.0;
    if (speed == 0 && _lastSpeed > 0) {
      onSpeedZeroStandstill?.call();
    }
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

    final activeFix = gpsFix ?? _latestGpsFix ?? _gpsService.lastFix;

    // Evaluate diagnostic anomalies & high-load power-loss rules with GPS coordinate tagging
    final enrichedData = data.copyWith(
      instantFuelLPerHour: instantFuelLPerHour,
      instantFuelL100km: instantFuelL100km,
    );
    final triggeredProblem = _anomalyDetector.evaluateSample(
      enrichedData,
      timestamp: now,
      latitude: activeFix?.latitude,
      longitude: activeFix?.longitude,
      elapsedSeconds: elapsedSeconds,
    );
    if (triggeredProblem) {
      _triggerBackgroundDtcScanIfNeeded(now, isTripStart: false);
    }

    // Record timeseries sample (with 1 Hz GPS coordinates when available)
    _timeseriesService.recordSample(
      enrichedData,
      timestamp: now,
      activeProblems: _anomalyDetector.activeProblems,
      activeSuspicions: _anomalyDetector.activeSuspicions,
      replaceLastIfWithinMs: timestamp == null ? 350 : null,
      latitude: activeFix?.latitude,
      longitude: activeFix?.longitude,
      altitudeMeters: activeFix?.altitudeMeters,
      gpsSpeedKmh: activeFix?.speedKmh,
    );

    // Record lightweight route point (~1 pt / 5s or 25m) when GPS fix is available
    if (activeFix != null) {
      final candidatePoint = TripRoutePoint(
        latitude: activeFix.latitude,
        longitude: activeFix.longitude,
        speedKmh: speed > 0 ? speed.toDouble() : (activeFix.speedKmh ?? 0.0),
        rpm: rpm,
        fuelRateLph: instantFuelLPerHour,
        fuelL100km: instantFuelL100km,
        engineLoadPercent: data.engineLoad,
        coolantTempC: data.coolantTemp,
        shortTermFuelTrim: data.shortTermFuelTrim,
        longTermFuelTrim: data.longTermFuelTrim,
        elapsedSeconds: elapsedSeconds,
      );
      _lastCandidateRoutePoint = candidatePoint;
      _routeDownsampler.recordPoint(candidatePoint);
    }

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
      routePoints: _routeDownsampler.points,
    );

    notifyListeners();
  }

  /// Records scanned [DtcCode] items into the active trip's anomaly detector.
  void recordDtcCodes(
    List<DtcCode> codes, {
    DateTime? timestamp,
    bool isTripStart = false,
    GpsFix? gpsFix,
  }) {
    if (!_activeTrip.isActive) return;
    final now = timestamp ?? _clock();
    if (gpsFix != null) {
      _latestGpsFix = gpsFix;
    }
    final activeFix = gpsFix ?? _latestGpsFix ?? _gpsService.lastFix;
    final rawElapsed = now.difference(_activeTrip.startTime).inMicroseconds / 1000000.0;
    final elapsedSeconds = rawElapsed >= 0 ? rawElapsed : 0.0;
    _anomalyDetector.recordDtcs(
      codes,
      timestamp: now,
      isTripStart: isTripStart,
      latitude: activeFix?.latitude,
      longitude: activeFix?.longitude,
      elapsedSeconds: elapsedSeconds,
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
      routePoints: _routeDownsampler.points,
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
  void processDataPointForTesting(
    ObdData data, [
    DateTime? timestamp,
    GpsFix? gpsFix,
  ]) {
    processDataPoint(data, timestamp: timestamp, gpsFix: gpsFix);
  }

  Future<void> _finishTrip([DateTime? finishTime]) async {
    final now = finishTime ?? _clock();
    final duration = now.difference(_activeTrip.startTime);
    final tripId =
        _activeTripId ?? '${_activeTrip.startTime.millisecondsSinceEpoch}';

    // Force-record the final route point if it differs from the last downsampled point
    if (_lastCandidateRoutePoint != null) {
      final pts = _routeDownsampler.points;
      if (pts.isEmpty || pts.last != _lastCandidateRoutePoint) {
        _routeDownsampler.recordPoint(_lastCandidateRoutePoint!, force: true);
      }
    }

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
        routePoints: _routeDownsampler.points,
        hasTimeseries: hasTimeseries,
      );

      await _historyService.saveTrip(trip);
      await _loadHistory();
      onTripFinished?.call(trip);
      LogService.i(
        "Trip saved to history: ${trip.distanceKm.toStringAsFixed(2)} km, "
        "${trip.duration.inMinutes}m, avg fuel: ${trip.avgFuelConsumption.toStringAsFixed(1)} L/100km, "
        "routePoints: ${trip.routePoints.length}, "
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
    _lastCandidateRoutePoint = null;
    _engineOffTime = null;
    _disconnectTime = null;
    _anomalyDetector.reset();
    _routeDownsampler.reset();
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

  /// Marks the specified [tripIds] as synced (`isSynced: true`), persists them to
  /// history, and enforces the sync-aware timeseries retention policy.
  Future<void> markTripsAsSynced(
    Iterable<String> tripIds, {
    int maxUnsyncedTrips = 35,
    int maxSyncedTrips = 5,
  }) async {
    final idSet = tripIds.toSet();
    if (idSet.isEmpty) return;

    final loaded = await _historyService.loadTrips();
    for (final trip in loaded) {
      if (idSet.contains(trip.id) && !trip.isSynced) {
        await _historyService.saveTrip(trip.copyWith(isSynced: true));
      }
    }

    final updatedTrips = await _historyService.loadTrips();
    final retainedIds = await _timeseriesService.enforceSyncAwareRetentionPolicy(
      updatedTrips,
      maxUnsyncedTrips: maxUnsyncedTrips,
      maxSyncedTrips: maxSyncedTrips,
    );
    _pastTrips = updatedTrips
        .map((t) => t.copyWith(hasTimeseries: retainedIds.contains(t.id)))
        .toList();
    notifyListeners();
  }

  /// Ingests a [trip] and optional raw `.jsonl` [timeseriesLines] received from
  /// the Headunit onto the Phone Companion archive, retaining all synced timeseries.
  Future<void> ingestSyncedTrip(
    Trip trip, {
    List<String>? timeseriesLines,
  }) async {
    bool hasTs = trip.hasTimeseries;
    if (timeseriesLines != null && timeseriesLines.isNotEmpty) {
      hasTs = await _timeseriesService.writeRawLines(trip.id, timeseriesLines);
    } else {
      hasTs = await _timeseriesService.hasTimeseries(trip.id);
    }

    final syncedTrip = trip.copyWith(
      isSynced: true,
      hasTimeseries: hasTs,
    );
    await _historyService.saveTrip(syncedTrip);

    final updatedTrips = await _historyService.loadTrips();
    final retainedIds = await _timeseriesService.enforceSyncAwareRetentionPolicy(
      updatedTrips,
      retainAll: true,
    );
    _pastTrips = updatedTrips
        .map((t) => t.copyWith(hasTimeseries: retainedIds.contains(t.id)))
        .toList();
    notifyListeners();
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
    _gpsSubscription?.cancel();
    _gpsService.dispose();
    _obdDataSubscription?.cancel();
    _boundObd?.removeListener(_onObdProviderNotification);
    _ticker?.cancel();
    if (_activeTrip.isActive) {
      saveCheckpoint(_clock());
    }
    super.dispose();
  }
}
