import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/services/logging/log_service.dart';
import 'package:redrive/services/sync/sync_protocol.dart';

/// Represents the current state of the Bluetooth RFCOMM Headunit ↔ Phone sync engine.
enum SyncConnectionState {
  disconnected,
  listening,
  connecting,
  connected,
  syncing,
  synced,
  error,
}

/// Abstract bidirectional byte stream transport for Headunit ↔ Phone synchronization
/// (implemented by Bluetooth RFCOMM sockets in production and `InMemorySyncTransportPair` in tests).
abstract class SyncTransport {
  Stream<List<int>> get inboundBytes;
  void sendBytes(List<int> bytes);
  Future<void> close();
}

/// In-memory connected pair of [SyncTransport] endpoints for deterministic unit and widget testing
/// as well as Demo Mode synchronization.
class InMemorySyncTransportPair {
  final _HeadunitToPhoneController _headunit;
  final _HeadunitToPhoneController _phone;

  InMemorySyncTransportPair._(this._headunit, this._phone);

  factory InMemorySyncTransportPair() {
    final hToP = StreamController<List<int>>.broadcast();
    final pToH = StreamController<List<int>>.broadcast();
    final headunit = _HeadunitToPhoneController(
      inbound: pToH.stream,
      outbound: hToP,
    );
    final phone = _HeadunitToPhoneController(
      inbound: hToP.stream,
      outbound: pToH,
    );
    return InMemorySyncTransportPair._(headunit, phone);
  }

  SyncTransport get headunitTransport => _headunit;
  SyncTransport get phoneTransport => _phone;

  Future<void> close() async {
    await _headunit.close();
    await _phone.close();
  }
}

class _HeadunitToPhoneController implements SyncTransport {
  final Stream<List<int>> _inbound;
  final StreamController<List<int>> _outbound;
  bool _closed = false;

  _HeadunitToPhoneController({
    required Stream<List<int>> inbound,
    required StreamController<List<int>> outbound,
  })  : _inbound = inbound,
        _outbound = outbound;

  @override
  Stream<List<int>> get inboundBytes => _inbound;

  @override
  void sendBytes(List<int> bytes) {
    if (!_closed && !_outbound.isClosed) {
      _outbound.add(Uint8List.fromList(bytes));
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (!_outbound.isClosed) {
      await _outbound.close();
    }
  }
}

/// Callback interface providing local state to [BluetoothSyncService] and receiving
/// synced payloads from the peer device.
class SyncDataDelegate {
  final Future<List<Trip>> Function() getLocalTrips;
  final Future<List<String>> Function(String tripId) getTimeseriesLines;
  final Future<void> Function(Trip trip, List<String>? timeseriesLines)
      onTripReceived;
  final Future<void> Function(
    List<String> syncedTripIds,
    List<String> syncedTimeseriesIds,
  ) onTripsAcked;
  final Future<ParkedCarSnapshot?> Function() getParkedSnapshot;
  final Future<void> Function(ParkedCarSnapshot snapshot)
      onParkedSnapshotReceived;
  final Future<MechanicDiagnosticReport?> Function() getMechanicReport;
  final Future<void> Function(MechanicDiagnosticReport report)
      onMechanicReportReceived;
  final Future<({List<VehicleProfile> vehicles, String activeVehicleId})>
      Function() getGarageData;
  final Future<void> Function(
    List<VehicleProfile> vehicles,
    String activeVehicleId,
  ) onGarageDataReceived;

  const SyncDataDelegate({
    required this.getLocalTrips,
    required this.getTimeseriesLines,
    required this.onTripReceived,
    required this.onTripsAcked,
    required this.getParkedSnapshot,
    required this.onParkedSnapshotReceived,
    required this.getMechanicReport,
    required this.onMechanicReportReceived,
    required this.getGarageData,
    required this.onGarageDataReceived,
  });
}

/// Manages Bluetooth RFCOMM / stream-based synchronization between the ReDrive
/// Headunit (`deviceRole: 'headunit'`) and Phone Companion (`deviceRole: 'phone'`),
/// as well as local persistence of the latest [ParkedCarSnapshot] and [MechanicDiagnosticReport].
class BluetoothSyncService {
  final String deviceId;
  final String deviceRole; // 'headunit' or 'phone'
  final File? customStateFile;
  final bool inMemory;

