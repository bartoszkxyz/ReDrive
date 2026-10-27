import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/sync_models.dart';
import 'package:obdrive/models/trip.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';
import 'package:obdrive/services/trip/trip_history_service.dart';
import 'package:obdrive/services/trip/trip_timeseries_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BluetoothSyncService & RFCOMM Synchronization Engine', () {
    test(
        'InMemorySyncTransportPair: bidirectional communication between Headunit server and Phone client',
        () async {
      final pair = InMemorySyncTransportPair();

      final headunitInbound = <String>[];
      final phoneInbound = <String>[];

      final sub1 = pair.phoneTransport.inboundBytes
          .transform(utf8.decoder)
          .listen((data) => phoneInbound.add(data));
      final sub2 = pair.headunitTransport.inboundBytes
          .transform(utf8.decoder)
          .listen((data) => headunitInbound.add(data));

      pair.headunitTransport.sendBytes(utf8.encode('FROM_HEADUNIT_FRAME\n'));
      pair.phoneTransport.sendBytes(utf8.encode('FROM_PHONE_FRAME\n'));

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(phoneInbound, contains('FROM_HEADUNIT_FRAME\n'));
      expect(headunitInbound, contains('FROM_PHONE_FRAME\n'));

      await sub1.cancel();
      await sub2.cancel();
      await pair.close();
    });

    test(
        'sync session: Headunit with 2 trips (1 with timeseries, 1 without) transfers missing trips and timeseries chunks to Phone',
        () async {
      final pair = InMemorySyncTransportPair();

      final headunitService = BluetoothSyncService(
        deviceId: 'headunit_ts18',
        deviceRole: 'headunit',
        inMemory: true,
      );

      final phoneService = BluetoothSyncService(
        deviceId: 'pixel_phone',
        deviceRole: 'phone',
        inMemory: true,
      );

      final startTime = DateTime.parse('2026-10-18T10:00:00Z');
      final tripWithTs = Trip(
        id: 'trip_ts_01',
        startTime: startTime,
        endTime: startTime.add(const Duration(minutes: 20)),
        duration: const Duration(minutes: 20),
        distanceKm: 15.5,
        fuelConsumedLiters: 1.1,
        avgFuelConsumption: 7.1,
        avgSpeed: 46.5,
        maxSpeed: 82.0,
        maxRpm: 3200,
        avgRpm: 2100,
        hasTimeseries: true,
      );

      final tripWithoutTs = Trip(
        id: 'trip_nots_02',
        startTime: startTime.add(const Duration(hours: 1)),
        endTime: startTime.add(const Duration(hours: 1, minutes: 15)),
        duration: const Duration(minutes: 15),
        distanceKm: 8.0,
        fuelConsumedLiters: 0.6,
        avgFuelConsumption: 7.5,
        avgSpeed: 32.0,
        maxSpeed: 60.0,
        maxRpm: 2800,
        avgRpm: 1900,
        hasTimeseries: false,
      );

      final expectedLines = List.generate(
        120,
        (i) => '{"sample": $i, "rpm": ${1500 + i * 5}, "speed": ${30 + i}}',
      );

      // Headunit delegate provides the 2 trips and timeseries lines for trip1
      headunitService.registerDelegate(
        SyncDataDelegate(
          getLocalTrips: () async => [tripWithTs, tripWithoutTs],
          getTimeseriesLines: (tripId) async {
            if (tripId == 'trip_ts_01') return expectedLines;
            return [];
          },
          onTripReceived: (trip, lines) async {},
          onTripsAcked: (syncedTrips, syncedTs) async {},
          getParkedSnapshot: () async => null,
          onParkedSnapshotReceived: (s) async {},
          getMechanicReport: () async => null,
          onMechanicReportReceived: (r) async {},
          getGarageData: () async =>
              (vehicles: <VehicleProfile>[], activeVehicleId: ''),
          onGarageDataReceived: (v, a) async {},
        ),
      );

      final receivedTrips = <Trip>[];
      final receivedTimeseries = <String, List<String>?>{};

      // Phone delegate initially has no trips
      phoneService.registerDelegate(
        SyncDataDelegate(
          getLocalTrips: () async => [],
          getTimeseriesLines: (id) async => [],
          onTripReceived: (trip, lines) async {
            receivedTrips.add(trip);
            receivedTimeseries[trip.id] = lines;
          },
          onTripsAcked: (syncedTrips, syncedTs) async {},
          getParkedSnapshot: () async => null,
          onParkedSnapshotReceived: (s) async {},
          getMechanicReport: () async => null,
          onMechanicReportReceived: (r) async {},
          getGarageData: () async =>
              (vehicles: <VehicleProfile>[], activeVehicleId: ''),
          onGarageDataReceived: (v, a) async {},
        ),
      );

      await headunitService.attachTransport(pair.headunitTransport);
      await phoneService.attachTransport(pair.phoneTransport);

      // Initiate sync session from Phone
      await phoneService.startSyncSession();

      // Allow async chunk transmission and reassembly
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(phoneService.state, equals(SyncConnectionState.synced));
      expect(headunitService.state, equals(SyncConnectionState.synced));

      expect(receivedTrips.length, equals(2));
      final ids = receivedTrips.map((t) => t.id).toSet();
      expect(ids, containsAll(['trip_ts_01', 'trip_nots_02']));

      // trip_ts_01 received all 120 timeseries lines across multi-frame chunks
      expect(receivedTimeseries['trip_ts_01'], isNotNull);
      expect(receivedTimeseries['trip_ts_01']!.length, equals(120));
      expect(receivedTimeseries['trip_ts_01'], equals(expectedLines));

      // trip_nots_02 did not have timeseries
      expect(receivedTimeseries['trip_nots_02'], isNull);

      await headunitService.dispose();
      await phoneService.dispose();
      await pair.close();
    });

    test(
        'SyncFrame.syncAck: Headunit marks transferred trips as synced and enforces retention policy',
        () async {
      final pair = InMemorySyncTransportPair();
      final tempDir = await Directory.systemTemp.createTemp('sync_ack_test_');

      try {
        final historyService = TripHistoryService(
          customFile: File('${tempDir.path}/trips.json'),
        );
        final timeseriesService = TripTimeseriesService(
          customDirectory: Directory('${tempDir.path}/timeseries'),
        );

        final startTime = DateTime.parse('2026-10-18T10:00:00Z');
        final trip1 = Trip(
          id: 'ack_trip_1',
          startTime: startTime,
          endTime: startTime.add(const Duration(minutes: 10)),
          duration: const Duration(minutes: 10),
          distanceKm: 5.0,
          fuelConsumedLiters: 0.4,
          avgFuelConsumption: 8.0,
          avgSpeed: 30.0,
          maxSpeed: 50.0,
          maxRpm: 2500,
          avgRpm: 1800,
          hasTimeseries: true,
          isSynced: false,
        );

        final trip2 = Trip(
          id: 'ack_trip_2',
          startTime: startTime.add(const Duration(minutes: 30)),
          endTime: startTime.add(const Duration(minutes: 40)),
          duration: const Duration(minutes: 10),
          distanceKm: 6.0,
          fuelConsumedLiters: 0.5,
          avgFuelConsumption: 8.3,
          avgSpeed: 36.0,
          maxSpeed: 55.0,
          maxRpm: 2600,
          avgRpm: 1900,
          hasTimeseries: false,
          isSynced: false,
        );

        await historyService.saveTrip(trip1);
        await historyService.saveTrip(trip2);
        final tsDir = Directory('${tempDir.path}/timeseries');
        await tsDir.create(recursive: true);
        await File('${tsDir.path}/trip_${trip1.id}.jsonl')
            .writeAsString('{"sample": 1}\n');

        final headunitService = BluetoothSyncService(
          deviceId: 'headunit_01',
          deviceRole: 'headunit',
          inMemory: true,
        );

        final phoneService = BluetoothSyncService(
          deviceId: 'phone_01',
          deviceRole: 'phone',
          inMemory: true,
        );

        final ackedTripsList = <String>[];
        final ackedTsList = <String>[];

        headunitService.registerDelegate(
          SyncDataDelegate(
            getLocalTrips: () async => await historyService.loadTrips(),
            getTimeseriesLines: (id) async =>
                await timeseriesService.readRawLines(id),
            onTripReceived: (t, lines) async {},
            onTripsAcked: (syncedTrips, syncedTs) async {
              ackedTripsList.addAll(syncedTrips);
              ackedTsList.addAll(syncedTs);

              // Update history to mark trips synced
              for (final id in syncedTrips) {
                final trips = await historyService.loadTrips();
                for (final tr in trips) {
                  if (tr.id == id) {
                    await historyService.saveTrip(tr.copyWith(isSynced: true));
                  }
                }
              }

              // Enforce retention policy
              final updated = await historyService.loadTrips();
              await timeseriesService.enforceSyncAwareRetentionPolicy(
                updated,
                maxSyncedTrips: 1,
              );
            },
            getParkedSnapshot: () async => null,
            onParkedSnapshotReceived: (s) async {},
            getMechanicReport: () async => null,
            onMechanicReportReceived: (r) async {},
            getGarageData: () async =>
                (vehicles: <VehicleProfile>[], activeVehicleId: ''),
            onGarageDataReceived: (v, a) async {},
          ),
        );

        phoneService.registerDelegate(
          SyncDataDelegate(
            getLocalTrips: () async => [],
            getTimeseriesLines: (id) async => [],
            onTripReceived: (t, lines) async {},
            onTripsAcked: (st, sts) async {},
            getParkedSnapshot: () async => null,
            onParkedSnapshotReceived: (s) async {},
            getMechanicReport: () async => null,
            onMechanicReportReceived: (r) async {},
            getGarageData: () async =>
                (vehicles: <VehicleProfile>[], activeVehicleId: ''),
            onGarageDataReceived: (v, a) async {},
          ),
        );

        await headunitService.attachTransport(pair.headunitTransport);
        await phoneService.attachTransport(pair.phoneTransport);

        await phoneService.startSyncSession();
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Verify headunit received ACK for both trips and timeseries
        expect(ackedTripsList, containsAll(['ack_trip_1', 'ack_trip_2']));
        expect(ackedTsList, contains('ack_trip_1'));

        // Verify history service persisted isSynced: true
        final savedTrips = await historyService.loadTrips();
        for (final st in savedTrips) {
          expect(st.isSynced, isTrue, reason: 'Trip ${st.id} should be marked synced');
        }

        await headunitService.dispose();
        await phoneService.dispose();
        await pair.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test(
        'ParkedCarSnapshot and MechanicDiagnosticReport transfer and local persistence',
        () async {
      final pair = InMemorySyncTransportPair();
      final tempDir =
          await Directory.systemTemp.createTemp('snapshot_report_test_');

      try {
        final fixedTime = DateTime.parse('2026-10-18T12:00:00Z');
        final snapshot = ParkedCarSnapshot(
          timestamp: fixedTime,
          vehicleId: 'swift_07',
          vehicleName: 'Suzuki Swift 3',
          latitude: 42.6977,
          longitude: 23.3219,
          remainingFuelLiters: 34.0,
          fuelLevelPercent: 75.0,
          estimatedRangeKm: 480.0,
          batteryVoltage: 12.55,
          odometerKm: 150240.0,
        );

        final report = MechanicDiagnosticReport(
          reportId: 'rep_test_01',
          generatedAt: fixedTime,
          vehicle: VehicleProfile.defaultSuzukiSwiftM15A(),
          currentOdometerKm: 150240.0,
          storedDtcs: const [
            DtcCode(
              code: 'P0300',
              system: 'Powertrain',
              title: 'Random Misfire',
              description: 'Multiple cylinders misfiring',
              severity: 'Critical',
              isPending: false,
              symptoms: 'Check engine light',
              possibleCauses: 'Ignition coil wear',
            ),
          ],
          latestSnapshot: snapshot,
        );

        final phoneFile = File('${tempDir.path}/phone_sync_state.json');

        final headunitService = BluetoothSyncService(
          deviceId: 'headunit_01',
          deviceRole: 'headunit',
          inMemory: true,
        );

        final phoneService = BluetoothSyncService(
          deviceId: 'phone_01',
          deviceRole: 'phone',
          customStateFile: phoneFile,
          inMemory: false,
        );

        ParkedCarSnapshot? receivedSnapshot;
        MechanicDiagnosticReport? receivedReport;

        headunitService.registerDelegate(
          SyncDataDelegate(
            getLocalTrips: () async => [],
            getTimeseriesLines: (id) async => [],
            onTripReceived: (t, lines) async {},
            onTripsAcked: (st, sts) async {},
            getParkedSnapshot: () async => snapshot,
            onParkedSnapshotReceived: (s) async {},
            getMechanicReport: () async => report,
            onMechanicReportReceived: (r) async {},
            getGarageData: () async =>
                (vehicles: <VehicleProfile>[], activeVehicleId: ''),
            onGarageDataReceived: (v, a) async {},
          ),
        );

        phoneService.registerDelegate(
          SyncDataDelegate(
            getLocalTrips: () async => [],
            getTimeseriesLines: (id) async => [],
            onTripReceived: (t, lines) async {},
            onTripsAcked: (st, sts) async {},
            getParkedSnapshot: () async => null,
            onParkedSnapshotReceived: (s) async {
              receivedSnapshot = s;
            },
            getMechanicReport: () async => null,
            onMechanicReportReceived: (r) async {
              receivedReport = r;
            },
            getGarageData: () async =>
                (vehicles: <VehicleProfile>[], activeVehicleId: ''),
            onGarageDataReceived: (v, a) async {},
          ),
        );

        await headunitService.attachTransport(pair.headunitTransport);
        await phoneService.attachTransport(pair.phoneTransport);

        await phoneService.startSyncSession(requestMechanicReport: true);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Check snapshot & report received in memory
        expect(receivedSnapshot, equals(snapshot));
        expect(phoneService.latestSnapshot, equals(snapshot));

        expect(receivedReport, isNotNull);
        expect(receivedReport!.reportId, equals('rep_test_01'));
        expect(receivedReport!.storedDtcs.first.code, equals('P0300'));
        expect(phoneService.latestMechanicReport?.reportId, equals('rep_test_01'));

        // Check disk persistence on phone
        expect(await phoneFile.exists(), isTrue);

        // Reload into a fresh service instance from disk
        final restoredPhoneService = BluetoothSyncService(
          deviceId: 'phone_01',
          deviceRole: 'phone',
          customStateFile: phoneFile,
          inMemory: false,
        );
        await restoredPhoneService.loadPersistedState();

        expect(restoredPhoneService.latestSnapshot, equals(snapshot));
        expect(restoredPhoneService.latestMechanicReport?.reportId,
            equals('rep_test_01'));
        expect(restoredPhoneService.latestMechanicReport?.storedDtcs.first.code,
            equals('P0300'));

        await headunitService.dispose();
        await phoneService.dispose();
        await restoredPhoneService.dispose();
        await pair.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('GarageSync: Phone pushes garage vehicle profiles to Headunit',
        () async {
      final pair = InMemorySyncTransportPair();

      final headunitService = BluetoothSyncService(
        deviceId: 'headunit_01',
        deviceRole: 'headunit',
        inMemory: true,
      );

      final phoneService = BluetoothSyncService(
        deviceId: 'phone_01',
        deviceRole: 'phone',
        inMemory: true,
      );

      final car1 = VehicleProfile.defaultSuzukiSwiftM15A();
      final car2 = VehicleProfile(
        id: 'car_custom_2',
        name: 'Toyota Corolla E120',
        year: 2005,
        displacementLiters: 1.6,
        fuelType: FuelType.gasoline,
        fuelTankCapacityLiters: 50.0,
        baseOdometerKm: 210000.0,
      );

      List<VehicleProfile>? headunitReceivedGarage;
      String? headunitActiveVehicleId;

      headunitService.registerDelegate(
        SyncDataDelegate(
          getLocalTrips: () async => [],
          getTimeseriesLines: (id) async => [],
          onTripReceived: (t, lines) async {},
          onTripsAcked: (st, sts) async {},
          getParkedSnapshot: () async => null,
          onParkedSnapshotReceived: (s) async {},
          getMechanicReport: () async => null,
          onMechanicReportReceived: (r) async {},
          getGarageData: () async =>
              (vehicles: <VehicleProfile>[], activeVehicleId: ''),
          onGarageDataReceived: (vehicles, activeId) async {
            headunitReceivedGarage = vehicles;
            headunitActiveVehicleId = activeId;
          },
        ),
      );

      phoneService.registerDelegate(
        SyncDataDelegate(
          getLocalTrips: () async => [],
          getTimeseriesLines: (id) async => [],
          onTripReceived: (t, lines) async {},
          onTripsAcked: (st, sts) async {},
          getParkedSnapshot: () async => null,
          onParkedSnapshotReceived: (s) async {},
          getMechanicReport: () async => null,
          onMechanicReportReceived: (r) async {},
          getGarageData: () async => (
            vehicles: [car1, car2],
            activeVehicleId: car2.id,
          ),
          onGarageDataReceived: (v, a) async {},
        ),
      );

      await headunitService.attachTransport(pair.headunitTransport);
      await phoneService.attachTransport(pair.phoneTransport);

      await phoneService.startSyncSession();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(headunitReceivedGarage, isNotNull);
      expect(headunitReceivedGarage!.length, equals(2));
      expect(headunitReceivedGarage!.map((c) => c.id),
          containsAll([car1.id, car2.id]));
      expect(headunitActiveVehicleId, equals(car2.id));

      await headunitService.dispose();
      await phoneService.dispose();
      await pair.close();
    });
  });
}
