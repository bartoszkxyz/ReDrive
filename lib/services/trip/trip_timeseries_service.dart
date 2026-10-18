import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/obd/models/obd_data.dart';

/// Supported export formats for trip timeseries data.
enum TimeseriesExportFormat {
  csv,
  json,
  both,
}

/// Represents a single synchronized timeseries sample recorded during a trip.
class TripTimeseriesSample {
  final DateTime timestamp;
  final double elapsedSeconds;
  final ObdData data;
  final List<String> activeProblems;
  final List<String> activeSuspicions;
  final double? latitude;
  final double? longitude;
  final double? altitudeMeters;
  final double? gpsSpeedKmh;

  const TripTimeseriesSample({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.data,
    this.activeProblems = const [],
    this.activeSuspicions = const [],
    this.latitude,
    this.longitude,
    this.altitudeMeters,
    this.gpsSpeedKmh,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'elapsedSeconds': elapsedSeconds,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (altitudeMeters != null) 'altitudeMeters': altitudeMeters,
        if (gpsSpeedKmh != null) 'gpsSpeedKmh': gpsSpeedKmh,
        'rpm': data.rpm,
        'speed': data.speed,
        'coolantTemp': data.coolantTemp,
        'intakeTemp': data.intakeAirTemp,
        'maf': data.maf,
        'throttlePosition': data.throttlePosition,
        'relativeThrottle': data.relativeThrottle,
        'fuelLevel': data.fuelLevelPercent,
        'timingAdvance': data.timingAdvance,
        'intakePressure': data.manifoldPressure,
        'engineLoad': data.engineLoad,
        'shortTermFuelTrim': data.shortTermFuelTrim,
        'longTermFuelTrim': data.longTermFuelTrim,
        'fuelSystemStatus': data.fuelSystemStatus.name,
        'engineFuelRate': data.engineFuelRate,
        'voltage': data.voltage,
        'isDfcoActive': data.isDfcoActive,
        'instantFuelLPerHour': data.instantFuelLPerHour,
        'instantFuelL100km': data.instantFuelL100km,
        'horsepower': data.horsepower,
        'torqueNm': data.torqueNm,
        'accelerationG': data.accelerationG,
        'remainingFuelLiters': data.remainingFuelLiters,
        'estimatedRangeKm': data.estimatedRangeKm,
        'activeProblems': activeProblems,
        'activeSuspicions': activeSuspicions,
      };

  factory TripTimeseriesSample.fromJson(Map<String, dynamic> json) {
    final obdData = ObdData(
      rpm: _toInt(json['rpm']),
      speed: _toInt(json['speed']),
      coolantTemp: _toInt(json['coolantTemp']),
      intakeAirTemp: _toInt(json['intakeTemp'] ?? json['intakeAirTemp']),
      voltage: _toDouble(json['voltage']),
      engineLoad: _toDouble(json['engineLoad']),
      throttlePosition: _toDouble(json['throttlePosition']),
      relativeThrottle: _toDouble(json['relativeThrottle']),
      maf: _toDouble(json['maf']),
      engineFuelRate: _toDouble(json['engineFuelRate']),
      instantFuelLPerHour: _toDouble(json['instantFuelLPerHour']),
      instantFuelL100km: _toDouble(json['instantFuelL100km']),
      shortTermFuelTrim: _toDouble(json['shortTermFuelTrim']),
      longTermFuelTrim: _toDouble(json['longTermFuelTrim']),
      timingAdvance: _toDouble(json['timingAdvance']),
      manifoldPressure:
          _toDouble(json['intakePressure'] ?? json['manifoldPressure']),
      fuelLevelPercent:
          _toDouble(json['fuelLevel'] ?? json['fuelLevelPercent']),
      fuelSystemStatus: _parseFuelSystemStatus(json['fuelSystemStatus']),
      horsepower: _toDouble(json['horsepower']),
      torqueNm: _toDouble(json['torqueNm']),
      accelerationG: _toDouble(json['accelerationG']),
      isDfcoActive: _toBool(json['isDfcoActive']),
      remainingFuelLiters: _toDouble(json['remainingFuelLiters']),
      estimatedRangeKm: _toDouble(json['estimatedRangeKm']),
    );

    double? parseDoubleNullable(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    final lat = parseDoubleNullable(json['latitude'] ?? json['lat']);
    final lon = parseDoubleNullable(json['longitude'] ?? json['lon']);
    final alt = parseDoubleNullable(
      json['altitudeMeters'] ?? json['altitude'] ?? json['alt'],
    );
    final gpsSpd = parseDoubleNullable(json['gpsSpeedKmh'] ?? json['gpsSpeed']);

    return TripTimeseriesSample(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      elapsedSeconds: _toDouble(json['elapsedSeconds']),
      data: obdData,
      activeProblems: _toStringList(json['activeProblems']),
      activeSuspicions: _toStringList(json['activeSuspicions']),
      latitude: lat,
      longitude: lon,
      altitudeMeters: alt,
      gpsSpeedKmh: gpsSpd,
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  static int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  static bool _toBool(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    return val.toString().toLowerCase() == 'true';
  }

  static List<String> _toStringList(dynamic val) {
    if (val is Iterable) {
      return val.where((e) => e != null).map((e) => e.toString()).toList();
    }
    return const [];
  }

  static FuelSystemStatus _parseFuelSystemStatus(dynamic val) {
    if (val == null) return FuelSystemStatus.unknown;
    if (val is FuelSystemStatus) return val;
    if (val is num) return FuelSystemStatus.fromNumeric(val);
    final str = val.toString().trim();
    final numVal = num.tryParse(str);
    if (numVal != null) {
      return FuelSystemStatus.fromNumeric(numVal);
    }
    for (final status in FuelSystemStatus.values) {
      if (status.name.toLowerCase() == str.toLowerCase() ||
          status.shortCode.toLowerCase() == str.toLowerCase()) {
        return status;
      }
    }
    return FuelSystemStatus.unknown;
  }

  static bool _obdEquals(ObdData a, ObdData b) {
    return a.rpm == b.rpm &&
        a.speed == b.speed &&
        a.coolantTemp == b.coolantTemp &&
        a.intakeAirTemp == b.intakeAirTemp &&
        (a.voltage - b.voltage).abs() < 1e-4 &&
        (a.engineLoad - b.engineLoad).abs() < 1e-4 &&
        (a.throttlePosition - b.throttlePosition).abs() < 1e-4 &&
        (a.relativeThrottle - b.relativeThrottle).abs() < 1e-4 &&
        (a.maf - b.maf).abs() < 1e-4 &&
        (a.engineFuelRate - b.engineFuelRate).abs() < 1e-4 &&
        (a.instantFuelLPerHour - b.instantFuelLPerHour).abs() < 1e-4 &&
        (a.instantFuelL100km - b.instantFuelL100km).abs() < 1e-4 &&
        (a.shortTermFuelTrim - b.shortTermFuelTrim).abs() < 1e-4 &&
        (a.longTermFuelTrim - b.longTermFuelTrim).abs() < 1e-4 &&
        (a.timingAdvance - b.timingAdvance).abs() < 1e-4 &&
        (a.manifoldPressure - b.manifoldPressure).abs() < 1e-4 &&
        (a.fuelLevelPercent - b.fuelLevelPercent).abs() < 1e-4 &&
        a.fuelSystemStatus == b.fuelSystemStatus &&
        (a.horsepower - b.horsepower).abs() < 1e-4 &&
        (a.torqueNm - b.torqueNm).abs() < 1e-4 &&
        (a.accelerationG - b.accelerationG).abs() < 1e-4 &&
        a.isDfcoActive == b.isDfcoActive &&
        (a.remainingFuelLiters - b.remainingFuelLiters).abs() < 1e-4 &&
        (a.estimatedRangeKm - b.estimatedRangeKm).abs() < 1e-4;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripTimeseriesSample &&
          runtimeType == other.runtimeType &&
          timestamp.isAtSameMomentAs(other.timestamp) &&
          (elapsedSeconds - other.elapsedSeconds).abs() < 1e-6 &&
          _obdEquals(data, other.data) &&
          _listEquals(activeProblems, other.activeProblems) &&
          _listEquals(activeSuspicions, other.activeSuspicions) &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          altitudeMeters == other.altitudeMeters &&
          gpsSpeedKmh == other.gpsSpeedKmh;

  @override
  int get hashCode => Object.hash(
        timestamp,
        elapsedSeconds,
        data.rpm,
        data.speed,
        data.voltage,
        data.coolantTemp,
        Object.hashAll(activeProblems),
        Object.hashAll(activeSuspicions),
        latitude,
        longitude,
        altitudeMeters,
        gpsSpeedKmh,
      );

  @override
  String toString() {
    return 'TripTimeseriesSample('
        'timestamp: ${timestamp.toIso8601String()}, '
        'elapsedSeconds: $elapsedSeconds, '
        'rpm: ${data.rpm}, '
        'speed: ${data.speed}, '
        'problems: $activeProblems, '
        'suspicions: $activeSuspicions)';
  }
}

/// Service responsible for recording timeseries telemetry for active trips,
/// enforcing a 2-trip rolling storage policy, and exporting timeseries on-demand to CSV/JSON.
class TripTimeseriesService {
  final Directory? customDirectory;
  final Directory? customExportDirectory;
  final int maxRetainedTrips;

  TripTimeseriesService({
    this.customDirectory,
    this.customExportDirectory,
    this.maxRetainedTrips = 2,
  });

  Future<void> _lock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  String? _activeTripId;
  DateTime? _activeTripStartTime;
  final List<TripTimeseriesSample> _buffer = [];

  String? get activeTripId => _activeTripId;
  DateTime? get activeTripStartTime => _activeTripStartTime;
  int get bufferedSampleCount => _buffer.length;

  /// Resolves the storage directory for raw .jsonl timeseries files.
  Future<Directory> get timeseriesDir async {
    Directory baseDir;
    if (customDirectory != null) {
      if (customDirectory!.path.endsWith('/timeseries') ||
          customDirectory!.path.endsWith(r'\timeseries')) {
        if (!await customDirectory!.exists()) {
          await customDirectory!.create(recursive: true);
        }
        return customDirectory!;
      }
      baseDir = customDirectory!;
    } else {
      try {
        baseDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        final home = Platform.environment['HOME'] ?? '.';
        final xdgData = Platform.environment['XDG_DATA_HOME'];
        final dataPath = xdgData != null && xdgData.isNotEmpty
            ? xdgData
            : '$home/.local/share/redrive';
        baseDir = Directory(dataPath);
      }
    }
    final dir = Directory('${baseDir.path}/timeseries');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileForTrip(String tripId) async {
    final dir = await timeseriesDir;
    return File('${dir.path}/trip_$tripId.jsonl');
  }

  /// Begins recording timeseries samples for [tripId] starting at [startTime].
  Future<void> startRecording(String tripId, DateTime startTime) async {
    final prevTripId = _activeTripId;
    final prevBuffer = List<TripTimeseriesSample>.from(_buffer);
    _activeTripId = tripId;
    _activeTripStartTime = startTime;
    _buffer.clear();

    if (prevTripId != null && prevBuffer.isNotEmpty) {
      await _synchronized(() async {
        final file = await _fileForTrip(prevTripId);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        final content =
            '${prevBuffer.map((s) => jsonEncode(s.toJson())).join('\n')}\n';
        await file.writeAsString(content, mode: FileMode.append, flush: true);
      });
    }
  }

  /// Appends a [TripTimeseriesSample] to the in-memory buffer for the active trip.
  /// If [replaceLastIfWithinMs] is provided and the last buffered sample was recorded
  /// within that many milliseconds, replaces the last sample in-place so rapid per-PID
  /// updates within a single OBD polling cycle coalesce into a single complete sample.
  void recordSample(
    ObdData data, {
    DateTime? timestamp,
    List<String> activeProblems = const [],
    List<String> activeSuspicions = const [],
    int? replaceLastIfWithinMs,
    double? latitude,
    double? longitude,
    double? altitudeMeters,
    double? gpsSpeedKmh,
  }) {
    final now = timestamp ?? DateTime.now();
    final start = _activeTripStartTime ?? now;
    final elapsedMicros = now.difference(start).inMicroseconds;
    final elapsedSeconds =
        elapsedMicros >= 0 ? elapsedMicros / 1000000.0 : 0.0;

    final sample = TripTimeseriesSample(
      timestamp: now,
      elapsedSeconds: elapsedSeconds,
      data: data,
      activeProblems: List.unmodifiable(activeProblems),
      activeSuspicions: List.unmodifiable(activeSuspicions),
      latitude: latitude,
      longitude: longitude,
      altitudeMeters: altitudeMeters,
      gpsSpeedKmh: gpsSpeedKmh,
    );

    if (replaceLastIfWithinMs != null && _buffer.isNotEmpty) {
      final last = _buffer.last;
      final diffMs = now.difference(last.timestamp).inMilliseconds;
      if (diffMs >= 0 && diffMs < replaceLastIfWithinMs) {
        _buffer[_buffer.length - 1] = sample;
        return;
      }
    }

    _buffer.add(sample);
  }

  /// Appends buffered samples as newline-delimited JSON (.jsonl) to the trip file and clears the buffer.
  Future<void> flush() async {
    return _synchronized(() => _flushInternal());
  }

  Future<void> _flushInternal() async {
    if (_activeTripId == null || _buffer.isEmpty) return;
    final file = await _fileForTrip(_activeTripId!);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final content =
        '${_buffer.map((s) => jsonEncode(s.toJson())).join('\n')}\n';
    await file.writeAsString(content, mode: FileMode.append, flush: true);
    _buffer.clear();
  }

  /// Flushes any pending buffer and finalizes the trip timeseries.
  /// If [keep] is false, deletes the raw timeseries file and returns false.
  /// If [keep] is true, returns true if the timeseries file exists and is non-empty.
  Future<bool> finishTrip(String tripId, {required bool keep}) async {
    return _synchronized(() async {
      await _flushInternal();

      if (_activeTripId == tripId) {
        _activeTripId = null;
        _activeTripStartTime = null;
      }

      final file = await _fileForTrip(tripId);

      if (!keep) {
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        return false;
      }

      if (await file.exists()) {
        final len = await file.length();
        return len > 0;
      }
      return false;
    });
  }

  /// Enforces the rolling retention policy keeping raw .jsonl files only for the
  /// first [maxRetainedTrips] (default 2) trip IDs in [orderedCompletedTripIds] (newest-first)
  /// that have an existing file, deleting older trip timeseries files.
  /// Returns the Set of trip IDs that still have an existing .jsonl file on disk.
  Future<Set<String>> enforceRetentionPolicy(
    List<String> orderedCompletedTripIds,
  ) async {
    return _synchronized(() async {
      final dir = await timeseriesDir;
      if (!await dir.exists()) return {};

      final keptTripIds = <String>{};
      for (final tripId in orderedCompletedTripIds) {
        final file = File('${dir.path}/trip_$tripId.jsonl');
        if (await file.exists() && (await file.length()) > 0) {
          if (keptTripIds.length < maxRetainedTrips) {
            keptTripIds.add(tripId);
          }
        }
      }

      // Delete any older or un-retained trip_<id>.jsonl files
      await for (final entity in dir.list()) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (fileName.startsWith('trip_') && fileName.endsWith('.jsonl')) {
            final tripId = fileName.substring(
              'trip_'.length,
              fileName.length - '.jsonl'.length,
            );
            if (tripId == _activeTripId) {
              continue;
            }
            if (!keptTripIds.contains(tripId)) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }

      final remaining = <String>{};
      await for (final entity in dir.list()) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (fileName.startsWith('trip_') && fileName.endsWith('.jsonl')) {
            if ((await entity.length()) > 0) {
              final tripId = fileName.substring(
                'trip_'.length,
                fileName.length - '.jsonl'.length,
              );
              remaining.add(tripId);
            }
          }
        }
      }
      return remaining;
    });
  }

  /// Checks if `<timeseriesDir>/trip_<tripId>.jsonl` exists and has length > 0.
  Future<bool> hasTimeseries(String tripId) async {
    final file = await _fileForTrip(tripId);
    return await file.exists() && (await file.length()) > 0;
  }

  /// Reads `<timeseriesDir>/trip_<tripId>.jsonl` line-by-line, skipping blank or malformed lines gracefully.
  Future<List<TripTimeseriesSample>> readSamples(String tripId) async {
    final file = await _fileForTrip(tripId);
    if (!await file.exists()) return [];

    final samples = <TripTimeseriesSample>[];
    try {
      final stream = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in stream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) {
            samples.add(TripTimeseriesSample.fromJson(decoded));
          } else if (decoded is Map) {
            samples.add(
              TripTimeseriesSample.fromJson(Map<String, dynamic>.from(decoded)),
            );
          }
        } catch (_) {
          // Gracefully skip blank, malformed, or partially written lines
        }
      }
    } catch (_) {
      // In case of I/O error, return whatever valid samples have been parsed
    }
    return samples;
  }

  /// Deletes `trip_<tripId>.jsonl` if it exists.
  Future<void> deleteTimeseries(String tripId) async {
    final file = await _fileForTrip(tripId);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static const MethodChannel _storageChannel =
      MethodChannel('com.example.redrive/storage');

  /// Exports recorded timeseries samples for [trip] into CSV, JSON, or both formats.
  /// Throws [StateError] if no samples exist for the trip.
  /// Returns the list of written file paths.
  Future<List<String>> exportTripTimeseries({
    required Trip trip,
    TimeseriesExportFormat format = TimeseriesExportFormat.both,
    DateTime? exportTime,
  }) async {
    final samples = await readSamples(trip.id);
    if (samples.isEmpty) {
      throw StateError('No timeseries samples found for trip ${trip.id}');
    }

    final timestampStr = _formatExportTimestamp(exportTime ?? DateTime.now());
    final writtenFiles = <String>[];

    if (format == TimeseriesExportFormat.csv ||
        format == TimeseriesExportFormat.both) {
      final csvFileName = 'redrive_trip_${trip.id}_$timestampStr.csv';
      final csvBuffer = StringBuffer();
      csvBuffer.writeln(
        'timestamp_iso,elapsed_s,rpm,speed_kmh,engine_load_pct,throttle_raw_pct,throttle_rel_pct,maf_gps,map_kpa,stft_pct,ltft_pct,total_trim_pct,timing_adv_deg,coolant_c,iat_c,voltage_v,fuel_rate_lph,fuel_level_pct,fuel_system_status,is_dfco,active_problems,active_suspicions',
      );
      for (final s in samples) {
        final totalTrim = s.data.shortTermFuelTrim + s.data.longTermFuelTrim;
        final fuelRate = s.data.engineFuelRate != 0.0
            ? s.data.engineFuelRate
            : s.data.instantFuelLPerHour;
        final row = [
          s.timestamp.toIso8601String(),
          s.elapsedSeconds,
          s.data.rpm,
          s.data.speed,
          s.data.engineLoad,
          s.data.throttlePosition,
          s.data.relativeThrottle,
          s.data.maf,
          s.data.manifoldPressure,
          s.data.shortTermFuelTrim,
          s.data.longTermFuelTrim,
          totalTrim,
          s.data.timingAdvance,
          s.data.coolantTemp,
          s.data.intakeAirTemp,
          s.data.voltage,
          fuelRate,
          s.data.fuelLevelPercent,
          s.data.fuelSystemStatus.name,
          s.data.isDfcoActive,
          s.activeProblems,
          s.activeSuspicions,
        ];
        csvBuffer.writeln(row.map(_toCsvField).join(','));
      }
      final savedCsvPath = await _writeExportFile(
        fileName: csvFileName,
        content: csvBuffer.toString(),
        mimeType: 'text/csv',
      );
      writtenFiles.add(savedCsvPath);
    }

    if (format == TimeseriesExportFormat.json ||
        format == TimeseriesExportFormat.both) {
      final jsonFileName = 'redrive_trip_${trip.id}_$timestampStr.json';
      final exportMap = <String, dynamic>{
        'trip': trip.toJson(),
        'anomalies': trip.anomalies.map((e) => e.toJson()).toList(),
        'recordedDtcs': trip.recordedDtcs,
        'sampleCount': samples.length,
        'samples': samples.map((s) => s.toJson()).toList(),
      };
      final jsonContent =
          const JsonEncoder.withIndent('  ').convert(exportMap);
      final savedJsonPath = await _writeExportFile(
        fileName: jsonFileName,
        content: jsonContent,
        mimeType: 'application/json',
      );
      writtenFiles.add(savedJsonPath);
    }

    return writtenFiles;
  }

  Future<String> _writeExportFile({
    required String fileName,
    required String content,
    required String mimeType,
  }) async {
    // 1. Custom export directory (used by unit tests)
    if (customExportDirectory != null) {
      if (!await customExportDirectory!.exists()) {
        await customExportDirectory!.create(recursive: true);
      }
      final file = File('${customExportDirectory!.path}/$fileName');
      await file.writeAsString(content, flush: true);
      return file.path;
    }

    // 2. Android: save to /storage/emulated/0/ReDrive or /storage/emulated/0/Download/ReDrive
    if (Platform.isAndroid) {
      try {
        await Permission.storage.request();
      } catch (_) {}

      const androidCandidateDirs = <String>[
        '/storage/emulated/0/ReDrive',
        '/storage/emulated/0/Download/ReDrive',
        '/storage/emulated/0/Download',
        '/storage/emulated/0',
      ];

      for (final dirPath in androidCandidateDirs) {
        try {
          final dir = Directory(dirPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final file = File('${dir.path}/$fileName');
          await file.writeAsString(content, flush: true);
          return file.path;
        } catch (_) {
          // Try next candidate or native MediaStore channel
        }
      }

      // Use native Android MediaStore.Downloads / external storage channel in MainActivity.kt
      try {
        final nativeSavedPath = await _storageChannel.invokeMethod<String>(
          'saveExportFile',
          <String, dynamic>{
            'fileName': fileName,
            'content': content,
            'mimeType': mimeType,
          },
        );
        if (nativeSavedPath != null && nativeSavedPath.isNotEmpty) {
          return nativeSavedPath;
        }
      } catch (_) {}

      // Fallback to /storage/emulated/0/Android/data/<pkg>/files/ReDrive_Exports
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final exportDir = Directory('${extDir.path}/ReDrive_Exports');
          if (!await exportDir.exists()) {
            await exportDir.create(recursive: true);
          }
          final file = File('${exportDir.path}/$fileName');
          await file.writeAsString(content, flush: true);
          return file.path;
        }
      } catch (_) {}
    }

    // 3. Desktop (Linux, macOS, Windows) or final fallback
    final exportDir = await _resolveDesktopExportDirectory();
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  Future<Directory> _resolveDesktopExportDirectory() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final desktopDownload = Directory('$home/Downloads/ReDrive');
    try {
      if (!await desktopDownload.exists()) {
        await desktopDownload.create(recursive: true);
      }
      return desktopDownload;
    } catch (_) {
      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        final xdgData = Platform.environment['XDG_DATA_HOME'];
        final dataPath = xdgData != null && xdgData.isNotEmpty
            ? xdgData
            : '$home/.local/share/redrive';
        docDir = Directory(dataPath);
      }
      final fallbackDir = Directory('${docDir.path}/ReDrive_Exports');
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      return fallbackDir;
    }
  }

  static String _formatExportTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm$ss';
  }

  static String _toCsvField(dynamic value) {
    if (value == null) return '';
    String str;
    if (value is Iterable) {
      str = value.join(';');
    } else {
      str = value.toString();
    }
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }
}
