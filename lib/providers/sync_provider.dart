import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:redrive/core/theme/custom_dashboard_theme.dart';
import 'package:redrive/core/theme/theme_engine.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/providers/garage_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/trip_provider.dart';
import 'package:redrive/core/app_flavor.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/services/sync/network_sync_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presentation and state management provider coordinating Bluetooth synchronization,
/// parked car snapshot tracking, and DTC mechanic diagnostic report generation.
class SyncProvider extends ChangeNotifier {
  final BluetoothSyncService _syncService;
  BluetoothSyncService get syncService => _syncService;

  late final NetworkSyncManager _networkSyncManager;
  NetworkSyncManager get networkSyncManager => _networkSyncManager;

  SyncConnectionState get connectionState => _syncService.state;
  DateTime? get lastSyncTime => _syncService.lastSyncTime;
  String? get lastError => _syncService.lastError ?? _networkSyncManager.lastError;
  ParkedCarSnapshot? get latestSnapshot => _syncService.latestSnapshot;
  MechanicDiagnosticReport? get latestMechanicReport =>
      _syncService.latestMechanicReport;

  TripProvider? _tripProvider;
  GarageProvider? _garageProvider;
  ObdProvider? _obdProvider;
  ThemeEngine? _themeEngine;

  bool _isDisposed = false;
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  SyncProvider({
    BluetoothSyncService? syncService,
    ThemeEngine? themeEngine,
    NetworkSyncManager? networkSyncManager,
  })  : _syncService = syncService ??
            BluetoothSyncService(
              deviceId: 'redrive_device_${DateTime.now().millisecondsSinceEpoch}',
              deviceRole: 'headunit',
            ),
        _themeEngine = themeEngine {
    _networkSyncManager = networkSyncManager ??
        NetworkSyncManager(
          syncService: _syncService,
          isHeadunit: _syncService.deviceRole == 'headunit',
        );
    _networkSyncManager.addListener(_onServiceStateChanged);
    _syncService.onStateChanged = _onServiceStateChanged;
    _init();
  }

