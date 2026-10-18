import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/vehicle_profile.dart';

/// Enumerates the framing message types supported by the ReDrive
/// Bluetooth RFCOMM synchronization protocol.
enum SyncFrameType {
  /// Initial handshake containing the device's manifest of trips and state.
  hello,

  /// Request from peer for specific missing trips, timeseries chunks, or state.
  requestSync,

  /// Full metadata payload for a completed trip.
  tripPayload,

  /// Chunk of raw high-frequency `.jsonl` timeseries sensor samples.
  timeseriesChunk,

  /// Parked vehicle telemetry snapshot (fuel, battery, GPS coordinates).
  parkedSnapshot,

  /// Human/mechanic readable diagnostic report and active DTC summaries.
  mechanicReport,

  /// Vehicle profiles stored in the garage.
  garageSync,

  /// Custom theme definition pushed from Phone to Headunit.
  themeSync,

  /// Confirmation from receiver acknowledging successful persistence.
  syncAck,

  /// Heartbeat ping to verify RFCOMM stream liveness.
  ping,

  /// Heartbeat response.
  pong,

  /// Sync protocol error description.
  error,
}

/// Represents a single newline-delimited JSON frame exchanged over the Bluetooth link.
@immutable
class SyncFrame {
  final SyncFrameType type;
  final String messageId;
  final DateTime timestamp;
  final Map<String, dynamic> payload;

  const SyncFrame({
    required this.type,
    required this.messageId,
    required this.timestamp,
    required this.payload,
  });

  static int _messageCounter = 0;
  static String _generateMessageId(String prefix) {
    _messageCounter++;
    final time = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_${time}_$_messageCounter';
  }

  // ---------------------------------------------------------------------------
  // Factory Constructors for Frame Types
  // ---------------------------------------------------------------------------

  /// Creates a [hello] frame transmitting a device manifest.
  factory SyncFrame.hello(
    SyncManifest manifest, {
    String? messageId,
    bool isReply = false,
  }) {
    final payload = manifest.toJson();
    if (isReply) {
      payload['isReply'] = true;
    }
    return SyncFrame(
      type: SyncFrameType.hello,
      messageId: messageId ?? _generateMessageId('hello'),
      timestamp: DateTime.now(),
      payload: payload,
    );
  }

  /// Creates a [requestSync] frame requesting specific missing data.
  factory SyncFrame.requestSync({
    List<String> missingTripIds = const [],
    List<String> missingTimeseriesIds = const [],
    bool requestSnapshot = true,
    bool requestGarage = true,
    bool requestMechanicReport = false,
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.requestSync,
      messageId: messageId ?? _generateMessageId('req'),
      timestamp: DateTime.now(),
      payload: {
        'missingTripIds': missingTripIds,
        'missingTimeseriesIds': missingTimeseriesIds,
        'requestSnapshot': requestSnapshot,
        'requestGarage': requestGarage,
        'requestMechanicReport': requestMechanicReport,
      },
    );
  }

  /// Creates a [tripPayload] frame transporting a complete [Trip].
  factory SyncFrame.tripPayload(
    Trip trip, {
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.tripPayload,
      messageId: messageId ?? _generateMessageId('trip_${trip.id}'),
      timestamp: DateTime.now(),
      payload: trip.toJson(),
    );
  }

  /// Creates a [timeseriesChunk] frame carrying raw `.jsonl` lines.
  factory SyncFrame.timeseriesChunk({
    required String tripId,
    required int chunkIndex,
    required int totalChunks,
    required List<String> lines,
    required bool isLast,
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.timeseriesChunk,
      messageId:
          messageId ?? _generateMessageId('ts_${tripId}_$chunkIndex'),
      timestamp: DateTime.now(),
      payload: {
        'tripId': tripId,
        'chunkIndex': chunkIndex,
        'totalChunks': totalChunks,
        'lines': lines,
        'isLast': isLast,
      },
    );
  }

  /// Creates a [parkedSnapshot] frame transporting a [ParkedCarSnapshot].
  factory SyncFrame.parkedSnapshot(
    ParkedCarSnapshot snapshot, {
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.parkedSnapshot,
      messageId: messageId ?? _generateMessageId('snap_${snapshot.vehicleId}'),
      timestamp: DateTime.now(),
      payload: snapshot.toJson(),
    );
  }

