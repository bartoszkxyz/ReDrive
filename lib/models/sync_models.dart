import 'package:flutter/foundation.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/vehicle_profile.dart';

/// Snapshot of vehicle status recorded when the ignition is switched off
/// or when a trip finishes, used for parking location, fuel level, and battery health.
@immutable
class ParkedCarSnapshot {
  final DateTime timestamp;
  final String vehicleId;
  final String vehicleName;
  final double? latitude;
  final double? longitude;
  final double remainingFuelLiters;
  final double fuelLevelPercent;
  final double estimatedRangeKm;
  final double batteryVoltage;
  final double coolantTempC;
  final double odometerKm;
  final String? lastTripId;

  const ParkedCarSnapshot({
    required this.timestamp,
    required this.vehicleId,
    required this.vehicleName,
    this.latitude,
    this.longitude,
    this.remainingFuelLiters = 0.0,
    this.fuelLevelPercent = 0.0,
    this.estimatedRangeKm = 0.0,
    this.batteryVoltage = 12.6,
    this.coolantTempC = 20.0,
    this.odometerKm = 0.0,
    this.lastTripId,
  });

  /// True if valid GPS coordinates are recorded for this parked snapshot.
  bool get hasCoordinates => latitude != null && longitude != null;

  ParkedCarSnapshot copyWith({
    DateTime? timestamp,
    String? vehicleId,
    String? vehicleName,
    double? latitude,
    double? longitude,
    double? remainingFuelLiters,
    double? fuelLevelPercent,
    double? estimatedRangeKm,
    double? batteryVoltage,
    double? coolantTempC,
    double? odometerKm,
    String? lastTripId,
  }) {
    return ParkedCarSnapshot(
      timestamp: timestamp ?? this.timestamp,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      remainingFuelLiters: remainingFuelLiters ?? this.remainingFuelLiters,
      fuelLevelPercent: fuelLevelPercent ?? this.fuelLevelPercent,
      estimatedRangeKm: estimatedRangeKm ?? this.estimatedRangeKm,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      coolantTempC: coolantTempC ?? this.coolantTempC,
      odometerKm: odometerKm ?? this.odometerKm,
      lastTripId: lastTripId ?? this.lastTripId,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'vehicleId': vehicleId,
        'vehicleName': vehicleName,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'remainingFuelLiters': remainingFuelLiters,
        'fuelLevelPercent': fuelLevelPercent,
        'estimatedRangeKm': estimatedRangeKm,
        'batteryVoltage': batteryVoltage,
        'coolantTempC': coolantTempC,
        'odometerKm': odometerKm,
        if (lastTripId != null) 'lastTripId': lastTripId,
      };

  factory ParkedCarSnapshot.fromJson(Map<String, dynamic> json) {
    return ParkedCarSnapshot(
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      vehicleId: (json['vehicleId'] ?? '').toString(),
      vehicleName: (json['vehicleName'] ?? '').toString(),
      latitude: _toDoubleNullable(json['latitude'] ?? json['lat']),
      longitude:
          _toDoubleNullable(json['longitude'] ?? json['lon'] ?? json['lng']),
      remainingFuelLiters: _toDouble(json['remainingFuelLiters'], 0.0),
      fuelLevelPercent: _toDouble(json['fuelLevelPercent'], 0.0),
      estimatedRangeKm: _toDouble(json['estimatedRangeKm'], 0.0),
      batteryVoltage: _toDouble(json['batteryVoltage'], 12.6),
      coolantTempC: _toDouble(json['coolantTempC'], 20.0),
      odometerKm: _toDouble(json['odometerKm'], 0.0),
      lastTripId: json['lastTripId']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParkedCarSnapshot &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          vehicleId == other.vehicleId &&
          vehicleName == other.vehicleName &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          remainingFuelLiters == other.remainingFuelLiters &&
          fuelLevelPercent == other.fuelLevelPercent &&
          estimatedRangeKm == other.estimatedRangeKm &&
          batteryVoltage == other.batteryVoltage &&
          coolantTempC == other.coolantTempC &&
          odometerKm == other.odometerKm &&
          lastTripId == other.lastTripId;

  @override
  int get hashCode => Object.hash(
        timestamp,
        vehicleId,
        vehicleName,
        latitude,
        longitude,
        remainingFuelLiters,
        fuelLevelPercent,
        estimatedRangeKm,
        batteryVoltage,
        coolantTempC,
        odometerKm,
        lastTripId,
      );

  @override
  String toString() =>
      'ParkedCarSnapshot(vehicle: $vehicleName ($vehicleId), '
      'coords: $latitude,$longitude, fuel: ${remainingFuelLiters}L ($fuelLevelPercent%), '
      'range: ${estimatedRangeKm}km, battery: ${batteryVoltage}V, odo: ${odometerKm}km)';
}

/// Comprehensive vehicle diagnostic report formatted for review and sharing
/// with mechanics or maintenance technicians.
@immutable
class MechanicDiagnosticReport {
  final String reportId;
  final DateTime generatedAt;
  final VehicleProfile vehicle;
  final double currentOdometerKm;
  final List<DtcCode> storedDtcs; // Mode 03 confirmed DTCs
  final List<DtcCode> pendingDtcs; // Mode 07 pending DTCs
  final List<TripAnomalyEpisode> recentAnomalies;
  final ParkedCarSnapshot? latestSnapshot;
  final String? attachedTripId;
  final int attachedSampleCount;

  const MechanicDiagnosticReport({
    required this.reportId,
    required this.generatedAt,
    required this.vehicle,
    required this.currentOdometerKm,
    this.storedDtcs = const [],
    this.pendingDtcs = const [],
    this.recentAnomalies = const [],
    this.latestSnapshot,
    this.attachedTripId,
    this.attachedSampleCount = 0,
  });

  /// Creates a diagnostic report directly derived from a recorded [Trip] and vehicle profile.
  factory MechanicDiagnosticReport.fromTrip({
    required String reportId,
    required VehicleProfile vehicle,
    required Trip trip,
    DateTime? generatedAt,
    double? currentOdometerKm,
    List<DtcCode> storedDtcs = const [],
    List<DtcCode> pendingDtcs = const [],
    ParkedCarSnapshot? latestSnapshot,
    int attachedSampleCount = 0,
  }) {
    return MechanicDiagnosticReport(
      reportId: reportId,
      generatedAt: generatedAt ?? trip.endTime,
      vehicle: vehicle,
      currentOdometerKm: currentOdometerKm ??
          vehicle.effectiveOdometerKm(trip.distanceKm),
      storedDtcs: storedDtcs,
      pendingDtcs: pendingDtcs,
      recentAnomalies: trip.anomalies,
      latestSnapshot: latestSnapshot,
      attachedTripId: trip.id,
      attachedSampleCount: attachedSampleCount,
    );
  }

  /// True if any confirmed/pending DTCs or recent anomaly episodes exist.
  bool get hasFaults =>
      storedDtcs.isNotEmpty ||
      pendingDtcs.isNotEmpty ||
      recentAnomalies.isNotEmpty;

  static String severityToPl(String severity) => _severityPl(severity);
  static String fuelTypeToPl(FuelType ft) => _fuelTypePl(ft);
  static String systemToPl(String system) => _systemPl(system);

  MechanicDiagnosticReport copyWith({
    String? reportId,
    DateTime? generatedAt,
    VehicleProfile? vehicle,
    double? currentOdometerKm,
    List<DtcCode>? storedDtcs,
    List<DtcCode>? pendingDtcs,
    List<TripAnomalyEpisode>? recentAnomalies,
    ParkedCarSnapshot? latestSnapshot,
    String? attachedTripId,
    int? attachedSampleCount,
  }) {
    return MechanicDiagnosticReport(
      reportId: reportId ?? this.reportId,
      generatedAt: generatedAt ?? this.generatedAt,
      vehicle: vehicle ?? this.vehicle,
      currentOdometerKm: currentOdometerKm ?? this.currentOdometerKm,
      storedDtcs: storedDtcs ?? this.storedDtcs,
      pendingDtcs: pendingDtcs ?? this.pendingDtcs,
      recentAnomalies: recentAnomalies ?? this.recentAnomalies,
      latestSnapshot: latestSnapshot ?? this.latestSnapshot,
      attachedTripId: attachedTripId ?? this.attachedTripId,
      attachedSampleCount: attachedSampleCount ?? this.attachedSampleCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        'generatedAt': generatedAt.toIso8601String(),
        'vehicle': vehicle.toJson(),
        'currentOdometerKm': currentOdometerKm,
        'storedDtcs': storedDtcs.map(_dtcToJson).toList(),
        'pendingDtcs': pendingDtcs.map(_dtcToJson).toList(),
        'recentAnomalies': recentAnomalies.map((a) => a.toJson()).toList(),
        if (latestSnapshot != null) 'latestSnapshot': latestSnapshot!.toJson(),
        if (attachedTripId != null) 'attachedTripId': attachedTripId,
        'attachedSampleCount': attachedSampleCount,
      };

  factory MechanicDiagnosticReport.fromJson(Map<String, dynamic> json) {
    final rawStored = json['storedDtcs'];
    final stored = <DtcCode>[];
    if (rawStored is Iterable) {
      for (final item in rawStored) {
        if (item is Map<String, dynamic>) {
          stored.add(_dtcFromJson(item));
        } else if (item is Map) {
          stored.add(_dtcFromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawPending = json['pendingDtcs'];
    final pending = <DtcCode>[];
    if (rawPending is Iterable) {
      for (final item in rawPending) {
        if (item is Map<String, dynamic>) {
          pending.add(_dtcFromJson(item));
        } else if (item is Map) {
          pending.add(_dtcFromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawAnomalies = json['recentAnomalies'];
    final anomalies = <TripAnomalyEpisode>[];
    if (rawAnomalies is Iterable) {
      for (final item in rawAnomalies) {
        if (item is Map<String, dynamic>) {
          anomalies.add(TripAnomalyEpisode.fromJson(item));
        } else if (item is Map) {
          anomalies.add(
              TripAnomalyEpisode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawSnapshot = json['latestSnapshot'];
    ParkedCarSnapshot? snapshot;
    if (rawSnapshot is Map<String, dynamic>) {
      snapshot = ParkedCarSnapshot.fromJson(rawSnapshot);
    } else if (rawSnapshot is Map) {
      snapshot =
          ParkedCarSnapshot.fromJson(Map<String, dynamic>.from(rawSnapshot));
    }

    final rawVehicle = json['vehicle'];
    final VehicleProfile vehicle;
    if (rawVehicle is Map<String, dynamic>) {
      vehicle = VehicleProfile.fromJson(rawVehicle);
    } else if (rawVehicle is Map) {
      vehicle = VehicleProfile.fromJson(Map<String, dynamic>.from(rawVehicle));
    } else {
      vehicle = VehicleProfile.defaultSuzukiSwiftM15A();
    }

    return MechanicDiagnosticReport(
      reportId: (json['reportId'] ?? '').toString(),
      generatedAt: json['generatedAt'] != null
          ? DateTime.tryParse(json['generatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      vehicle: vehicle,
      currentOdometerKm: _toDouble(json['currentOdometerKm']),
      storedDtcs: stored,
      pendingDtcs: pending,
      recentAnomalies: anomalies,
      latestSnapshot: snapshot,
      attachedTripId: json['attachedTripId']?.toString(),
      attachedSampleCount: _toInt(json['attachedSampleCount']),
    );
  }

  /// Formats the report into a clear, printable text summary suitable for sharing
  /// with a professional mechanic or service department.
  String toFormattedTextSummary({String language = 'en'}) {
    final isPl = language.toLowerCase() == 'pl';
    final buffer = StringBuffer();

    if (isPl) {
      buffer.writeln('========================================');
      buffer.writeln('     RAPORT DIAGNOSTYCZNY OBDRIVE       ');
      buffer.writeln('========================================');
      buffer.writeln('Identyfikator raportu: $reportId');
      buffer.writeln('Wygenerowano: ${generatedAt.toIso8601String()}');
      buffer.writeln();
      buffer.writeln('--- INFORMACJE O POJEŹDZIE ---');
      buffer.writeln('Pojazd: ${vehicle.name}');
      buffer.writeln('VIN: ${vehicle.vin ?? "Brak danych"}');
      buffer.writeln('Rodzaj paliwa: ${_fuelTypePl(vehicle.fuelType)}');
      buffer.writeln('Przebieg całkowity: ${currentOdometerKm.toStringAsFixed(1)} km');
      if (attachedTripId != null) {
        buffer.writeln(
            'Załączona trasa: $attachedTripId ($attachedSampleCount próbek)');
      }
      buffer.writeln();

      buffer.writeln('--- ZAPISANE KODY BŁĘDÓW (TRYB 03) ---');
      if (storedDtcs.isEmpty) {
        buffer.writeln('Brak zapisanych kodów DTC.');
      } else {
        for (final dtc in storedDtcs) {
          buffer.writeln('[${dtc.code}] (${_severityPl(dtc.severity)}) ${dtc.title}');
          buffer.writeln('  Układ: ${_systemPl(dtc.system)}');
          buffer.writeln('  Opis: ${dtc.description}');
          buffer.writeln(
              '  Możliwe przyczyny / zalecane kroki: ${dtc.possibleCauses}');
        }
      }
      buffer.writeln();

      buffer.writeln('--- OCZEKUJĄCE KODY BŁĘDÓW (TRYB 07) ---');
      if (pendingDtcs.isEmpty) {
        buffer.writeln('Brak oczekujących kodów DTC.');
      } else {
        for (final dtc in pendingDtcs) {
          buffer.writeln('[${dtc.code}] (${_severityPl(dtc.severity)}) ${dtc.title}');
          buffer.writeln('  Układ: ${_systemPl(dtc.system)}');
          buffer.writeln('  Opis: ${dtc.description}');
          buffer.writeln(
              '  Możliwe przyczyny / zalecane kroki: ${dtc.possibleCauses}');
        }
      }
      buffer.writeln();

      buffer.writeln('--- OSTATNIE WYKRYTE ANOMALIE ---');
      if (recentAnomalies.isEmpty) {
        buffer.writeln('Brak wykrytych anomalii.');
      } else {
        for (final anomaly in recentAnomalies) {
          buffer.writeln(
              '• ${anomaly.title} [${_severityPl(anomaly.severity.name).toUpperCase()}]');
          buffer.writeln('  Czas: ${anomaly.startTime.toIso8601String()}');
          if (anomaly.latitude != null && anomaly.longitude != null) {
            buffer.writeln(
                '  Pozycja GPS: ${anomaly.latitude}, ${anomaly.longitude}');
          }
          buffer.writeln('  Opis: ${anomaly.description}');
          if (anomaly.dtcCodes.isNotEmpty) {
            buffer.writeln('  Powiązane kody DTC: ${anomaly.dtcCodes.join(', ')}');
          }
        }
      }
      buffer.writeln();

      buffer.writeln('--- OSTATNIA TELEMETRIA POSTOJU ---');
      if (latestSnapshot != null) {
        final snap = latestSnapshot!;
        buffer.writeln(
            'Napięcie akumulatora: ${snap.batteryVoltage.toStringAsFixed(2)} V');
        buffer.writeln(
            'Temperatura płynu chłodzącego: ${snap.coolantTempC.toStringAsFixed(1)} °C');
        buffer.writeln(
            'Pozostałe paliwo: ${snap.remainingFuelLiters.toStringAsFixed(1)} L (${snap.fuelLevelPercent.toStringAsFixed(1)}%)');
        buffer.writeln(
            'Szacowany zasięg: ${snap.estimatedRangeKm.toStringAsFixed(1)} km');
        if (snap.hasCoordinates) {
          buffer.writeln('Pozycja GPS: ${snap.latitude}, ${snap.longitude}');
        }
      } else {
        buffer.writeln('Brak danych telemetrycznych postoju.');
      }
      buffer.writeln('========================================');
      return buffer.toString();
    }

    buffer.writeln('========================================');
    buffer.writeln('      OBDRIVE DIAGNOSTIC REPORT         ');
    buffer.writeln('========================================');
    buffer.writeln('Report ID: $reportId');
    buffer.writeln('Generated: ${generatedAt.toIso8601String()}');
    buffer.writeln();
    buffer.writeln('--- VEHICLE INFORMATION ---');
    buffer.writeln('Vehicle: ${vehicle.name}');
    buffer.writeln('VIN: ${vehicle.vin ?? "N/A"}');
    buffer.writeln('Fuel Type: ${vehicle.fuelType.label}');
    buffer.writeln('Odometer: ${currentOdometerKm.toStringAsFixed(1)} km');
    if (attachedTripId != null) {
      buffer.writeln(
          'Attached Trip ID: $attachedTripId ($attachedSampleCount samples)');
    }
    buffer.writeln();

    buffer.writeln('--- STORED DIAGNOSTIC CODES (MODE 03) ---');
    if (storedDtcs.isEmpty) {
      buffer.writeln('No stored DTCs detected.');
    } else {
      for (final dtc in storedDtcs) {
        buffer.writeln('[${dtc.code}] (${dtc.severity}) ${dtc.title}');
        buffer.writeln('  System: ${dtc.system}');
        buffer.writeln('  Description: ${dtc.description}');
        buffer.writeln(
            '  Possible Causes / Recommended Fix: ${dtc.possibleCauses}');
      }
    }
    buffer.writeln();

    buffer.writeln('--- PENDING DIAGNOSTIC CODES (MODE 07) ---');
    if (pendingDtcs.isEmpty) {
      buffer.writeln('No pending DTCs detected.');
    } else {
      for (final dtc in pendingDtcs) {
        buffer.writeln('[${dtc.code}] (${dtc.severity}) ${dtc.title}');
        buffer.writeln('  System: ${dtc.system}');
        buffer.writeln('  Description: ${dtc.description}');
        buffer.writeln(
            '  Possible Causes / Recommended Fix: ${dtc.possibleCauses}');
      }
    }
    buffer.writeln();

    buffer.writeln('--- RECENT ANOMALY EPISODES ---');
    if (recentAnomalies.isEmpty) {
      buffer.writeln('No anomalies detected.');
    } else {
      for (final anomaly in recentAnomalies) {
        buffer.writeln(
            '• ${anomaly.title} [${anomaly.severity.name.toUpperCase()}]');
        buffer.writeln('  Timestamp: ${anomaly.startTime.toIso8601String()}');
        if (anomaly.latitude != null && anomaly.longitude != null) {
          buffer.writeln(
              '  GPS Coordinates: ${anomaly.latitude}, ${anomaly.longitude}');
        }
        buffer.writeln('  Description: ${anomaly.description}');
        if (anomaly.dtcCodes.isNotEmpty) {
          buffer.writeln('  Associated DTCs: ${anomaly.dtcCodes.join(', ')}');
        }
      }
    }
    buffer.writeln();

    buffer.writeln('--- LATEST PARKED TELEMETRY ---');
    if (latestSnapshot != null) {
      final snap = latestSnapshot!;
      buffer.writeln(
          'Battery Voltage: ${snap.batteryVoltage.toStringAsFixed(2)} V');
      buffer.writeln(
          'Coolant Temp: ${snap.coolantTempC.toStringAsFixed(1)} °C');
      buffer.writeln(
          'Fuel Remaining: ${snap.remainingFuelLiters.toStringAsFixed(1)} L (${snap.fuelLevelPercent.toStringAsFixed(1)}%)');
      buffer.writeln(
          'Estimated Range: ${snap.estimatedRangeKm.toStringAsFixed(1)} km');
      if (snap.hasCoordinates) {
        buffer.writeln('Parked GPS: ${snap.latitude}, ${snap.longitude}');
      }
    } else {
      buffer.writeln('No parked snapshot available.');
    }
    buffer.writeln('========================================');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MechanicDiagnosticReport &&
          runtimeType == other.runtimeType &&
          reportId == other.reportId &&
          generatedAt == other.generatedAt &&
          vehicle == other.vehicle &&
          currentOdometerKm == other.currentOdometerKm &&
          listEquals(storedDtcs, other.storedDtcs) &&
          listEquals(pendingDtcs, other.pendingDtcs) &&
          listEquals(recentAnomalies, other.recentAnomalies) &&
          latestSnapshot == other.latestSnapshot &&
          attachedTripId == other.attachedTripId &&
          attachedSampleCount == other.attachedSampleCount;

  @override
  int get hashCode => Object.hash(
        reportId,
        generatedAt,
        vehicle,
        currentOdometerKm,
        Object.hashAll(storedDtcs),
        Object.hashAll(pendingDtcs),
        Object.hashAll(recentAnomalies),
        latestSnapshot,
        attachedTripId,
        attachedSampleCount,
      );

  @override
  String toString() =>
      'MechanicDiagnosticReport(id: $reportId, vehicle: ${vehicle.name}, '
      'stored: ${storedDtcs.length}, pending: ${pendingDtcs.length}, '
      'anomalies: ${recentAnomalies.length}, faults: $hasFaults)';
}

/// Metadata manifest exchanged during initial Bluetooth synchronization handshake.
/// Describes all trips and state available on the device so the peer can calculate
/// differential sync payloads.
@immutable
class SyncManifest {
  final String deviceId;
  final String deviceRole; // 'headunit' or 'phone'
  final DateTime generatedAt;
  final List<String> tripIds;
  final List<String> timeseriesTripIds;
  final String? activeVehicleId;
  final DateTime? latestGarageUpdatedAt;
  final DateTime? latestSnapshotTimestamp;

  const SyncManifest({
    required this.deviceId,
    required this.deviceRole,
    required this.generatedAt,
    this.tripIds = const [],
    this.timeseriesTripIds = const [],
    this.activeVehicleId,
    this.latestGarageUpdatedAt,
    this.latestSnapshotTimestamp,
  });

  /// Computes the list of trip IDs present in this manifest that are missing
  /// from the peer's [knownTripIds] set.
  List<String> computeMissingTripIds(Set<String> knownTripIds) {
    return tripIds.where((id) => !knownTripIds.contains(id)).toList();
  }

  /// Computes the list of timeseries trip IDs present in this manifest that are missing
  /// from the peer's [knownTimeseriesIds] set.
  List<String> computeMissingTimeseriesIds(Set<String> knownTimeseriesIds) {
    return timeseriesTripIds
        .where((id) => !knownTimeseriesIds.contains(id))
        .toList();
  }

  SyncManifest copyWith({
    String? deviceId,
    String? deviceRole,
    DateTime? generatedAt,
    List<String>? tripIds,
    List<String>? timeseriesTripIds,
    String? activeVehicleId,
    DateTime? latestGarageUpdatedAt,
    DateTime? latestSnapshotTimestamp,
  }) {
    return SyncManifest(
      deviceId: deviceId ?? this.deviceId,
      deviceRole: deviceRole ?? this.deviceRole,
      generatedAt: generatedAt ?? this.generatedAt,
      tripIds: tripIds ?? this.tripIds,
      timeseriesTripIds: timeseriesTripIds ?? this.timeseriesTripIds,
      activeVehicleId: activeVehicleId ?? this.activeVehicleId,
      latestGarageUpdatedAt:
          latestGarageUpdatedAt ?? this.latestGarageUpdatedAt,
      latestSnapshotTimestamp:
          latestSnapshotTimestamp ?? this.latestSnapshotTimestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceRole': deviceRole,
        'generatedAt': generatedAt.toIso8601String(),
        'tripIds': tripIds,
        'timeseriesTripIds': timeseriesTripIds,
        if (activeVehicleId != null) 'activeVehicleId': activeVehicleId,
        if (latestGarageUpdatedAt != null)
          'latestGarageUpdatedAt': latestGarageUpdatedAt!.toIso8601String(),
        if (latestSnapshotTimestamp != null)
          'latestSnapshotTimestamp': latestSnapshotTimestamp!.toIso8601String(),
      };

  factory SyncManifest.fromJson(Map<String, dynamic> json) {
    final rawTripIds = json['tripIds'];
    final parsedTripIds = <String>[];
    if (rawTripIds is Iterable) {
      for (final item in rawTripIds) {
        if (item != null) parsedTripIds.add(item.toString());
      }
    }

    final rawTimeseries = json['timeseriesTripIds'];
    final parsedTimeseries = <String>[];
    if (rawTimeseries is Iterable) {
      for (final item in rawTimeseries) {
        if (item != null) parsedTimeseries.add(item.toString());
      }
    }

    return SyncManifest(
      deviceId: (json['deviceId'] ?? '').toString(),
      deviceRole: (json['deviceRole'] ?? 'headunit').toString(),
      generatedAt: json['generatedAt'] != null
          ? DateTime.tryParse(json['generatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      tripIds: parsedTripIds,
      timeseriesTripIds: parsedTimeseries,
      activeVehicleId: json['activeVehicleId']?.toString(),
      latestGarageUpdatedAt: json['latestGarageUpdatedAt'] != null
          ? DateTime.tryParse(json['latestGarageUpdatedAt'].toString())
          : null,
      latestSnapshotTimestamp: json['latestSnapshotTimestamp'] != null
          ? DateTime.tryParse(json['latestSnapshotTimestamp'].toString())
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncManifest &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          deviceRole == other.deviceRole &&
          generatedAt == other.generatedAt &&
          listEquals(tripIds, other.tripIds) &&
          listEquals(timeseriesTripIds, other.timeseriesTripIds) &&
          activeVehicleId == other.activeVehicleId &&
          latestGarageUpdatedAt == other.latestGarageUpdatedAt &&
          latestSnapshotTimestamp == other.latestSnapshotTimestamp;

  @override
  int get hashCode => Object.hash(
        deviceId,
        deviceRole,
        generatedAt,
        Object.hashAll(tripIds),
        Object.hashAll(timeseriesTripIds),
        activeVehicleId,
        latestGarageUpdatedAt,
        latestSnapshotTimestamp,
      );

  @override
  String toString() =>
      'SyncManifest(device: $deviceId [$deviceRole], trips: ${tripIds.length}, '
      'timeseries: ${timeseriesTripIds.length}, activeVehicle: $activeVehicleId)';
}

// -----------------------------------------------------------------------------
// Serialization Helpers
// -----------------------------------------------------------------------------

Map<String, dynamic> _dtcToJson(DtcCode dtc) => {
      'code': dtc.code,
      'system': dtc.system,
      'title': dtc.title,
      'description': dtc.description,
      'severity': dtc.severity,
      'isPending': dtc.isPending,
      'symptoms': dtc.symptoms,
      'possibleCauses': dtc.possibleCauses,
    };

DtcCode _dtcFromJson(Map<String, dynamic> json) => DtcCode(
      code: (json['code'] ?? '').toString(),
      system: (json['system'] ?? 'Powertrain').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      severity: (json['severity'] ?? 'Warning').toString(),
      isPending: json['isPending'] == true,
      symptoms: (json['symptoms'] ??
              'Check Engine Light illuminated, possible performance decrease')
          .toString(),
      possibleCauses: (json['possibleCauses'] ??
              'Sensor fault, wiring issue, or component wear')
          .toString(),
    );

double _toDouble(dynamic val, [double defaultValue = 0.0]) {
  if (val == null) return defaultValue;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString()) ?? defaultValue;
}

double? _toDoubleNullable(dynamic val) {
  if (val == null) return null;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString());
}

int _toInt(dynamic val, [int defaultValue = 0]) {
  if (val == null) return defaultValue;
  if (val is num) return val.toInt();
  return int.tryParse(val.toString()) ?? defaultValue;
}

String _fuelTypePl(FuelType ft) {
  switch (ft) {
    case FuelType.gasoline:
      return 'Benzyna';
    case FuelType.lpg:
      return 'LPG';
    case FuelType.diesel:
      return 'Diesel';
    case FuelType.hybrid:
      return 'Hybryda';
  }
}

String _severityPl(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return 'Krytyczny';
    case 'warning':
      return 'Ostrzeżenie';
    case 'problem':
      return 'Problem';
    case 'info':
    case 'information':
      return 'Informacja';
    default:
      return severity;
  }
}

String _systemPl(String system) {
  switch (system.toLowerCase()) {
    case 'powertrain':
      return 'Układ napędowy';
    case 'chassis':
      return 'Podwozie';
    case 'body':
      return 'Nadwozie';
    case 'network':
      return 'Sieć / Komunikacja';
    default:
      return system;
  }
}

