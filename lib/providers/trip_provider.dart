import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/trip/fuel_calculator.dart';
import 'package:redrive/services/trip/trip_history_service.dart';
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
      );
}

/// Provider managing real-time fuel consumption calculation, active trip accumulation,
/// and past trip persistence.
class TripProvider extends ChangeNotifier {
  final TripHistoryService _historyService = TripHistoryService();
  final FuelCalculator _fuelCalculator = const FuelCalculator(displacementLiters: 1.5);

  List<Trip> _pastTrips = [];
  List<Trip> get pastTrips => _pastTrips;

  ActiveTripState _activeTrip = ActiveTripState.initial();
  ActiveTripState get activeTrip => _activeTrip;

  DateTime? _lastUpdateTime;
  DateTime? _engineOffTime;
  DateTime? _disconnectTime;
  int _rpmSum = 0;
  int _sampleCount = 0;
  int _lastSpeed = 0;

  StreamSubscription<ObdData>? _obdDataSubscription;
  ObdProvider? _boundObd;

  double _minTripDistanceKm = 10.0;
  double get minTripDistanceKm => _minTripDistanceKm;

  Timer? _ticker;

  TripProvider() {
    _loadHistory();
    _loadPreferences();
    // Periodic ticker to smoothly update trip duration and handle auto-stop timeouts
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeTrip.isActive) {
        final now = DateTime.now();

        // Check if engine has been off for > 45 seconds
        if (_engineOffTime != null && now.difference(_engineOffTime!).inSeconds >= 45) {
          _finishTrip();
          _engineOffTime = null;
          return;
        }

        // Check if disconnected for > 60 seconds
        if (_disconnectTime != null && now.difference(_disconnectTime!).inSeconds >= 60) {
          _finishTrip();
          _disconnectTime = null;
          return;
        }

        final duration = now.difference(_activeTrip.startTime);
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
        );

        if (now.second % 3 == 0) {
          _updateNotificationInfo();
        }