  /// Creates a [mechanicReport] frame transporting a [MechanicDiagnosticReport].
  factory SyncFrame.mechanicReport(
    MechanicDiagnosticReport report, {
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.mechanicReport,
      messageId: messageId ?? _generateMessageId('mech_${report.reportId}'),
      timestamp: DateTime.now(),
      payload: report.toJson(),
    );
  }

  /// Creates a [garageSync] frame carrying vehicle profiles and the active vehicle ID.
  factory SyncFrame.garageSync({
    required List<VehicleProfile> vehicles,
    required String activeVehicleId,
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.garageSync,
      messageId: messageId ?? _generateMessageId('garage'),
      timestamp: DateTime.now(),
      payload: {
        'vehicles': vehicles.map((v) => v.toJson()).toList(),
        'activeVehicleId': activeVehicleId,
      },
    );
  }

  /// Creates a [themeSync] frame carrying a custom dashboard theme JSON payload.
  factory SyncFrame.themeSync(
    Map<String, dynamic> themePayload, {
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.themeSync,
      messageId: messageId ?? _generateMessageId('theme'),
      timestamp: DateTime.now(),
      payload: themePayload,
    );
  }

  /// Creates a [syncAck] frame confirming persistence of synced trips and timeseries.
  factory SyncFrame.syncAck({
    required List<String> syncedTripIds,
    required List<String> syncedTimeseriesTripIds,
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.syncAck,
      messageId: messageId ?? _generateMessageId('ack'),
      timestamp: DateTime.now(),
      payload: {
        'syncedTripIds': syncedTripIds,
        'syncedTimeseriesTripIds': syncedTimeseriesTripIds,
      },
    );
  }

  /// Creates an [error] frame.
  factory SyncFrame.error(
    String errorMessage, {
    String? messageId,
  }) {
    return SyncFrame(
      type: SyncFrameType.error,
      messageId: messageId ?? _generateMessageId('err'),
      timestamp: DateTime.now(),
      payload: {
        'error': errorMessage,
      },
    );
  }

  /// Creates a [ping] heartbeat frame.
  factory SyncFrame.ping({String? messageId}) {
    return SyncFrame(
      type: SyncFrameType.ping,
      messageId: messageId ?? _generateMessageId('ping'),
      timestamp: DateTime.now(),
      payload: const {},
    );
  }

  /// Creates a [pong] heartbeat response frame.
  factory SyncFrame.pong({String? messageId}) {
    return SyncFrame(
      type: SyncFrameType.pong,
      messageId: messageId ?? _generateMessageId('pong'),
      timestamp: DateTime.now(),
      payload: const {},
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization & Encoding
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'messageId': messageId,
        'timestamp': timestamp.toIso8601String(),
        'payload': payload,
      };

  factory SyncFrame.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? '').toString();
    final frameType = SyncFrameType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => SyncFrameType.error,
    );
    final messageId = (json['messageId'] ?? '').toString();
    final timestamp = json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
        : DateTime.now();

    final rawPayload = json['payload'];
    final Map<String, dynamic> payload;
    if (rawPayload is Map<String, dynamic>) {
      payload = rawPayload;
    } else if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else {
      payload = const {};
    }

    return SyncFrame(
      type: frameType,
      messageId: messageId,
      timestamp: timestamp,
      payload: payload,
    );
  }

  /// Serializes the frame to a newline-terminated JSON string.
  String encodeLine() => '${jsonEncode(toJson())}\n';

  /// Encodes the frame to UTF-8 bytes including the terminating newline.
  Uint8List encodeBytes() => Uint8List.fromList(utf8.encode(encodeLine()));

  // ---------------------------------------------------------------------------
  // Typed Payload Accessors
  // ---------------------------------------------------------------------------

  SyncManifest? asHelloManifest() {
    if (type != SyncFrameType.hello) return null;
    return SyncManifest.fromJson(payload);
  }

  ParkedCarSnapshot? asParkedSnapshot() {
    if (type != SyncFrameType.parkedSnapshot) return null;
    return ParkedCarSnapshot.fromJson(payload);
  }

  MechanicDiagnosticReport? asMechanicReport() {
    if (type != SyncFrameType.mechanicReport) return null;
    return MechanicDiagnosticReport.fromJson(payload);
  }

  Trip? asTrip() {
    if (type != SyncFrameType.tripPayload) return null;
    return Trip.fromJson(payload);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncFrame &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          messageId == other.messageId &&
          timestamp == other.timestamp &&
          _deepMapEquals(payload, other.payload);

  @override
  int get hashCode => Object.hash(
        type,
        messageId,
        timestamp,
      );

  @override
  String toString() =>
      'SyncFrame(type: ${type.name}, id: $messageId, time: $timestamp)';
}

