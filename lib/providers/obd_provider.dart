import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/obd/pid/pid_key.dart';
import 'package:redrive/obd/polling/polling_controller.dart';

import '../obd/demo/demo_data_generator.dart';
import '../obd/models/obd_data.dart';
import '../obd/connection/obd_connection.dart';
import '../obd/pid/pid_registry.dart';
import '../obd/source/live_obd_source.dart';
import '../obd/source/obd_source_state.dart';
import '../obd/elm/elm_response.dart';
import '../services/settings/app_preferences.dart';
import '../services/background_service.dart';

enum ObdMode { idle, demo, real }

enum ObdRecoveryStage { none, session, transport }

/// Coordinates OBD data sources and exposes vehicle data to the UI.
///
/// Manages Real/Demo modes, active watchlists, connection lifecycle,
/// and the latest decoded OBD data.
///
/// Low-level OBD communication is delegated to [LiveObdSource].
class ObdProvider extends ChangeNotifier {
  static const Set<PidKey> defaultSessionKeys = {
    PidKey.vehicleSpeed,
    PidKey.engineRpm,
    PidKey.coolantTemperature,
    PidKey.adapterVoltage,
    PidKey.engineLoad,
    PidKey.throttlePosition,
    PidKey.mafAirFlowRate,
    PidKey.engineFuelRate,
    PidKey.intakeAirTemperature,
    PidKey.shortTermFuelTrim1,
    PidKey.longTermFuelTrim1,
    PidKey.timingAdvance,
    PidKey.intakeManifoldPressure,
    PidKey.fuelSystemStatus,
    PidKey.fuelTankLevel,
  };

  ObdConnection? _connection;
  LiveObdSource? _liveSource;
  final PidRegistry _registry;
  DemoDataGenerator? _demoGenerator;

  ObdProvider({PidRegistry? registry}) : _registry = registry ?? PidRegistry() {
    _watchlists[WatchSource.session] = defaultSessionKeys;
  }

  StreamSubscription<({PidKey key, num value})>? _updatesSubscription;
  StreamSubscription<Map<PidKey, num>>? _cycleCompleteSubscription;
  StreamSubscription<ObdSourceState>? _stateSubscription;
  StreamSubscription<bool>? _connectionStateSubscription;
  StreamSubscription<bool>? _reconnectingStateSubscription;

  final _errorsController = StreamController<Object>.broadcast();
  Stream<Object> get errors => _errorsController.stream;

  final _dataController = StreamController<ObdData>.broadcast();
  Stream<ObdData> get dataStream => _dataController.stream;

  final _cycleController = StreamController<ObdData>.broadcast();
  Stream<ObdData> get cycleStream => _cycleController.stream;

  final Map<WatchSource, Set<PidKey>> _watchlists = {};

  bool get isDeviceConnected => _connection?.isConnected ?? false;

  ObdSourceState get state => _liveSource?.state ?? ObdSourceState.disconnected;

  bool get isReconnecting => _connection?.isReconnecting ?? false;

  bool _isResuming = false;
  bool _transportReconnectUsed = false;
  bool _hadData = false;

  DateTime? _lastSpeedTime;
  int _lastSpeedVal = 0;
  double _currentGForce = 0.0;

  ObdRecoveryStage get recoveryStage {
    if (isReconnecting) return ObdRecoveryStage.transport;
    if (_mode != ObdMode.real) return ObdRecoveryStage.none;
    if (state == ObdSourceState.recovering || state == ObdSourceState.error) {
      return ObdRecoveryStage.session;
    }
    if (_isResuming && state != ObdSourceState.polling) {
      return ObdRecoveryStage.session;
    }
    return ObdRecoveryStage.none;
  }

  bool get isEcuConnected =>
      _mode == ObdMode.real &&
      (state == ObdSourceState.polling ||
          (_hadData && recoveryStage != ObdRecoveryStage.none));