        notifyListeners();
      }
    });
  }

  /// Binds directly to [ObdProvider] telemetry streams, decoupling trip accumulation
  /// from the Flutter widget tree lifecycle.
  void bindToObd(ObdProvider obdProvider) {
    if (_boundObd == obdProvider && _obdDataSubscription != null) return;

    _obdDataSubscription?.cancel();
    _boundObd?.removeListener(_onObdProviderNotification);

    _boundObd = obdProvider;
    obdProvider.addListener(_onObdProviderNotification);

    _obdDataSubscription = obdProvider.dataStream.listen((_) {
      updateFromObd(obdProvider);
    });

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
          content: "Speed: ${_activeTrip.currentSpeed} km/h | Fuel: ${_activeTrip.avgFuelConsumption.toStringAsFixed(1)} L/100km",
        );
      } else {
        updateServiceNotification(
          title: "ReDrive Telemetry",
          content: "Waiting for OBD / trip start...",
        );
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    _pastTrips = await _historyService.loadTrips();
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    _minTripDistanceKm = await AppPreferences.getMinTripDistanceKm();
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

  /// Binds to [ObdProvider] telemetry streams.
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
        if (!_activeTrip.isActive) {
          _startTrip();
        }
      } else {
        // Engine not running (idling at 0 RPM or ignition on without engine started)
        if (_activeTrip.isActive) {
          _engineOffTime ??= DateTime.now();
        }
      }

      if (_activeTrip.isActive) {
        _processDataPoint(data);
      }
    } else {
      if (_activeTrip.isActive) {
        _disconnectTime ??= DateTime.now();
      }
    }
  }

  void _startTrip() {
    final now = DateTime.now();
    _lastUpdateTime = now;
    _lastSpeed = 0;
    _rpmSum = 0;
    _sampleCount = 0;

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
    );

    _updateNotificationInfo();
    LogService.i("Trip started. Tracking real-time fuel, distance, and speeds.", tag: 'Trip');
    notifyListeners();
  }

  void _processDataPoint(ObdData data) {
    final now = DateTime.now();
    final dtSeconds = _lastUpdateTime != null
        ? (now.difference(_lastUpdateTime!).inMilliseconds / 1000.0).clamp(0.05, 15.0)
        : 1.0;
    _lastUpdateTime = now;

    final speed = data.speed;
    final rpm = data.rpm;

    // Trapezoidal numerical integration for distance
    final avgSpeedForSlice = (_lastSpeed + speed) / 2.0;
    _lastSpeed = speed;

    // Calculate instantaneous fuel flow (L/h)
    final instantFuelLPerHour = _fuelCalculator.calculateFuelFlowLitersPerHour(
      rpm: rpm,
      engineLoadPercent: data.engineLoad > 0 ? data.engineLoad : 25.0,
      mafGramsPerSecond: data.maf > 0 ? data.maf : null,
      directFuelRateLPerHour: data.engineFuelRate > 0 ? data.engineFuelRate : null,
      throttlePositionPercent: data.throttlePosition,
      speedKmH: speed,
    );

    // Calculate instantaneous fuel economy (L/100km)
    final instantFuelL100km = _fuelCalculator.calculateLitersPer100Km(
      fuelFlowLitersPerHour: instantFuelLPerHour,
      speedKmH: speed,
    );

    // Incremental distance and fuel using trapezoidal average
    final deltaKm = (avgSpeedForSlice * dtSeconds) / 3600.0;
    final deltaFuelLiters = (instantFuelLPerHour * dtSeconds) / 3600.0;

    final newDistance = _activeTrip.distanceKm + deltaKm;
    final newFuelConsumed = _activeTrip.fuelConsumedLiters + deltaFuelLiters;

    final avgFuel = newDistance > 0.05
        ? (newFuelConsumed / newDistance) * 100.0
        : 0.0;

    _sampleCount++;
    _rpmSum += rpm;

    final duration = now.difference(_activeTrip.startTime);
    final hours = duration.inSeconds / 3600.0;
    final avgSpeed = hours > 0 ? newDistance / hours : speed.toDouble();

    final maxSpeed = speed > _activeTrip.maxSpeed ? speed.toDouble() : _activeTrip.maxSpeed;
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
    );

    notifyListeners();
  }

  Future<void> _finishTrip() async {
    final now = DateTime.now();
    final duration = now.difference(_activeTrip.startTime);

    // Only save trip if distance traveled satisfies the configured minimum distance threshold (default 10 km)
    final meetsDistanceThreshold = _activeTrip.distanceKm >= _minTripDistanceKm;
    final hasValidMovement = duration.inSeconds >= 5 || _activeTrip.distanceKm > 0.01;

    if (meetsDistanceThreshold && hasValidMovement) {
      final trip = Trip(
        id: '${_activeTrip.startTime.millisecondsSinceEpoch}',
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
      );

      await _historyService.saveTrip(trip);
      await _loadHistory();
      LogService.i(
        "Trip saved to history: ${trip.distanceKm.toStringAsFixed(2)} km, "
        "${trip.duration.inMinutes}m, avg fuel: ${trip.avgFuelConsumption.toStringAsFixed(1)} L/100km",
        tag: 'Trip',
      );
    } else {
      LogService.i(
        "Trip ended but discarded: ${_activeTrip.distanceKm.toStringAsFixed(2)} km "
        "(min threshold is $_minTripDistanceKm km)",
        tag: 'Trip',
      );
    }

    _activeTrip = ActiveTripState.initial();
    _lastUpdateTime = null;
    _lastSpeed = 0;
    _updateNotificationInfo();
    notifyListeners();
  }

  /// Manually starts a new driving trip immediately.
  void manualStartTrip() {
    if (!_activeTrip.isActive) {
      _startTrip();
    }
  }

  /// Manually ends the active trip and saves it to history.
  Future<void> manualEndTrip() async {
    if (_activeTrip.isActive) {
      await _finishTrip();
    }
  }

  Future<void> deleteTrip(String id) async {
    await _historyService.deleteTrip(id);
    await _loadHistory();
  }

  Future<void> clearHistory() async {
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
    _obdDataSubscription?.cancel();
    _boundObd?.removeListener(_onObdProviderNotification);
    _ticker?.cancel();
    super.dispose();
  }
}