/// Utility codec for framing arbitrary RFCOMM byte streams and chunking
/// large timeseries recordings.
class SyncProtocolCodec {
  SyncProtocolCodec._();

  /// Transforms an incoming stream of raw byte chunks (from RFCOMM Bluetooth sockets)
  /// into decoded [SyncFrame]s. Handles arbitrary chunk fragmentation, frame coalescing,
  /// and silently ignores empty or corrupted lines without crashing the stream.
  static StreamTransformer<T, SyncFrame> frameDecoder<T extends List<int>>() {
    return StreamTransformer<T, SyncFrame>.fromBind((Stream<T> stream) {
      return stream
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .transform(
            StreamTransformer<String, SyncFrame>.fromHandlers(
              handleData: (line, sink) {
                try {
                  final decoded = jsonDecode(line.trim());
                  if (decoded is Map<String, dynamic>) {
                    sink.add(SyncFrame.fromJson(decoded));
                  } else if (decoded is Map) {
                    sink.add(
                      SyncFrame.fromJson(Map<String, dynamic>.from(decoded)),
                    );
                  }
                } catch (_) {
                  // Silently ignore malformed or partially corrupted frames
                }
              },
            ),
          );
    });
  }

  /// Splits lines of a raw `.jsonl` timeseries into ordered [SyncFrame.timeseriesChunk] frames.
  /// If [rawLines] is empty, returns a single empty terminal chunk frame.
  static List<SyncFrame> chunkTimeseriesLines(
    String tripId,
    List<String> rawLines, {
    int maxLinesPerChunk = 50,
  }) {
    if (rawLines.isEmpty) {
      return [
        SyncFrame.timeseriesChunk(
          tripId: tripId,
          chunkIndex: 0,
          totalChunks: 1,
          lines: const [],
          isLast: true,
        ),
      ];
    }

    final chunkSize = maxLinesPerChunk > 0 ? maxLinesPerChunk : 50;
    final totalChunks = (rawLines.length / chunkSize).ceil();
    final frames = <SyncFrame>[];

    for (var i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = math.min(start + chunkSize, rawLines.length);
      final chunkLines = rawLines.sublist(start, end);
      final isLast = (i == totalChunks - 1);

      frames.add(
        SyncFrame.timeseriesChunk(
          tripId: tripId,
          chunkIndex: i,
          totalChunks: totalChunks,
          lines: chunkLines,
          isLast: isLast,
        ),
      );
    }

    return frames;
  }

  /// Reassembles an unordered or ordered collection of [SyncFrame.timeseriesChunk] frames
  /// into the complete list of `.jsonl` lines.
  static List<String> reassembleTimeseriesChunks(List<SyncFrame> chunkFrames) {
    final filtered = chunkFrames
        .where((f) => f.type == SyncFrameType.timeseriesChunk)
        .toList();

    filtered.sort((a, b) {
      final indexA = (a.payload['chunkIndex'] as num?)?.toInt() ?? 0;
      final indexB = (b.payload['chunkIndex'] as num?)?.toInt() ?? 0;
      return indexA.compareTo(indexB);
    });

    final result = <String>[];
    for (final frame in filtered) {
      final rawLines = frame.payload['lines'];
      if (rawLines is Iterable) {
        for (final line in rawLines) {
          if (line != null) {
            result.add(line.toString());
          }
        }
      }
    }
    return result;
  }
}

// -----------------------------------------------------------------------------
// Deep Map Equality Helper
// -----------------------------------------------------------------------------

bool _deepMapEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepMapEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepMapEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