  BluetoothSyncService({
    required this.deviceId,
    required this.deviceRole,
    this.customStateFile,
    this.inMemory = false,
  });

  SyncTransport? _transport;
  StreamSubscription<SyncFrame>? _frameSubscription;
  SyncDataDelegate? _delegate;

  SyncConnectionState _state = SyncConnectionState.disconnected;
  SyncConnectionState get state => _state;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  String? _lastError;
  String? get lastError => _lastError;

  ParkedCarSnapshot? _latestSnapshot;
  ParkedCarSnapshot? get latestSnapshot => _latestSnapshot;

  MechanicDiagnosticReport? _latestMechanicReport;
  MechanicDiagnosticReport? get latestMechanicReport => _latestMechanicReport;

  // Reassembly buffers for incoming trips and chunked .jsonl timeseries
  final Map<String, Trip> _pendingReceivedTrips = {};
  final Map<String, List<SyncFrame>> _pendingTimeseriesChunks = {};
  final Set<String> _expectedTripIds = {};
  final Set<String> _expectedTimeseriesIds = {};
  final List<String> _completedSyncedTripIds = [];
  final List<String> _completedSyncedTimeseriesIds = [];
  Completer<void>? _activeSyncCompleter;

  void Function()? onStateChanged;

  void registerDelegate(SyncDataDelegate delegate) {
    _delegate = delegate;
  }

  Future<File> get _stateFile async {
    if (customStateFile != null) return customStateFile!;
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      final xdgData = Platform.environment['XDG_DATA_HOME'];
      final dataPath = xdgData != null && xdgData.isNotEmpty
          ? xdgData
          : '$home/.local/share/redrive';
      dir = Directory(dataPath);
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/companion_sync_state.json');
  }

  /// Loads persisted [ParkedCarSnapshot], [MechanicDiagnosticReport], and `lastSyncTime`.
  Future<void> loadPersistedState() async {
    if (inMemory) return;
    try {
      final file = await _stateFile;
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        if (decoded['latestSnapshot'] is Map) {
          _latestSnapshot = ParkedCarSnapshot.fromJson(
            Map<String, dynamic>.from(decoded['latestSnapshot'] as Map),
          );
        }
        if (decoded['latestMechanicReport'] is Map) {
          _latestMechanicReport = MechanicDiagnosticReport.fromJson(
            Map<String, dynamic>.from(decoded['latestMechanicReport'] as Map),
          );
        }
        if (decoded['lastSyncTime'] != null) {
          _lastSyncTime = DateTime.tryParse(decoded['lastSyncTime'].toString());
        }
        onStateChanged?.call();
      }
    } catch (e) {
      LogService.w('Failed to load companion sync state: $e', tag: 'Sync');
    }
  }

  /// Persists the current [ParkedCarSnapshot], [MechanicDiagnosticReport], and `lastSyncTime`.
  Future<void> savePersistedState() async {
    if (inMemory) return;
    try {
      final file = await _stateFile;
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final payload = <String, dynamic>{
        if (_latestSnapshot != null)
          'latestSnapshot': _latestSnapshot!.toJson(),
        if (_latestMechanicReport != null)
          'latestMechanicReport': _latestMechanicReport!.toJson(),
        if (_lastSyncTime != null)
          'lastSyncTime': _lastSyncTime!.toIso8601String(),
      };
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      LogService.w('Failed to save companion sync state: $e', tag: 'Sync');
    }
  }