  Future<void> _init() async {
    try {
      await _syncService.loadPersistedState();
      await loadRetentionSettings();
      _setupDelegate();
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  void _onServiceStateChanged() {
    if (_isDisposed) return;

    // Fail-safe: When phone companion disconnects from Headunit,
    // ensure we have a valid parked snapshot coordinate.
    if (_syncService.state == SyncConnectionState.disconnected &&
        AppConfig.isPhone) {
      _checkPhoneDisconnectFallback();
    }

    notifyListeners();
  }

  Future<void> _checkPhoneDisconnectFallback() async {
    final snap = latestSnapshot;
    final now = DateTime.now();
    final isStale = snap == null ||
        snap.latitude == null ||
        now.difference(snap.timestamp).inSeconds > 45;
    if (isStale) {
      final fix = _tripProvider?.latestGpsFix;
      if (fix != null) {
        final fallback = (snap ??
                ParkedCarSnapshot(
                  timestamp: now,
                  vehicleId: _garageProvider?.activeProfileId ?? '',
                  vehicleName:
                      _garageProvider?.activeProfile.name ?? 'My Vehicle',
                ))
            .copyWith(
          latitude: fix.latitude,
          longitude: fix.longitude,
          timestamp: now,
        );
        await _syncService.updateParkedSnapshot(fallback);
        notifyListeners();
      }
    }
  }

  /// Binds related providers to enable seamless sync data exchange
  /// and parked car snapshot capture on trip end / ignition off.
  void bindProviders({
    required TripProvider tripProvider,
    required GarageProvider garageProvider,
    ObdProvider? obdProvider,
    ThemeEngine? themeEngine,
  }) {
    if (_tripProvider != tripProvider ||
        _garageProvider != garageProvider ||
        _obdProvider != obdProvider ||
        _themeEngine != themeEngine) {
      _tripProvider = tripProvider;
      _garageProvider = garageProvider;
      _obdProvider = obdProvider;
      _themeEngine = themeEngine ?? _themeEngine;

      _setupDelegate();
      _listenToTripProvider(tripProvider);
    }
  }

  void _setupDelegate() {
    _syncService.registerDelegate(
      SyncDataDelegate(
        getLocalTrips: () async {
          return _tripProvider?.pastTrips ?? <Trip>[];
        },
        getTimeseriesLines: (tripId) async {
          final tp = _tripProvider;
          if (tp == null) return [];
          return await tp.timeseriesService.readRawLines(tripId);
        },
        onTripReceived: (trip, timeseriesLines) async {
          final tp = _tripProvider;
          if (tp != null) {
            await tp.ingestSyncedTrip(trip, timeseriesLines: timeseriesLines);
          }
        },
        onTripsAcked: (syncedTripIds, syncedTimeseriesIds) async {
          final tp = _tripProvider;
          if (tp != null) {
            await tp.markTripsAsSynced(syncedTripIds);
          }
        },
        getParkedSnapshot: () async {
          return _syncService.latestSnapshot;
        },
        onParkedSnapshotReceived: (snapshot) async {
          // Snapshot state is saved inside syncService
          notifyListeners();
        },
        getMechanicReport: () async {
          return _syncService.latestMechanicReport;
        },
        onMechanicReportReceived: (report) async {
          notifyListeners();
        },
        getGarageData: () async {
          final gp = _garageProvider;
          if (gp == null) {
            return (vehicles: <VehicleProfile>[], activeVehicleId: '');
          }
          return (
            vehicles: gp.profiles,
            activeVehicleId: gp.activeProfile.id,
          );
        },
        onGarageDataReceived: (vehicles, activeVehicleId) async {
          final gp = _garageProvider;
          if (gp != null && vehicles.isNotEmpty) {
            for (final v in vehicles) {
              await gp.saveProfile(v);
            }
            if (activeVehicleId.isNotEmpty) {
              await gp.selectActiveProfile(activeVehicleId);
            }
          }
        },
        onThemeReceived: (themePayload) async {
          final te = _themeEngine;
          if (te != null) {
            final theme = CustomDashboardTheme.fromJson(themePayload);
            await te.applyTheme(theme);
          }
        },
      ),
    );
  }

  /// Pushes a custom theme to the peer headunit over Bluetooth.
  Future<bool> pushCustomTheme(CustomDashboardTheme theme) async {
    return _syncService.pushCustomTheme(theme.toJson());
  }

  String? _lastTrackedTripId;

  void _listenToTripProvider(TripProvider tripProvider) {
    tripProvider.onTripFinished = (trip) async {
      final gp = _garageProvider;
      if (gp != null) {
        final profile = gp.activeProfile;
        if (profile.fuelLevelSource == FuelLevelSource.virtualTank) {
          await gp.deductFuel(trip.fuelConsumedLiters);
        }
      }
      await captureParkedSnapshot();
    };

    tripProvider.onSpeedZeroStandstill = () async {
      await captureParkedSnapshot();
    };

    tripProvider.addListener(() {
      final active = tripProvider.activeTrip;
      // When a trip was active and ends, or when pastTrips has a new completed trip:
      if (!active.isActive && tripProvider.pastTrips.isNotEmpty) {
        final newest = tripProvider.pastTrips.first;
        if (newest.id != _lastTrackedTripId) {
          _lastTrackedTripId = newest.id;
          captureParkedSnapshot();
        }
      }
    });
  }

  /// Captures a fresh [ParkedCarSnapshot] from current OBD telemetry, GPS fix,
  /// and active vehicle profile.
  Future<ParkedCarSnapshot?> captureParkedSnapshot() async {
    final gp = _garageProvider;
    final tp = _tripProvider;
    final obd = _obdProvider;
    final profile = gp?.activeProfile ?? VehicleProfile.defaultSuzukiSwiftM15A();

    final fix = tp?.latestGpsFix;
    final obdData = obd?.data;
    final now = DateTime.now();

    final double remainingFuelLiters;
    final double fuelLevelPercent;
    final double estimatedRangeKm;

    switch (profile.fuelLevelSource) {
      case FuelLevelSource.virtualTank:
        remainingFuelLiters = profile.virtualTankCurrentLiters ??
            (obdData?.remainingFuelLiters ?? 0.0);
        fuelLevelPercent = profile.virtualFuelPercent ??
            (obdData?.fuelLevelPercent ?? 0.0);
        const nominalEconomy = 6.8;
        estimatedRangeKm = remainingFuelLiters > 0
            ? (remainingFuelLiters / nominalEconomy) * 100.0
            : (obdData?.estimatedRangeKm ?? 0.0);
        break;
      case FuelLevelSource.none:
        remainingFuelLiters = 0.0;
        fuelLevelPercent = 0.0;
        estimatedRangeKm = 0.0;
        break;
      case FuelLevelSource.obdPid:
        remainingFuelLiters = obdData?.remainingFuelLiters ?? 0.0;
        fuelLevelPercent = obdData?.fuelLevelPercent ?? 0.0;
        estimatedRangeKm = obdData?.estimatedRangeKm ?? 0.0;
        break;
    }

    final snapshot = ParkedCarSnapshot(
      timestamp: now,
      vehicleId: profile.id,
      vehicleName: profile.name,
      latitude: fix?.latitude,
      longitude: fix?.longitude,
      remainingFuelLiters: remainingFuelLiters,
      fuelLevelPercent: fuelLevelPercent,
      estimatedRangeKm: estimatedRangeKm,
      batteryVoltage: obdData?.voltage ?? 12.6,
      coolantTempC: (obdData?.coolantTemp ?? 20).toDouble(),
      odometerKm: tp?.effectiveOdometerKm ?? profile.baseOdometerKm,
      lastTripId: tp?.pastTrips.isNotEmpty == true ? tp!.pastTrips.first.id : null,
    );

    await _syncService.updateParkedSnapshot(snapshot);
    notifyListeners();
    return snapshot;
  }

  /// Generates a fresh [MechanicDiagnosticReport] and stores/broadcasts it.
  Future<MechanicDiagnosticReport> generateMechanicReport({
    List<DtcCode> storedDtcs = const [],
    List<DtcCode> pendingDtcs = const [],
  }) async {
    final gp = _garageProvider;
    final tp = _tripProvider;
    final profile = gp?.activeProfile ?? VehicleProfile.defaultSuzukiSwiftM15A();
    final odo = tp?.effectiveOdometerKm ?? profile.baseOdometerKm;
    final trips = tp?.pastTrips ?? <Trip>[];

    final report = await _syncService.generateMechanicReport(
      vehicle: profile,
      currentOdometerKm: odo,
      storedDtcs: storedDtcs,
      pendingDtcs: pendingDtcs,
      recentTrips: trips,
    );
    notifyListeners();
    return report;
  }

  /// Connects to a [SyncTransport] (e.g. RFCOMM or memory test pair).
  Future<void> attachTransport(
    SyncTransport transport, {
    bool initiateHandshake = false,
  }) async {
    await _syncService.attachTransport(
      transport,
      initiateHandshake: initiateHandshake,
    );
    notifyListeners();
  }

  /// Disconnects transport.
  Future<void> detachTransport() async {
    await _syncService.detachTransport();
    notifyListeners();
  }

  /// Triggers a manual sync session.
  Future<void> startSyncSession() async {
    await _syncService.startSyncSession();
    notifyListeners();
  }

  /// Starts the Headunit TCP Sync Server.
  Future<bool> startNetworkSyncServer({int port = NetworkSyncManager.defaultPort}) {
    return _networkSyncManager.startServer(port: port);
  }

  /// Stops the Headunit TCP Sync Server.
  Future<void> stopNetworkSyncServer() {
    return _networkSyncManager.stopServer();
  }

  static const String prefRawBlackboxDaysKey = 'sync_pref_raw_blackbox_retention_days';
  static const String prefTripSummaryDaysKey = 'sync_pref_trip_summary_retention_days';

  int _rawBlackboxRetentionDays = 30; // 0 = keep forever
  int get rawBlackboxRetentionDays => _rawBlackboxRetentionDays;

  int _tripSummaryRetentionDays = 0; // 0 = keep forever
  int get tripSummaryRetentionDays => _tripSummaryRetentionDays;

  /// Loads retention preferences from [SharedPreferences].
  Future<void> loadRetentionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rawBlackboxRetentionDays = prefs.getInt(prefRawBlackboxDaysKey) ?? 30;
      _tripSummaryRetentionDays = prefs.getInt(prefTripSummaryDaysKey) ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  /// Updates and persists configurable storage retention thresholds.
  Future<void> updateRetentionSettings({
    int? rawBlackboxDays,
    int? tripSummaryDays,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (rawBlackboxDays != null) {
      _rawBlackboxRetentionDays = rawBlackboxDays;
      await prefs.setInt(prefRawBlackboxDaysKey, rawBlackboxDays);
    }
    if (tripSummaryDays != null) {
      _tripSummaryRetentionDays = tripSummaryDays;
      await prefs.setInt(prefTripSummaryDaysKey, tripSummaryDays);
    }
    notifyListeners();
  }

  /// Connects to the Headunit TCP Sync Server from Phone Companion.
  Future<bool> connectNetworkSync({
    String host = NetworkSyncManager.defaultAndroidAutoGateway,
    int port = NetworkSyncManager.defaultPort,
  }) {
    return _networkSyncManager.connectToHeadunit(host: host, port: port);
  }

  LinkSelfTestReport? _overrideSelfTestReport;
  @visibleForTesting
  set overrideSelfTestReport(LinkSelfTestReport? report) {
    _overrideSelfTestReport = report;
  }

  int? _overridePingLatency;
  @visibleForTesting
  set overridePingLatency(int? ping) {
    _overridePingLatency = ping;
  }

  /// Runs the comprehensive 4-step link self-test from the Phone Companion perspective.
  Future<LinkSelfTestReport> runLinkSelfTest({
    String host = NetworkSyncManager.defaultAndroidAutoGateway,
    int port = NetworkSyncManager.defaultPort,
  }) {
    if (_overrideSelfTestReport != null) {
      return Future.value(_overrideSelfTestReport!);
    }
    return _networkSyncManager.runLinkSelfTest(host: host, port: port);
  }

  /// Probes TCP reachability and ping latency to the Headunit server without keeping a socket open.
  Future<int?> pingHeadunit({
    String host = NetworkSyncManager.defaultAndroidAutoGateway,
    int port = NetworkSyncManager.defaultPort,
  }) {
    if (_overridePingLatency != null) {
      return Future.value(_overridePingLatency);
    }
    return _networkSyncManager.pingHeadunit(host: host, port: port);
  }

  /// Checks whether phone is connected to the in-car Android Auto subnet (192.168.43.x).
  Future<bool> isAndroidAutoSubnetActive() {
    return _networkSyncManager.isAndroidAutoSubnetActive();
  }

  /// Connects and triggers sync with 15s budget and a single 2s boot retry.
  Future<bool> smartSyncWithHeadunit({
    String host = NetworkSyncManager.defaultAndroidAutoGateway,
    int port = NetworkSyncManager.defaultPort,
  }) {
    return _networkSyncManager.smartSyncWithHeadunit(host: host, port: port);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _networkSyncManager.removeListener(_onServiceStateChanged);
    _networkSyncManager.dispose();
    _syncService.dispose();
    super.dispose();
  }
}