  ObdData _data = const ObdData();
  ObdData get data => _data;

  @visibleForTesting
  void setDataForTesting(ObdData data) {
    _data = data;
    notifyListeners();
  }

  VehicleProfile _vehicleProfile = VehicleProfile.defaultSuzukiSwiftM15A();
  VehicleProfile get vehicleProfile => _vehicleProfile;

  void applyVehicleProfile(VehicleProfile profile) {
    _vehicleProfile = profile;
    if (_data.fuelLevelPercent > 0) {
      final remainingL =
          (_data.fuelLevelPercent / 100.0) * _vehicleProfile.fuelTankCapacityLiters;
      final dte = _data.instantFuelL100km > 0.5
          ? (remainingL / _data.instantFuelL100km) * 100.0
          : (remainingL / 6.5) * 100.0;
      _data = _data.copyWith(
        remainingFuelLiters: remainingL,
        estimatedRangeKm: dte,
      );
    }
    _checkCoolantAlert(_data.coolantTemp);
    notifyListeners();
  }

  bool _isCoolantOverheating = false;
  bool get isCoolantOverheating => _isCoolantOverheating;

  void _checkCoolantAlert(int temp) {
    final overheatThreshold = _vehicleProfile.coolantOverheatTempC;
    final clearThreshold = overheatThreshold - 6;
    if (!_isCoolantOverheating && temp > overheatThreshold) {
      _isCoolantOverheating = true;
      notifyListeners();
      try {
        updateServiceNotification(
          title: '⚠️ ENGINE OVERHEAT ALERT',
          content: 'Coolant temperature is $temp°C! Reduce load immediately.',
        );
      } catch (_) {}
    } else if (_isCoolantOverheating && temp < clearThreshold) {
      _isCoolantOverheating = false;
      notifyListeners();
      try {
        updateServiceNotification(
          title: 'ReDrive Connected',
          content: 'Coolant normalized ($temp°C). Monitoring active.',
        );
      } catch (_) {}
    }
  }

  ObdMode _mode = ObdMode.idle;
  ObdMode get mode => _mode;

  void attachConnection(ObdConnection connection) {
    _connectionStateSubscription?.cancel();
    _reconnectingStateSubscription?.cancel();

    _connection = connection;

    _connectionStateSubscription = connection.connectionState.listen((
      isConnected,
    ) async {
      if (!isConnected) {
        unawaited(_handleTransportDisconnected());
      } else {
        notifyListeners();
        final autoConnect = await AppPreferences.isAutoConnectEnabled();
        if (autoConnect && _mode == ObdMode.idle && !isReconnecting) {
          unawaited(startRealMode());
        }
      }
    });

    _reconnectingStateSubscription = connection.reconnectingState.listen((
      isReconnecting,
    ) {
      if (isReconnecting) {
        unawaited(_handleReconnectStarted());
      } else {
        notifyListeners();
        if (_connection?.isConnected == true && _mode == ObdMode.real) {
          _startLiveSource();
        }
      }
    });

    notifyListeners();
  }

  void detachConnection() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _reconnectingStateSubscription?.cancel();
    _reconnectingStateSubscription = null;