  /// Updates and persists the latest [ParkedCarSnapshot] (e.g., when ignition turns off).
  Future<void> updateParkedSnapshot(ParkedCarSnapshot snapshot) async {
    _latestSnapshot = snapshot;
    await savePersistedState();
    onStateChanged?.call();
    if (_transport != null &&
        (_state == SyncConnectionState.connected ||
            _state == SyncConnectionState.synced)) {
      _sendFrame(SyncFrame.parkedSnapshot(snapshot));
    }
  }

  /// Updates and persists the latest [MechanicDiagnosticReport].
  Future<void> updateMechanicReport(MechanicDiagnosticReport report) async {
    _latestMechanicReport = report;
    await savePersistedState();
    onStateChanged?.call();
    if (_transport != null &&
        (_state == SyncConnectionState.connected ||
            _state == SyncConnectionState.synced)) {
      _sendFrame(SyncFrame.mechanicReport(report));
    }
  }

  /// Builds a fresh [MechanicDiagnosticReport] from the active vehicle, stored/pending DTCs,
  /// recent anomalies across trips, and latest parked snapshot.
  Future<MechanicDiagnosticReport> generateMechanicReport({
    required VehicleProfile vehicle,
    required double currentOdometerKm,
    required List<DtcCode> storedDtcs,
    required List<DtcCode> pendingDtcs,
    required List<Trip> recentTrips,
    int attachedSampleCount = 0,
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    final recentAnomalies = <TripAnomalyEpisode>[];
    for (final trip in recentTrips.take(5)) {
      recentAnomalies.addAll(trip.anomalies);
    }
    final report = MechanicDiagnosticReport(
      reportId: 'report_${ts.millisecondsSinceEpoch}',
      generatedAt: ts,
      vehicle: vehicle,
      currentOdometerKm: currentOdometerKm,
      storedDtcs: storedDtcs,
      pendingDtcs: pendingDtcs,
      recentAnomalies: recentAnomalies,
      latestSnapshot: _latestSnapshot,
      attachedTripId: recentTrips.isNotEmpty ? recentTrips.first.id : null,
      attachedSampleCount: attachedSampleCount,
    );
    await updateMechanicReport(report);
    return report;
  }

  /// Attaches an active [SyncTransport] (e.g. Bluetooth RFCOMM socket or test pair)
  /// and starts listening for incoming [SyncFrame] messages.
  Future<void> attachTransport(
    SyncTransport transport, {
    bool initiateHandshake = false,
  }) async {
    await detachTransport();
    _transport = transport;
    _setState(SyncConnectionState.connected);

    _frameSubscription = transport.inboundBytes
        .transform(SyncProtocolCodec.frameDecoder())
        .listen(
          _onFrameReceived,
          onError: (Object err) {
            _lastError = err.toString();
            _setState(SyncConnectionState.error);
          },
          onDone: () {
            if (_state != SyncConnectionState.disconnected) {
              _setState(SyncConnectionState.disconnected);
            }
          },
        );

    if (initiateHandshake) {
      await startSyncSession();
    }
  }

  /// Detaches the active transport and resets connection state.
  Future<void> detachTransport() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    final old = _transport;
    _transport = null;
    if (old != null) {
      await old.close();
    }
    _setState(SyncConnectionState.disconnected);
  }

