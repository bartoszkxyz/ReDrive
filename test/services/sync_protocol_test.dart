import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/models/trip_route_point.dart';
import 'package:redrive/models/vehicle_profile.dart';
import 'package:redrive/services/sync/sync_protocol.dart';

void main() {
  group('ParkedCarSnapshot', () {
    final fixedTime = DateTime.parse('2026-10-18T12:00:00Z');

    test('round-trip JSON serialization with full coordinates', () {
      final snapshot = ParkedCarSnapshot(
        timestamp: fixedTime,
        vehicleId: 'swift_07',
        vehicleName: 'Suzuki Swift 3',
        latitude: 42.6977,
        longitude: 23.3219,
        remainingFuelLiters: 35.5,
        fuelLevelPercent: 78.9,
        estimatedRangeKm: 512.0,
        batteryVoltage: 12.55,
        coolantTempC: 85.0,
        odometerKm: 154210.3,
        lastTripId: 'trip_1001',
      );

      final json = snapshot.toJson();
      final parsed = ParkedCarSnapshot.fromJson(json);

      expect(parsed, equals(snapshot));
      expect(parsed.hasCoordinates, isTrue);
      expect(parsed.latitude, 42.6977);
      expect(parsed.longitude, 23.3219);
      expect(parsed.lastTripId, 'trip_1001');
    });

    test('handles null coordinates and default fallback values in fromJson',
        () {
      final snapshot = ParkedCarSnapshot(
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        vehicleId: 'default_car',
        vehicleName: 'Car',
      );

      final parsed = ParkedCarSnapshot.fromJson({
        'vehicleId': 'default_car',
        'vehicleName': 'Car',
      });

      expect(parsed.hasCoordinates, isFalse);
      expect(parsed.latitude, isNull);
      expect(parsed.longitude, isNull);
      expect(parsed.remainingFuelLiters, 0.0);
      expect(parsed.fuelLevelPercent, 0.0);
      expect(parsed.estimatedRangeKm, 0.0);
      expect(parsed.batteryVoltage, 12.6);
      expect(parsed.coolantTempC, 20.0);
      expect(parsed.odometerKm, 0.0);
      expect(parsed.lastTripId, isNull);
      expect(parsed, equals(snapshot));
    });

    test('hasCoordinates evaluates latitude and longitude presence correctly',
        () {
      expect(
        ParkedCarSnapshot(
          timestamp: fixedTime,
          vehicleId: '1',
          vehicleName: 'Car',
          latitude: 42.0,
          longitude: 23.0,
        ).hasCoordinates,
        isTrue,
      );

      expect(
        ParkedCarSnapshot(
          timestamp: fixedTime,
          vehicleId: '1',
          vehicleName: 'Car',
          latitude: 42.0,
          longitude: null,
        ).hasCoordinates,
        isFalse,
      );

      expect(
        ParkedCarSnapshot(
          timestamp: fixedTime,
          vehicleId: '1',
          vehicleName: 'Car',
          latitude: null,
          longitude: 23.0,
        ).hasCoordinates,
        isFalse,
      );

      expect(
        ParkedCarSnapshot(
          timestamp: fixedTime,
          vehicleId: '1',
          vehicleName: 'Car',
        ).hasCoordinates,
        isFalse,
      );
    });

    test('copyWith updates specified fields and retains others', () {
      final initial = ParkedCarSnapshot(
        timestamp: fixedTime,
        vehicleId: 'v1',
        vehicleName: 'Original Car',
        latitude: 10.0,
        longitude: 20.0,
        remainingFuelLiters: 20.0,
        batteryVoltage: 12.4,
      );

      final updated = initial.copyWith(
        vehicleName: 'Updated Car',
        batteryVoltage: 12.8,
        latitude: null,
      );

      expect(updated.vehicleName, 'Updated Car');
      expect(updated.batteryVoltage, 12.8);
      expect(updated.vehicleId, 'v1');
      expect(updated.remainingFuelLiters, 20.0);
      expect(updated.longitude, 20.0);
    });

    test('equality and hashCode contract', () {
      final snapA = ParkedCarSnapshot(
        timestamp: fixedTime,
        vehicleId: 'v1',
        vehicleName: 'Swift',
        remainingFuelLiters: 25.0,
      );
      final snapB = ParkedCarSnapshot(
        timestamp: fixedTime,
        vehicleId: 'v1',
        vehicleName: 'Swift',
        remainingFuelLiters: 25.0,
      );
      final snapC = snapA.copyWith(remainingFuelLiters: 30.0);

      expect(snapA, equals(snapB));
      expect(snapA.hashCode, equals(snapB.hashCode));
      expect(snapA, isNot(equals(snapC)));
    });
  });

  group('MechanicDiagnosticReport', () {
    final fixedTime = DateTime.parse('2026-10-18T14:30:00Z');
    final vehicle = VehicleProfile.defaultSuzukiSwiftM15A().copyWith(
      vin: 'TS18SUZUKISWIFT07',
    );

    const storedDtc = DtcCode(
      code: 'P0300',
      system: 'Powertrain',
      title: 'Random/Multiple Cylinder Misfire Detected',
      description: 'Multiple cylinders misfiring under load',
      severity: 'Critical',
      isPending: false,
      symptoms: 'Rough idle, loss of acceleration',
      possibleCauses: 'Faulty ignition coil, spark plug wear, vacuum leak',
    );

    const pendingDtc = DtcCode(
      code: 'P0171',
      system: 'Powertrain',
      title: 'System Too Lean (Bank 1)',
      description: 'Fuel trim system lean bank 1',
      severity: 'Warning',
      isPending: true,
      symptoms: 'Check Engine Light pending',
      possibleCauses: 'Dirty MAF sensor or intake leak',
    );

    final anomaly = TripAnomalyEpisode(
      id: 'anom_01',
      severity: AnomalySeverity.problem,
      category: AnomalyCategory.powerLoss,
      title: 'Severe Engine Misfire',
      description: 'RPM drop under sustained high throttle',
      startTime: fixedTime,
      endTime: fixedTime.add(const Duration(seconds: 8)),
      dtcCodes: const ['P0300'],
      latitude: 42.6977,
      longitude: 23.3219,
    );

    final snapshot = ParkedCarSnapshot(
      timestamp: fixedTime,
      vehicleId: vehicle.id,
      vehicleName: vehicle.name,
      latitude: 42.6977,
      longitude: 23.3219,
      remainingFuelLiters: 38.2,
      fuelLevelPercent: 85.0,
      estimatedRangeKm: 550.0,
      batteryVoltage: 12.45,
      coolantTempC: 88.5,
      odometerKm: 150245.5,
    );

    test('round-trip JSON serialization with DTCs, anomalies, and snapshot',
        () {
      final report = MechanicDiagnosticReport(
        reportId: 'rep_1001',
        generatedAt: fixedTime,
        vehicle: vehicle,
        currentOdometerKm: 150245.5,
        storedDtcs: const [storedDtc],
        pendingDtcs: const [pendingDtc],
        recentAnomalies: [anomaly],
        latestSnapshot: snapshot,
        attachedTripId: 'trip_100',
        attachedSampleCount: 1500,
      );

      final json = report.toJson();
      final parsed = MechanicDiagnosticReport.fromJson(json);

      expect(parsed, equals(report));
      expect(parsed.hasFaults, isTrue);
      expect(parsed.storedDtcs.first.code, 'P0300');
      expect(parsed.pendingDtcs.first.code, 'P0171');
      expect(parsed.recentAnomalies.first.title, 'Severe Engine Misfire');
      expect(parsed.latestSnapshot?.batteryVoltage, 12.45);
      expect(parsed.attachedTripId, 'trip_100');
      expect(parsed.attachedSampleCount, 1500);
    });

    test('hasFaults detects stored DTCs, pending DTCs, and anomalies', () {
      final cleanReport = MechanicDiagnosticReport(
        reportId: 'rep_clean',
        generatedAt: fixedTime,
        vehicle: vehicle,
        currentOdometerKm: 150000.0,
      );
      expect(cleanReport.hasFaults, isFalse);

      final withStored = cleanReport.copyWith(storedDtcs: const [storedDtc]);
      expect(withStored.hasFaults, isTrue);

      final withPending = cleanReport.copyWith(pendingDtcs: const [pendingDtc]);
      expect(withPending.hasFaults, isTrue);

      final withAnomaly = cleanReport.copyWith(recentAnomalies: [anomaly]);
      expect(withAnomaly.hasFaults, isTrue);
    });

    test(
        'toFormattedTextSummary contains VIN, DTCs, anomaly titles, voltage, and fuel',
        () {
      final report = MechanicDiagnosticReport(
        reportId: 'rep_mech_fmt',
        generatedAt: fixedTime,
        vehicle: vehicle,
        currentOdometerKm: 150245.5,
        storedDtcs: const [storedDtc],
        pendingDtcs: const [pendingDtc],
        recentAnomalies: [anomaly],
        latestSnapshot: snapshot,
        attachedTripId: 'trip_555',
        attachedSampleCount: 1200,
      );

      final summary = report.toFormattedTextSummary();

      // Vehicle & Identifiers
      expect(summary, contains('Suzuki Swift 3'));
      expect(summary, contains('TS18SUZUKISWIFT07'));
      expect(summary, contains('Gasoline'));
      expect(summary, contains('150245.5 km'));

      // Stored DTCs
      expect(summary, contains('[P0300] (Critical)'));
      expect(
          summary, contains('Faulty ignition coil, spark plug wear, vacuum leak'));

      // Pending DTCs
      expect(summary, contains('[P0171] (Warning)'));
      expect(summary, contains('Dirty MAF sensor or intake leak'));

      // Recent Anomaly Episodes
      expect(summary, contains('Severe Engine Misfire [PROBLEM]'));
      expect(summary, contains('42.6977, 23.3219'));

      // Parked Telemetry
      expect(summary, contains('Battery Voltage: 12.45 V'));
      expect(summary, contains('Coolant Temp: 88.5 °C'));
      expect(summary, contains('Fuel Remaining: 38.2 L (85.0%)'));
      expect(summary, contains('Estimated Range: 550.0 km'));
    });

    test('toFormattedTextSummary handles clean report with null snapshot', () {
      final report = MechanicDiagnosticReport(
        reportId: 'rep_clean',
        generatedAt: fixedTime,
        vehicle: vehicle,
        currentOdometerKm: 150000.0,
      );

      final summary = report.toFormattedTextSummary();
      expect(summary, contains('No stored DTCs detected.'));
      expect(summary, contains('No pending DTCs detected.'));
      expect(summary, contains('No anomalies detected.'));
      expect(summary, contains('No parked snapshot available.'));
    });

    test('fromTrip factory binds trip telemetry and anomalies properly', () {
      final trip = Trip(
        id: 'trip_derived',
        startTime: fixedTime.subtract(const Duration(minutes: 30)),
        endTime: fixedTime,
        duration: const Duration(minutes: 30),
        distanceKm: 25.5,
        fuelConsumedLiters: 1.8,
        avgFuelConsumption: 7.05,
        avgSpeed: 51.0,
        maxSpeed: 88.0,
        maxRpm: 3400,
        avgRpm: 2100,
        anomalies: [anomaly],
        routePoints: const [
          TripRoutePoint(
            latitude: 42.69,
            longitude: 23.32,
            elapsedSeconds: 1.0,
            speedKmh: 45.0,
          ),
          TripRoutePoint(
            latitude: 42.70,
            longitude: 23.33,
            elapsedSeconds: 2.0,
            speedKmh: 55.0,
          ),
        ],
      );

      final report = MechanicDiagnosticReport.fromTrip(
        reportId: 'rep_from_trip',
        vehicle: vehicle,
        trip: trip,
        latestSnapshot: snapshot,
      );

      expect(report.reportId, 'rep_from_trip');
      expect(report.attachedTripId, 'trip_derived');
      expect(report.recentAnomalies.length, 1);
      expect(report.recentAnomalies.first.title, 'Severe Engine Misfire');
      expect(report.currentOdometerKm,
          vehicle.baseOdometerKm + trip.distanceKm);
      expect(report.latestSnapshot, equals(snapshot));
    });
  });

  group('SyncManifest', () {
    final fixedTime = DateTime.parse('2026-10-18T10:00:00Z');

    test('round-trip JSON serialization', () {
      final manifest = SyncManifest(
        deviceId: 'ts18_headunit_01',
        deviceRole: 'headunit',
        generatedAt: fixedTime,
        tripIds: const ['trip_1', 'trip_2', 'trip_3'],
        timeseriesTripIds: const ['trip_2', 'trip_3'],
        activeVehicleId: 'swift_07',
        latestGarageUpdatedAt: fixedTime,
        latestSnapshotTimestamp: fixedTime,
      );

      final json = manifest.toJson();
      final parsed = SyncManifest.fromJson(json);

      expect(parsed, equals(manifest));
      expect(parsed.deviceId, 'ts18_headunit_01');
      expect(parsed.deviceRole, 'headunit');
      expect(parsed.tripIds, const ['trip_1', 'trip_2', 'trip_3']);
      expect(parsed.timeseriesTripIds, const ['trip_2', 'trip_3']);
      expect(parsed.activeVehicleId, 'swift_07');
    });

    test('computeMissingTripIds filters out known trips', () {
      final manifest = SyncManifest(
        deviceId: 'dev1',
        deviceRole: 'headunit',
        generatedAt: fixedTime,
        tripIds: const ['trip_1', 'trip_2', 'trip_3', 'trip_4'],
      );

      final missing =
          manifest.computeMissingTripIds({'trip_1', 'trip_3', 'trip_99'});
      expect(missing, equals(['trip_2', 'trip_4']));

      final noneMissing = manifest.computeMissingTripIds(
          {'trip_1', 'trip_2', 'trip_3', 'trip_4', 'other'});
      expect(noneMissing, isEmpty);

      final allMissing = manifest.computeMissingTripIds(const <String>{});
      expect(allMissing, equals(['trip_1', 'trip_2', 'trip_3', 'trip_4']));
    });

    test('computeMissingTimeseriesIds filters out known timeseries', () {
      final manifest = SyncManifest(
        deviceId: 'dev1',
        deviceRole: 'headunit',
        generatedAt: fixedTime,
        timeseriesTripIds: const ['ts_1', 'ts_2', 'ts_3'],
      );

      final missing = manifest.computeMissingTimeseriesIds({'ts_2'});
      expect(missing, equals(['ts_1', 'ts_3']));
    });
  });

  group('SyncFrame Factories & JSON Round-Trip', () {
    final fixedTime = DateTime.parse('2026-10-18T10:00:00Z');
    final manifest = SyncManifest(
      deviceId: 'headunit_ts18',
      deviceRole: 'headunit',
      generatedAt: fixedTime,
      tripIds: const ['t1'],
    );
    final vehicle = VehicleProfile.defaultSuzukiSwiftM15A();
    final snapshot = ParkedCarSnapshot(
      timestamp: fixedTime,
      vehicleId: 'swift_07',
      vehicleName: 'Suzuki Swift 3',
    );
    final trip = Trip(
      id: 't1',
      startTime: fixedTime,
      endTime: fixedTime.add(const Duration(minutes: 10)),
      duration: const Duration(minutes: 10),
      distanceKm: 5.0,
      fuelConsumedLiters: 0.4,
      avgFuelConsumption: 8.0,
      avgSpeed: 30.0,
      maxSpeed: 50.0,
      maxRpm: 2500,
      avgRpm: 1800,
    );
    final report = MechanicDiagnosticReport(
      reportId: 'rep_1',
      generatedAt: fixedTime,
      vehicle: vehicle,
      currentOdometerKm: 150000.0,
    );

    test('hello frame round-trip and accessor', () {
      final frame = SyncFrame.hello(manifest, messageId: 'msg_hello');
      expect(frame.type, SyncFrameType.hello);
      expect(frame.messageId, 'msg_hello');

      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.hello);
      expect(parsed.messageId, 'msg_hello');
      final decodedManifest = parsed.asHelloManifest();
      expect(decodedManifest, isNotNull);
      expect(decodedManifest!.deviceId, manifest.deviceId);
    });

    test('requestSync frame round-trip', () {
      final frame = SyncFrame.requestSync(
        missingTripIds: const ['t1', 't2'],
        missingTimeseriesIds: const ['t2'],
        requestSnapshot: true,
        requestGarage: false,
        requestMechanicReport: true,
        messageId: 'req_1',
      );

      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.requestSync);
      expect(parsed.payload['missingTripIds'], const ['t1', 't2']);
      expect(parsed.payload['missingTimeseriesIds'], const ['t2']);
      expect(parsed.payload['requestSnapshot'], isTrue);
      expect(parsed.payload['requestGarage'], isFalse);
      expect(parsed.payload['requestMechanicReport'], isTrue);
    });

    test('tripPayload frame round-trip and accessor', () {
      final frame = SyncFrame.tripPayload(trip, messageId: 'trip_f1');
      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.tripPayload);
      final decodedTrip = parsed.asTrip();
      expect(decodedTrip, isNotNull);
      expect(decodedTrip!.id, trip.id);
      expect(decodedTrip.distanceKm, trip.distanceKm);
    });

    test('timeseriesChunk frame round-trip', () {
      final frame = SyncFrame.timeseriesChunk(
        tripId: 't1',
        chunkIndex: 0,
        totalChunks: 2,
        lines: const ['line1', 'line2'],
        isLast: false,
        messageId: 'ts_f0',
      );

      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.timeseriesChunk);
      expect(parsed.payload['tripId'], 't1');
      expect(parsed.payload['chunkIndex'], 0);
      expect(parsed.payload['totalChunks'], 2);
      expect(parsed.payload['lines'], const ['line1', 'line2']);
      expect(parsed.payload['isLast'], isFalse);
    });

    test('parkedSnapshot frame round-trip and accessor', () {
      final frame = SyncFrame.parkedSnapshot(snapshot, messageId: 'snap_f1');
      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.parkedSnapshot);
      final decodedSnap = parsed.asParkedSnapshot();
      expect(decodedSnap, isNotNull);
      expect(decodedSnap!.vehicleId, snapshot.vehicleId);
    });

    test('mechanicReport frame round-trip and accessor', () {
      final frame = SyncFrame.mechanicReport(report, messageId: 'mech_f1');
      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.mechanicReport);
      final decodedReport = parsed.asMechanicReport();
      expect(decodedReport, isNotNull);
      expect(decodedReport!.reportId, report.reportId);
    });

    test('garageSync frame round-trip', () {
      final frame = SyncFrame.garageSync(
        vehicles: [vehicle],
        activeVehicleId: vehicle.id,
        messageId: 'gar_f1',
      );

      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.garageSync);
      expect(parsed.payload['activeVehicleId'], vehicle.id);
      final vehicles = parsed.payload['vehicles'] as List;
      expect(vehicles.length, 1);
    });

    test('syncAck frame round-trip', () {
      final frame = SyncFrame.syncAck(
        syncedTripIds: const ['t1'],
        syncedTimeseriesTripIds: const ['t1'],
        messageId: 'ack_f1',
      );

      final json = frame.toJson();
      final parsed = SyncFrame.fromJson(json);

      expect(parsed.type, SyncFrameType.syncAck);
      expect(parsed.payload['syncedTripIds'], const ['t1']);
      expect(parsed.payload['syncedTimeseriesTripIds'], const ['t1']);
    });

    test('ping and pong frame round-trip', () {
      final ping = SyncFrame.ping(messageId: 'ping_1');
      final pong = SyncFrame.pong(messageId: 'pong_1');

      final parsedPing = SyncFrame.fromJson(ping.toJson());
      final parsedPong = SyncFrame.fromJson(pong.toJson());

      expect(parsedPing.type, SyncFrameType.ping);
      expect(parsedPong.type, SyncFrameType.pong);
    });

    test('error frame round-trip', () {
      final frame = SyncFrame.error('Connection reset', messageId: 'err_1');
      final parsed = SyncFrame.fromJson(frame.toJson());

      expect(parsed.type, SyncFrameType.error);
      expect(parsed.payload['error'], 'Connection reset');
    });
  });

  group('SyncProtocolCodec.frameDecoder', () {
    test('handles byte fragmentation across multiple chunks', () async {
      final frame = SyncFrame.parkedSnapshot(
        ParkedCarSnapshot(
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          vehicleId: 'swift_07',
          vehicleName: 'Suzuki Swift',
          latitude: 42.6977,
          longitude: 23.3219,
          remainingFuelLiters: 30.0,
        ),
        messageId: 'frag_test_msg',
      );

      final rawBytes = frame.encodeBytes();
      expect(rawBytes.last, equals(0x0A)); // Ends in newline '\n'

      // Split rawBytes into 5 arbitrary byte slices
      final step = (rawBytes.length / 5).ceil();
      final slices = <Uint8List>[];
      for (var i = 0; i < rawBytes.length; i += step) {
        final end = (i + step < rawBytes.length) ? i + step : rawBytes.length;
        slices.add(rawBytes.sublist(i, end));
      }

      final stream =
          Stream.fromIterable(slices).transform(SyncProtocolCodec.frameDecoder());
      final decodedFrames = await stream.toList();

      expect(decodedFrames.length, 1);
      final decoded = decodedFrames.first;
      expect(decoded.type, SyncFrameType.parkedSnapshot);
      expect(decoded.messageId, 'frag_test_msg');
      expect(decoded.payload['vehicleId'], 'swift_07');
      expect(decoded.payload['latitude'], 42.6977);
    });

    test('handles multiple coalesced frames in a single byte chunk', () async {
      final frame1 = SyncFrame.ping(messageId: 'p1');
      final frame2 = SyncFrame.pong(messageId: 'p2');
      final frame3 = SyncFrame.error('E3', messageId: 'p3');

      final combined = <int>[
        ...frame1.encodeBytes(),
        ...frame2.encodeBytes(),
        ...frame3.encodeBytes(),
      ];

      final stream = Stream.value(Uint8List.fromList(combined))
          .transform(SyncProtocolCodec.frameDecoder());
      final decodedFrames = await stream.toList();

      expect(decodedFrames.length, 3);
      expect(decodedFrames[0].type, SyncFrameType.ping);
      expect(decodedFrames[0].messageId, 'p1');
      expect(decodedFrames[1].type, SyncFrameType.pong);
      expect(decodedFrames[1].messageId, 'p2');
      expect(decodedFrames[2].type, SyncFrameType.error);
      expect(decodedFrames[2].messageId, 'p3');
    });

    test('gracefully skips corrupted, malformed, non-map, or empty lines',
        () async {
      final valid1 = SyncFrame.ping(messageId: 'valid_1');
      final valid2 = SyncFrame.pong(messageId: 'valid_2');

      final mixedPayload = [
        ...valid1.encodeBytes(),
        ...utf8.encode('CORRUPT_NOT_JSON\n'),
        ...utf8.encode('{"incomplete_json": \n'),
        ...utf8.encode('\n\n   \n'), // empty lines
        ...utf8.encode('12345\n'), // valid JSON but not a Map
        ...utf8.encode('"string_not_map"\n'),
        ...valid2.encodeBytes(),
      ];

      final stream = Stream.value(Uint8List.fromList(mixedPayload))
          .transform(SyncProtocolCodec.frameDecoder());
      final decodedFrames = await stream.toList();

      expect(decodedFrames.length, 2);
      expect(decodedFrames[0].messageId, 'valid_1');
      expect(decodedFrames[1].messageId, 'valid_2');
    });
  });

  group('SyncProtocolCodec.chunkTimeseriesLines & reassembleTimeseriesChunks',
      () {
    test(
        'chunks 125-line payload into 3 chunks (50, 50, 25) and reassembles out-of-order',
        () {
      const totalCount = 125;
      final rawLines = List.generate(
        totalCount,
        (i) => '{"sample": $i, "rpm": ${1200 + i * 10}, "speed": ${30 + i}}',
      );

      final chunks = SyncProtocolCodec.chunkTimeseriesLines(
        'trip_test_125',
        rawLines,
        maxLinesPerChunk: 50,
      );

      expect(chunks.length, 3);

      // Chunk 0: lines 0..49
      expect(chunks[0].payload['chunkIndex'], 0);
      expect(chunks[0].payload['totalChunks'], 3);
      expect((chunks[0].payload['lines'] as List).length, 50);
      expect(chunks[0].payload['isLast'], isFalse);

      // Chunk 1: lines 50..99
      expect(chunks[1].payload['chunkIndex'], 1);
      expect(chunks[1].payload['totalChunks'], 3);
      expect((chunks[1].payload['lines'] as List).length, 50);
      expect(chunks[1].payload['isLast'], isFalse);

      // Chunk 2: lines 100..124
      expect(chunks[2].payload['chunkIndex'], 2);
      expect(chunks[2].payload['totalChunks'], 3);
      expect((chunks[2].payload['lines'] as List).length, 25);
      expect(chunks[2].payload['isLast'], isTrue);

      // Shuffle the chunks out of order to verify sorting during reassembly
      final shuffled = [chunks[2], chunks[0], chunks[1]];
      final reassembled =
          SyncProtocolCodec.reassembleTimeseriesChunks(shuffled);

      expect(reassembled.length, totalCount);
      expect(reassembled, equals(rawLines));
    });

    test('handles empty lines list gracefully', () {
      final emptyChunks =
          SyncProtocolCodec.chunkTimeseriesLines('trip_empty', const []);

      expect(emptyChunks.length, 1);
      expect(emptyChunks.first.payload['chunkIndex'], 0);
      expect(emptyChunks.first.payload['totalChunks'], 1);
      expect(emptyChunks.first.payload['lines'], isEmpty);
      expect(emptyChunks.first.payload['isLast'], isTrue);

      final reassembled =
          SyncProtocolCodec.reassembleTimeseriesChunks(emptyChunks);
      expect(reassembled, isEmpty);
    });
  });
}