    _connection = null;
    notifyListeners();
  }

  Future<void> startDemoMode() async {
    if (_mode == ObdMode.real || _mode == ObdMode.demo) return;

    _data = const ObdData();

    _demoGenerator = DemoDataGenerator();
    _demoGenerator!.start((ObdData newDemoData) {
      _data = newDemoData;
      _latestPidValues[PidKey.vehicleSpeed] = newDemoData.speed;
      _latestPidValues[PidKey.engineRpm] = newDemoData.rpm;
      _latestPidValues[PidKey.coolantTemperature] = newDemoData.coolantTemp;
      _latestPidValues[PidKey.adapterVoltage] = newDemoData.voltage;
      _latestPidValues[PidKey.engineLoad] = newDemoData.engineLoad;
      _latestPidValues[PidKey.throttlePosition] = newDemoData.throttlePosition;
      _latestPidValues[PidKey.mafAirFlowRate] = newDemoData.maf;
      _latestPidValues[PidKey.engineFuelRate] = newDemoData.engineFuelRate;
      // Simulated expanded sensors for demo mode
      _latestPidValues[PidKey.intakeAirTemperature] = 24.0 + (newDemoData.coolantTemp > 85 ? 4.0 : 0.0);
      _latestPidValues[PidKey.intakeManifoldPressure] = 30.0 + (newDemoData.engineLoad * 0.65);
      _latestPidValues[PidKey.timingAdvance] = 12.0 + (newDemoData.rpm / 400.0);
      _latestPidValues[PidKey.shortTermFuelTrim1] = -1.5 + (newDemoData.speed % 4);
      _latestPidValues[PidKey.longTermFuelTrim1] = 0.8;
      _latestPidValues[PidKey.fuelPressure] = 380.0;
      _latestPidValues[PidKey.fuelTankLevel] = 68.5;
      _latestPidValues[PidKey.barometricPressure] = 101.3;
      _latestPidValues[PidKey.controlModuleVoltage] = newDemoData.voltage - 0.2;
      _latestPidValues[PidKey.ambientAirTemperature] = 18.0;
      _latestPidValues[PidKey.engineOilTemperature] = newDemoData.coolantTemp + 5.0;
      _latestPidValues[PidKey.runTimeSinceStart] = 480.0;
      _latestPidValues[PidKey.fuelSystemStatus] = 2.0;
      if (!_dataController.isClosed) {
        _dataController.add(_data);
      }
      if (!_cycleController.isClosed) {
        _cycleController.add(_data);
      }
      _checkCoolantAlert(newDemoData.coolantTemp);
      notifyListeners();
    });

    _mode = ObdMode.demo;
    notifyListeners();
  }

  Future<void> stopDemoMode() async {
    if (_mode != ObdMode.demo) return;

    _demoGenerator?.stop();
    _demoGenerator = null;

    _mode = ObdMode.idle;
    _data = const ObdData();
    _latestPidValues.clear();

    notifyListeners();
  }

  Future<void> startRealMode() async {
    if (_connection == null || _mode == ObdMode.real || isReconnecting) {
      return;
    }

    if (_mode == ObdMode.demo) {
      _demoGenerator?.stop();
      _demoGenerator = null;
      _data = const ObdData();
    }

    _transportReconnectUsed = false;
    _isResuming = false;
    _hadData = false;

    _mode = ObdMode.real;
    notifyListeners();

    try {
      await _startLiveSource();
    } catch (_) {
      await _stopLive();
      _mode = ObdMode.idle;
      notifyListeners();
    }
  }

  Future<void> stopRealMode() async {
    if (_mode != ObdMode.real) return;

    _mode = ObdMode.idle;
    _transportReconnectUsed = false;
    _isResuming = false;
    _hadData = false;

    await _stopLive();

    _data = const ObdData();
    notifyListeners();
  }

  String _preferredProtocol = 'ATSP0';
  String get preferredProtocol => _preferredProtocol;

  void setPreferredProtocol(String protocol) {
    if (_preferredProtocol == protocol) return;
    _preferredProtocol = protocol;
    notifyListeners();
  }

  Future<void> _startLiveSource() async {
    await _stopLive();

    final source = LiveObdSource(
      connection: _connection!,
      registry: _registry,
      protocolCommand: _preferredProtocol,
    );

    for (final entry in _watchlists.entries) {
      source.setWatchlist(entry.key, entry.value);
    }

    _liveSource = source;

    _stateSubscription = source.stateStream.listen((_) {
      notifyListeners();
    });

    _updatesSubscription = source.updates.listen(
      _onUpdate,
      onError: _onLiveError,
    );

    _cycleCompleteSubscription = source.onCycleComplete.listen((_) {
      if (!_cycleController.isClosed) {
        _cycleController.add(_data);
      }
    });

    await source.start();
  }

  Future<void> _onLiveError(Object error, StackTrace _) async {
    if (_errorsController.isClosed || _mode != ObdMode.real || isReconnecting) {
      return;
    }

    if (!_transportReconnectUsed) {
      _transportReconnectUsed = true;
      await _connection?.reconnect();
      return;
    }

    _isResuming = false;
    _transportReconnectUsed = false;
    _hadData = false;
    _mode = ObdMode.idle;
    await _stopLive();
    _data = const ObdData();
    _errorsController.add(error);
    notifyListeners();
  }

  Future<void> _stopLive() async {
    await _stateSubscription?.cancel();
    _stateSubscription = null;

    await _updatesSubscription?.cancel();
    _updatesSubscription = null;

    await _cycleCompleteSubscription?.cancel();
    _cycleCompleteSubscription = null;

    if (_liveSource != null) {
      await _liveSource?.stop();
      await _liveSource?.dispose();
      _liveSource = null;
    }
  }

  Future<void> _handleReconnectStarted() async {
    if (_mode != ObdMode.real) {
      notifyListeners();
      return;
    }

    _isResuming = true;
    await _stopLive();

    notifyListeners();
  }

  Future<void> _handleTransportDisconnected() async {
    final wasResuming = _isResuming;
    await _stopLive();

    _isResuming = false;
    _transportReconnectUsed = false;
    _hadData = false;
    _mode = ObdMode.idle;
    _data = const ObdData();

    if (wasResuming && !_errorsController.isClosed) {
      _errorsController.add(StateError('Bluetooth reconnect failed'));
    }

    notifyListeners();
  }

  void setWatchlist(WatchSource source, Set<PidKey> keys) {
    if (keys.isEmpty) {
      _watchlists.remove(source);
    } else {
      _watchlists[source] = Set.unmodifiable(keys);
    }

    _liveSource?.setWatchlist(source, keys);
  }

  void clearWatchlist(WatchSource source) {
    setWatchlist(source, const {});
  }

  Set<PidKey> get supportedKeys => _liveSource?.supportedKeys ?? const {};
  Set<int> get rawSupportedPids => _liveSource?.rawSupportedPids ?? const {};

  final Map<PidKey, num> _latestPidValues = {};
  Map<PidKey, num> get latestPidValues => Map.unmodifiable(_latestPidValues);
  num? getPidValue(PidKey key) => _latestPidValues[key];

  Future<ElmResponse> executeCommand(String command) async {
    if (_liveSource == null) {
      throw StateError('Live OBD session is not active');
    }
    return _liveSource!.executeCommand(command);
  }

  void _onUpdate(({PidKey key, num value}) update) {
    _isResuming = false;
    _transportReconnectUsed = false;
    _hadData = true;
    _latestPidValues[update.key] = update.value;

    switch (update.key) {
      case PidKey.engineRpm:
        _data = _data.copyWith(rpm: update.value.toInt());

      case PidKey.vehicleSpeed:
        final newSpeed = update.value.toInt();
        final now = DateTime.now();
        if (_lastSpeedTime != null) {
          final dtSec = now.difference(_lastSpeedTime!).inMicroseconds / 1000000.0;
          if (dtSec > 0.08 && dtSec < 2.5) {
            final dvMps = (newSpeed - _lastSpeedVal) * (1000.0 / 3600.0);
            final instG = (dvMps / dtSec) / 9.80665;
            _currentGForce = (_currentGForce * 0.65) + (instG.clamp(-1.5, 1.5) * 0.35);
          }
        }
        _lastSpeedTime = now;
        _lastSpeedVal = newSpeed;
        _data = _data.copyWith(speed: newSpeed, accelerationG: _currentGForce);

      case PidKey.coolantTemperature:
        final temp = update.value.toInt();
        _data = _data.copyWith(coolantTemp: temp);
        _checkCoolantAlert(temp);

      case PidKey.adapterVoltage:
        _data = _data.copyWith(voltage: update.value.toDouble());

      case PidKey.engineLoad:
        _data = _data.copyWith(engineLoad: update.value.toDouble());

      case PidKey.throttlePosition:
        _data = _data.copyWith(throttlePosition: update.value.toDouble());

      case PidKey.mafAirFlowRate:
        _data = _data.copyWith(maf: update.value.toDouble());

      case PidKey.engineFuelRate:
        _data = _data.copyWith(engineFuelRate: update.value.toDouble());

      case PidKey.intakeAirTemperature:
        _data = _data.copyWith(intakeAirTemp: update.value.toInt());

      case PidKey.shortTermFuelTrim1:
        _data = _data.copyWith(shortTermFuelTrim: update.value.toDouble());

      case PidKey.longTermFuelTrim1:
        _data = _data.copyWith(longTermFuelTrim: update.value.toDouble());

      case PidKey.timingAdvance:
        _data = _data.copyWith(timingAdvance: update.value.toDouble());

      case PidKey.intakeManifoldPressure:
        _data = _data.copyWith(manifoldPressure: update.value.toDouble());

      case PidKey.fuelTankLevel:
        final pct = update.value.toDouble().clamp(0.0, 100.0);
        final remainingL = (pct / 100.0) * _vehicleProfile.fuelTankCapacityLiters;
        final dte = _data.instantFuelL100km > 0.5
            ? (remainingL / _data.instantFuelL100km) * 100.0
            : (remainingL / 6.5) * 100.0;
        _data = _data.copyWith(
          fuelLevelPercent: pct,
          remainingFuelLiters: remainingL,
          estimatedRangeKm: dte,
        );

      case PidKey.fuelSystemStatus:
        _data = _data.copyWith(fuelSystemStatus: FuelSystemStatus.fromNumeric(update.value));

      default:
        break;
    }

    // Zero-Overhead Derived Metrics calculation
    final idleBase = _vehicleProfile.idleThrottleBaselinePercent;
    final wotBase = _vehicleProfile.wotThrottleBaselinePercent > idleBase
        ? _vehicleProfile.wotThrottleBaselinePercent
        : 85.0;
    final relThrottle =
        ((_data.throttlePosition - idleBase) / (wotBase - idleBase) * 100.0)
            .clamp(0.0, 100.0);
    final hpClamp = _vehicleProfile.maxHorsepower > 102
        ? (_vehicleProfile.maxHorsepower * 1.25)
        : 130.0;
    final hp = _data.maf > 0 ? (_data.maf * 1.25).clamp(0.0, hpClamp) : 0.0;
    final kw = hp * 0.7457;
    final torque = (_data.rpm > 500) ? ((kw * 9549.0) / _data.rpm).clamp(0.0, 180.0) : 0.0;

    final isThrottleClosed = _data.throttlePosition < 1.5 ||
        (_data.throttlePosition >= 10.0 && _data.throttlePosition <= 15.0) ||
        (_data.throttlePosition >= (idleBase - 3.0) &&
            _data.throttlePosition <= (idleBase + 2.0)) ||
        relThrottle <= 0.5;
    final isDfco = _data.speed > 20 &&
        _data.rpm > 1300 &&
        isThrottleClosed &&
        _data.engineLoad < 18.0;

    _data = _data.copyWith(
      relativeThrottle: relThrottle,
      horsepower: hp,
      torqueNm: torque,
      isDfcoActive: isDfco,
    );

    if (!_dataController.isClosed) {
      _dataController.add(_data);
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _demoGenerator?.stop();
    _stateSubscription?.cancel();
    _updatesSubscription?.cancel();
    _cycleCompleteSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _reconnectingStateSubscription?.cancel();
    _errorsController.close();
    _dataController.close();
    _cycleController.close();

    super.dispose();
  }
}