  /// Initiates a bidirectional sync session over the attached [SyncTransport].
  Future<void> startSyncSession({
    bool requestMechanicReport = true,
  }) async {
    if (_transport == null) {
      _lastError = 'No Bluetooth sync transport attached';
      _setState(SyncConnectionState.error);
      return;
    }

    _activeSyncCompleter = Completer<void>();
    _setState(SyncConnectionState.syncing);

    final manifest = await _buildLocalManifest();
    _sendFrame(SyncFrame.hello(manifest));

    return _activeSyncCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        if (_activeSyncCompleter != null &&
            !_activeSyncCompleter!.isCompleted) {
          _activeSyncCompleter!.complete();
        }
      },
    );
  }

  Future<SyncManifest> _buildLocalManifest() async {
    final delegate = _delegate;
    final trips = delegate != null ? await delegate.getLocalTrips() : <Trip>[];
    final tripIds = trips.map((t) => t.id).toList();
    final tsIds =
        trips.where((t) => t.hasTimeseries).map((t) => t.id).toList();
    final garage = delegate != null ? await delegate.getGarageData() : null;

    return SyncManifest(
      deviceId: deviceId,
      deviceRole: deviceRole,
      generatedAt: DateTime.now(),
      tripIds: tripIds,
      timeseriesTripIds: tsIds,
      activeVehicleId: garage?.activeVehicleId,
      latestSnapshotTimestamp: _latestSnapshot?.timestamp,
    );
  }

  void _sendFrame(SyncFrame frame) {
    _transport?.sendBytes(frame.encodeBytes());
  }

  Future<void> _onFrameReceived(SyncFrame frame) async {
    try {
      switch (frame.type) {
        case SyncFrameType.hello:
          await _handleHelloFrame(frame);
          break;
        case SyncFrameType.requestSync:
          await _handleRequestSyncFrame(frame);
          break;
        case SyncFrameType.tripPayload:
          await _handleTripPayloadFrame(frame);
          break;
        case SyncFrameType.timeseriesChunk:
          await _handleTimeseriesChunkFrame(frame);
          break;
        case SyncFrameType.parkedSnapshot:
          await _handleParkedSnapshotFrame(frame);
          break;
        case SyncFrameType.mechanicReport:
          await _handleMechanicReportFrame(frame);
          break;
        case SyncFrameType.garageSync:
          await _handleGarageSyncFrame(frame);
          break;
        case SyncFrameType.syncAck:
          await _handleSyncAckFrame(frame);
          break;
        case SyncFrameType.ping:
          _sendFrame(
            SyncFrame(
              type: SyncFrameType.pong,
              messageId: frame.messageId,
              timestamp: DateTime.now(),
              payload: const {},
            ),
          );
          break;
        case SyncFrameType.pong:
          break;
        case SyncFrameType.error:
          _lastError = frame.payload['message']?.toString() ?? 'Peer error';
          _setState(SyncConnectionState.error);
          break;
      }
    } catch (e) {
      LogService.e('Error handling sync frame ${frame.type}: $e', tag: 'Sync');
      _lastError = e.toString();
      _setState(SyncConnectionState.error);
    }
  }

  Future<void> _handleHelloFrame(SyncFrame frame) async {
    final peerManifest = SyncManifest.fromJson(frame.payload);
    final delegate = _delegate;
    final localTrips =
        delegate != null ? await delegate.getLocalTrips() : <Trip>[];
    final knownTripIds = localTrips.map((t) => t.id).toSet();
    final knownTsIds =
        localTrips.where((t) => t.hasTimeseries).map((t) => t.id).toSet();

    final missingTripIds = peerManifest.computeMissingTripIds(knownTripIds);
    final missingTsIds = peerManifest.computeMissingTimeseriesIds(knownTsIds);

    _expectedTripIds
      ..clear()
      ..addAll(missingTripIds);
    _expectedTimeseriesIds
      ..clear()
      ..addAll(missingTsIds);
    _pendingReceivedTrips.clear();
    _pendingTimeseriesChunks.clear();
    _completedSyncedTripIds.clear();
    _completedSyncedTimeseriesIds.clear();

    _setState(SyncConnectionState.syncing);

    final isReply = frame.payload['isReply'] == true;
    if (!isReply) {
      final localManifest = await _buildLocalManifest();
      _sendFrame(SyncFrame.hello(localManifest, isReply: true));
    }

    // If this device is the Phone and has garage profiles, push garage state to Headunit
    if (deviceRole == 'phone' && delegate != null) {
      final garage = await delegate.getGarageData();
      if (garage.vehicles.isNotEmpty) {
        _sendFrame(
          SyncFrame.garageSync(
            vehicles: garage.vehicles,
            activeVehicleId: garage.activeVehicleId,
          ),
        );
      }
    }

    _sendFrame(
      SyncFrame.requestSync(
        missingTripIds: missingTripIds,
        missingTimeseriesIds: missingTsIds,
        requestSnapshot: true,
        requestGarage: deviceRole == 'phone',
        requestMechanicReport: true,
      ),
    );

    if (missingTripIds.isEmpty &&
        missingTsIds.isEmpty &&
        (localTrips.isEmpty || isReply)) {
      _markSyncComplete();
    }
  }

  Future<void> _handleRequestSyncFrame(SyncFrame frame) async {
    final delegate = _delegate;
    if (delegate == null) return;

    _setState(SyncConnectionState.syncing);

    final rawMissingTrips = frame.payload['missingTripIds'];
    final missingTripIds = rawMissingTrips is Iterable
        ? rawMissingTrips.map((e) => e.toString()).toSet()
        : <String>{};

    final rawMissingTs = frame.payload['missingTimeseriesIds'];
    final missingTsIds = rawMissingTs is Iterable
        ? rawMissingTs.map((e) => e.toString()).toSet()
        : <String>{};

    final requestSnapshot = frame.payload['requestSnapshot'] == true;
    final requestGarage = frame.payload['requestGarage'] == true;
    final requestMechanicReport =
        frame.payload['requestMechanicReport'] == true;

    if (requestGarage) {
      final garage = await delegate.getGarageData();
      if (garage.vehicles.isNotEmpty) {
        _sendFrame(
          SyncFrame.garageSync(
            vehicles: garage.vehicles,
            activeVehicleId: garage.activeVehicleId,
          ),
        );
      }
    }

    if (requestSnapshot) {
      final snap = await delegate.getParkedSnapshot() ?? _latestSnapshot;
      if (snap != null) {
        _sendFrame(SyncFrame.parkedSnapshot(snap));
      }
    }

    if (requestMechanicReport) {
      final report =
          await delegate.getMechanicReport() ?? _latestMechanicReport;
      if (report != null) {
        _sendFrame(SyncFrame.mechanicReport(report));
      }
    }

    final localTrips = await delegate.getLocalTrips();
    final tripsById = {for (final t in localTrips) t.id: t};

    // Send requested trips
    for (final tripId in missingTripIds) {
      final trip = tripsById[tripId];
      if (trip != null) {
        _sendFrame(SyncFrame.tripPayload(trip));
      }
    }

    // Send requested timeseries chunks
    for (final tripId in missingTsIds) {
      final lines = await delegate.getTimeseriesLines(tripId);
      final chunks = SyncProtocolCodec.chunkTimeseriesLines(tripId, lines);
      for (final chunkFrame in chunks) {
        _sendFrame(chunkFrame);
      }
    }

    if (missingTripIds.isEmpty && missingTsIds.isEmpty) {
      _markSyncComplete();
    }
  }

  Future<void> _handleTripPayloadFrame(SyncFrame frame) async {
    final trip = Trip.fromJson(frame.payload);
    _pendingReceivedTrips[trip.id] = trip;
    _expectedTripIds.remove(trip.id);

    // If no timeseries chunks are expected for this trip, persist immediately
    if (!_expectedTimeseriesIds.contains(trip.id)) {
      await _delegate?.onTripReceived(trip, null);
      _pendingReceivedTrips.remove(trip.id);
      _completedSyncedTripIds.add(trip.id);
      _checkAndSendAckIfComplete();
    }
  }

  Future<void> _handleTimeseriesChunkFrame(SyncFrame frame) async {
    final tripId = frame.payload['tripId']?.toString() ?? '';
    if (tripId.isEmpty) return;

    final isLast = frame.payload['isLast'] == true;
    final list = _pendingTimeseriesChunks.putIfAbsent(tripId, () => []);
    list.add(frame);

    if (isLast) {
      final lines = SyncProtocolCodec.reassembleTimeseriesChunks(list);
      _pendingTimeseriesChunks.remove(tripId);
      _expectedTimeseriesIds.remove(tripId);

      final trip = _pendingReceivedTrips.remove(tripId);
      if (trip != null) {
        await _delegate?.onTripReceived(trip, lines);
        _completedSyncedTripIds.add(tripId);
      } else {
        // Trip was already known locally, only timeseries was missing
        final localTrips = await _delegate?.getLocalTrips() ?? <Trip>[];
        for (final existing in localTrips) {
          if (existing.id == tripId) {
            await _delegate?.onTripReceived(existing, lines);
            break;
          }
        }
      }
      _completedSyncedTimeseriesIds.add(tripId);
      _checkAndSendAckIfComplete();
    }
  }

  void _checkAndSendAckIfComplete() {
    if (_expectedTripIds.isEmpty && _expectedTimeseriesIds.isEmpty) {
      if (_completedSyncedTripIds.isNotEmpty ||
          _completedSyncedTimeseriesIds.isNotEmpty) {
        _sendFrame(
          SyncFrame.syncAck(
            syncedTripIds: List.unmodifiable(_completedSyncedTripIds),
            syncedTimeseriesTripIds:
                List.unmodifiable(_completedSyncedTimeseriesIds),
          ),
        );
      }
      _markSyncComplete();
    }
  }

  Future<void> _handleParkedSnapshotFrame(SyncFrame frame) async {
    final snapshot = ParkedCarSnapshot.fromJson(frame.payload);
    _latestSnapshot = snapshot;
    await _delegate?.onParkedSnapshotReceived(snapshot);
    await savePersistedState();
    onStateChanged?.call();
  }

  Future<void> _handleMechanicReportFrame(SyncFrame frame) async {
    final report = MechanicDiagnosticReport.fromJson(frame.payload);
    _latestMechanicReport = report;
    await _delegate?.onMechanicReportReceived(report);
    await savePersistedState();
    onStateChanged?.call();
  }

  Future<void> _handleGarageSyncFrame(SyncFrame frame) async {
    final rawVehicles = frame.payload['vehicles'];
    final vehicles = <VehicleProfile>[];
    if (rawVehicles is Iterable) {
      for (final item in rawVehicles) {
        if (item is Map<String, dynamic>) {
          vehicles.add(VehicleProfile.fromJson(item));
        } else if (item is Map) {
          vehicles.add(
            VehicleProfile.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final activeId = frame.payload['activeVehicleId']?.toString() ?? '';
    if (vehicles.isNotEmpty) {
      await _delegate?.onGarageDataReceived(vehicles, activeId);
    }
  }

  Future<void> _handleSyncAckFrame(SyncFrame frame) async {
    final rawTrips = frame.payload['syncedTripIds'];
    final syncedTripIds = rawTrips is Iterable
        ? rawTrips.map((e) => e.toString()).toList()
        : <String>[];

    final rawTs = frame.payload['syncedTimeseriesTripIds'];
    final syncedTsIds = rawTs is Iterable
        ? rawTs.map((e) => e.toString()).toList()
        : <String>[];

    await _delegate?.onTripsAcked(syncedTripIds, syncedTsIds);
    _markSyncComplete();
  }

  void _markSyncComplete() {
    _lastSyncTime = DateTime.now();
    unawaited(savePersistedState());
    _setState(SyncConnectionState.synced);
    if (_activeSyncCompleter != null && !_activeSyncCompleter!.isCompleted) {
      _activeSyncCompleter!.complete();
    }
  }

  void _setState(SyncConnectionState newState) {
    _state = newState;
    onStateChanged?.call();
  }

  Future<void> dispose() async {
    await detachTransport();
  }
}
