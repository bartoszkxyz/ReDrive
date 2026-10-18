import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/models/trip.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/obd/models/obd_data.dart';
import 'package:redrive/services/trip/trip_timeseries_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory exportTempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('redrive_timeseries_test_');
    exportTempDir =
        Directory.systemTemp.createTempSync('redrive_exports_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    try {
      if (exportTempDir.existsSync()) {
        exportTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  ObdData createFullFidelityObdData({
    int rpm = 3250,
    int speed = 84,
    int coolantTemp = 92,
    int intakeAirTemp = 28,
    double voltage = 14.15,
    double engineLoad = 58.4,
    double throttlePosition = 36.2,
    double relativeThrottle = 27.8,
    double maf = 18.75,
    double engineFuelRate = 4.82,
    double instantFuelLPerHour = 4.82,
    double instantFuelL100km = 5.74,
    double shortTermFuelTrim = 2.34,
    double longTermFuelTrim = -1.56,
    double timingAdvance = 22.5,
    double manifoldPressure = 78.0,
    double fuelLevelPercent = 64.5,
    FuelSystemStatus fuelSystemStatus = FuelSystemStatus.closedLoop,
    double horsepower = 68.2,
    double torqueNm = 112.5,
    double accelerationG = 0.18,
    bool isDfcoActive = false,
    double remainingFuelLiters = 29.0,
    double estimatedRangeKm = 505.0,
  }) {
    return ObdData(
      rpm: rpm,
      speed: speed,
      coolantTemp: coolantTemp,
      intakeAirTemp: intakeAirTemp,
      voltage: voltage,
      engineLoad: engineLoad,
      throttlePosition: throttlePosition,
      relativeThrottle: relativeThrottle,
      maf: maf,
      engineFuelRate: engineFuelRate,
      instantFuelLPerHour: instantFuelLPerHour,
      instantFuelL100km: instantFuelL100km,
      shortTermFuelTrim: shortTermFuelTrim,
      longTermFuelTrim: longTermFuelTrim,
      timingAdvance: timingAdvance,
      manifoldPressure: manifoldPressure,
      fuelLevelPercent: fuelLevelPercent,
      fuelSystemStatus: fuelSystemStatus,
      horsepower: horsepower,
      torqueNm: torqueNm,
      accelerationG: accelerationG,
      isDfcoActive: isDfcoActive,
      remainingFuelLiters: remainingFuelLiters,
      estimatedRangeKm: estimatedRangeKm,
    );
  }

  Trip createTestTrip({
    required String id,
    DateTime? startTime,
    DateTime? endTime,
    List<TripAnomalyEpisode> anomalies = const [],
    List<String> recordedDtcs = const [],
  }) {
    final start = startTime ?? DateTime(2026, 10, 17, 10, 0, 0);
    final end = endTime ?? start.add(const Duration(minutes: 20));
    return Trip(
      id: id,
      startTime: start,
      endTime: end,
      duration: end.difference(start),
      distanceKm: 15.2,
      fuelConsumedLiters: 1.1,
      avgFuelConsumption: 7.2,
      avgSpeed: 45.6,
      maxSpeed: 88.0,
      maxRpm: 3500,
      avgRpm: 2100,
      anomalies: anomalies,
      recordedDtcs: recordedDtcs,
      hasTimeseries: true,
    );
  }

  group('Requirement 1: Recording, Flush & ReadSamples Field Fidelity', () {
    test(
      'round-trip preserves all ObdData fields, activeProblems, and activeSuspicions with full fidelity',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
        );

        final startTime = DateTime(2026, 10, 17, 10, 0, 0);
        final sampleTime1 = startTime.add(const Duration(seconds: 2));
        final sampleTime2 = startTime.add(const Duration(seconds: 5));

        final obd1 = createFullFidelityObdData(
          rpm: 3250,
          speed: 84,
          coolantTemp: 92,
          intakeAirTemp: 28,
          voltage: 14.15,
          engineLoad: 58.4,
          throttlePosition: 36.2,
          relativeThrottle: 27.8,
          maf: 18.75,
          engineFuelRate: 4.82,
          instantFuelLPerHour: 4.82,
          instantFuelL100km: 5.74,
          shortTermFuelTrim: 2.34,
          longTermFuelTrim: -1.56,
          timingAdvance: 22.5,
          manifoldPressure: 78.0,
          fuelLevelPercent: 64.5,
          fuelSystemStatus: FuelSystemStatus.closedLoop,
          horsepower: 68.2,
          torqueNm: 112.5,
          accelerationG: 0.18,
          isDfcoActive: false,
          remainingFuelLiters: 29.0,
          estimatedRangeKm: 505.0,
        );

        final obd2 = createFullFidelityObdData(
          rpm: 4100,
          speed: 102,
          coolantTemp: 95,
          intakeAirTemp: 32,
          voltage: 13.95,
          engineLoad: 72.1,
          throttlePosition: 48.5,
          relativeThrottle: 39.2,
          maf: 26.40,
          engineFuelRate: 6.95,
          instantFuelLPerHour: 6.95,
          instantFuelL100km: 6.81,
          shortTermFuelTrim: -3.12,
          longTermFuelTrim: 1.85,
          timingAdvance: 18.0,
          manifoldPressure: 92.0,
          fuelLevelPercent: 64.2,
          fuelSystemStatus: FuelSystemStatus.openLoopLoadOrDecel,
          horsepower: 88.5,
          torqueNm: 142.0,
          accelerationG: 0.35,
          isDfcoActive: true,
          remainingFuelLiters: 28.8,
          estimatedRangeKm: 501.0,
        );

        await service.startRecording('trip_fidelity_01', startTime);
        expect(service.activeTripId, equals('trip_fidelity_01'));
        expect(service.bufferedSampleCount, equals(0));

        service.recordSample(
          obd1,
          timestamp: sampleTime1,
          activeProblems: ['powerLossHighRpm'],
          activeSuspicions: ['vacuumLeakMap'],
        );
        expect(service.bufferedSampleCount, equals(1));

        service.recordSample(
          obd2,
          timestamp: sampleTime2,
          activeProblems: ['fuelTrimLean', 'dtcConfirmed'],
          activeSuspicions: ['timingRetardLoad'],
        );
        expect(service.bufferedSampleCount, equals(2));

        await service.flush();
        expect(service.bufferedSampleCount, equals(0));

        final samples = await service.readSamples('trip_fidelity_01');
        expect(samples.length, equals(2));

        // Verify Sample 1
        final read1 = samples[0];
        expect(read1.timestamp.isAtSameMomentAs(sampleTime1), isTrue);
        expect(read1.elapsedSeconds, closeTo(2.0, 1e-4));
        expect(read1.activeProblems, equals(['powerLossHighRpm']));
        expect(read1.activeSuspicions, equals(['vacuumLeakMap']));

        expect(read1.data.rpm, equals(3250));
        expect(read1.data.speed, equals(84));
        expect(read1.data.coolantTemp, equals(92));
        expect(read1.data.intakeAirTemp, equals(28));
        expect(read1.data.voltage, closeTo(14.15, 1e-4));
        expect(read1.data.engineLoad, closeTo(58.4, 1e-4));
        expect(read1.data.throttlePosition, closeTo(36.2, 1e-4));
        expect(read1.data.relativeThrottle, closeTo(27.8, 1e-4));
        expect(read1.data.maf, closeTo(18.75, 1e-4));
        expect(read1.data.engineFuelRate, closeTo(4.82, 1e-4));
        expect(read1.data.instantFuelLPerHour, closeTo(4.82, 1e-4));
        expect(read1.data.instantFuelL100km, closeTo(5.74, 1e-4));
        expect(read1.data.shortTermFuelTrim, closeTo(2.34, 1e-4));
        expect(read1.data.longTermFuelTrim, closeTo(-1.56, 1e-4));
        expect(read1.data.timingAdvance, closeTo(22.5, 1e-4));
        expect(read1.data.manifoldPressure, closeTo(78.0, 1e-4));
        expect(read1.data.fuelLevelPercent, closeTo(64.5, 1e-4));
        expect(read1.data.fuelSystemStatus, equals(FuelSystemStatus.closedLoop));
        expect(read1.data.horsepower, closeTo(68.2, 1e-4));
        expect(read1.data.torqueNm, closeTo(112.5, 1e-4));
        expect(read1.data.accelerationG, closeTo(0.18, 1e-4));
        expect(read1.data.isDfcoActive, isFalse);
        expect(read1.data.remainingFuelLiters, closeTo(29.0, 1e-4));
        expect(read1.data.estimatedRangeKm, closeTo(505.0, 1e-4));

        // Verify Sample 2
        final read2 = samples[1];
        expect(read2.timestamp.isAtSameMomentAs(sampleTime2), isTrue);
        expect(read2.elapsedSeconds, closeTo(5.0, 1e-4));
        expect(
          read2.activeProblems,
          equals(['fuelTrimLean', 'dtcConfirmed']),
        );
        expect(read2.activeSuspicions, equals(['timingRetardLoad']));

        expect(read2.data.rpm, equals(4100));
        expect(read2.data.speed, equals(102));
        expect(read2.data.coolantTemp, equals(95));
        expect(read2.data.intakeAirTemp, equals(32));
        expect(read2.data.voltage, closeTo(13.95, 1e-4));
        expect(read2.data.engineLoad, closeTo(72.1, 1e-4));
        expect(read2.data.throttlePosition, closeTo(48.5, 1e-4));
        expect(read2.data.relativeThrottle, closeTo(39.2, 1e-4));
        expect(read2.data.maf, closeTo(26.40, 1e-4));
        expect(read2.data.engineFuelRate, closeTo(6.95, 1e-4));
        expect(read2.data.shortTermFuelTrim, closeTo(-3.12, 1e-4));
        expect(read2.data.longTermFuelTrim, closeTo(1.85, 1e-4));
        expect(read2.data.timingAdvance, closeTo(18.0, 1e-4));
        expect(read2.data.manifoldPressure, closeTo(92.0, 1e-4));
        expect(read2.data.fuelLevelPercent, closeTo(64.2, 1e-4));
        expect(
          read2.data.fuelSystemStatus,
          equals(FuelSystemStatus.openLoopLoadOrDecel),
        );
        expect(read2.data.horsepower, closeTo(88.5, 1e-4));
        expect(read2.data.torqueNm, closeTo(142.0, 1e-4));
        expect(read2.data.accelerationG, closeTo(0.35, 1e-4));
        expect(read2.data.isDfcoActive, isTrue);

        // Verify TripTimeseriesSample value equality operator
        expect(read1, equals(read1));
        expect(read2, equals(read2));
        expect(read1, isNot(equals(read2)));
      },
    );
  });

  group('Requirement 2: Crash Recovery & Partial/Corrupted Line Tolerance', () {
    test(
      'gracefully skips malformed or partially truncated trailing lines without losing earlier valid lines',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
        );

        final sample1 = TripTimeseriesSample(
          timestamp: DateTime(2026, 10, 17, 11, 0, 0),
          elapsedSeconds: 0.0,
          data: createFullFidelityObdData(rpm: 2000, speed: 40),
          activeProblems: const [],
          activeSuspicions: const [],
        );

        final sample2 = TripTimeseriesSample(
          timestamp: DateTime(2026, 10, 17, 11, 0, 1),
          elapsedSeconds: 1.0,
          data: createFullFidelityObdData(rpm: 2500, speed: 50),
          activeProblems: const ['suspicion_temp'],
          activeSuspicions: const [],
        );

        // Prepare timeseries directory and file manually simulating an unexpected crash
        final timeseriesDir = Directory('${tempDir.path}/timeseries');
        if (!timeseriesDir.existsSync()) {
          timeseriesDir.createSync(recursive: true);
        }
        final tripFile = File('${timeseriesDir.path}/trip_crash_test.jsonl');

        final lines = [
          jsonEncode(sample1.toJson()),
          jsonEncode(sample2.toJson()),
          // Truncated line representing mid-write OS kill / power loss
          '{"timestamp":"2026-10-17T11:00:02.000Z","elapsedSeconds":2.0,"rpm":3000,"speed":60,"coolant',
        ];

        tripFile.writeAsStringSync('${lines.join('\n')}\n', flush: true);

        final recoveredSamples = await service.readSamples('crash_test');
        expect(recoveredSamples.length, equals(2));
        expect(recoveredSamples[0].data.rpm, equals(2000));
        expect(recoveredSamples[1].data.rpm, equals(2500));
        expect(
          recoveredSamples[1].activeProblems,
          equals(['suspicion_temp']),
        );
      },
    );

    test(
      'gracefully handles blank lines, whitespace, and non-JSON corruption between valid records',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
        );

        final sample1 = TripTimeseriesSample(
          timestamp: DateTime(2026, 10, 17, 11, 10, 0),
          elapsedSeconds: 0.0,
          data: createFullFidelityObdData(rpm: 1500, speed: 30),
        );

        final sample2 = TripTimeseriesSample(
          timestamp: DateTime(2026, 10, 17, 11, 10, 2),
          elapsedSeconds: 2.0,
          data: createFullFidelityObdData(rpm: 3000, speed: 65),
        );

        final timeseriesDir = Directory('${tempDir.path}/timeseries');
        if (!timeseriesDir.existsSync()) {
          timeseriesDir.createSync(recursive: true);
        }
        final tripFile = File('${timeseriesDir.path}/trip_corrupt_test.jsonl');

        final corruptedContent = '''
${jsonEncode(sample1.toJson())}

   
CORRUPTED_NON_JSON_DATA_BUFFER_GARBAGE!
${jsonEncode(sample2.toJson())}


''';

        tripFile.writeAsStringSync(corruptedContent, flush: true);

        final samples = await service.readSamples('corrupt_test');
        expect(samples.length, equals(2));
        expect(samples[0].data.rpm, equals(1500));
        expect(samples[1].data.rpm, equals(3000));
      },
    );
  });

  group('Requirement 3: 2-Trip Rolling Retention Policy', () {
    test(
      'keeps .jsonl files for the 2 newest completed trips and automatically deletes older .jsonl files',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
          maxRetainedTrips: 2,
        );

        // Record Trip 1 (oldest)
        await service.startRecording(
          'trip_01',
          DateTime(2026, 10, 17, 8, 0, 0),
        );
        service.recordSample(createFullFidelityObdData(rpm: 1800));
        final kept1 = await service.finishTrip('trip_01', keep: true);
        expect(kept1, isTrue);

        // Record Trip 2
        await service.startRecording(
          'trip_02',
          DateTime(2026, 10, 17, 9, 0, 0),
        );
        service.recordSample(createFullFidelityObdData(rpm: 2200));
        final kept2 = await service.finishTrip('trip_02', keep: true);
        expect(kept2, isTrue);

        // Record Trip 3 (newest)
        await service.startRecording(
          'trip_03',
          DateTime(2026, 10, 17, 10, 0, 0),
        );
        service.recordSample(createFullFidelityObdData(rpm: 2600));
        final kept3 = await service.finishTrip('trip_03', keep: true);
        expect(kept3, isTrue);

        // Prior to retention enforcement, all 3 trips have timeseries
        expect(await service.hasTimeseries('trip_01'), isTrue);
        expect(await service.hasTimeseries('trip_02'), isTrue);
        expect(await service.hasTimeseries('trip_03'), isTrue);

        // Enforce retention policy with newest-first ordering
        final retainedTripIds = await service.enforceRetentionPolicy(
          ['trip_03', 'trip_02', 'trip_01'],
        );

        // Expect trips 03 and 02 to be kept, trip 01 pruned
        expect(retainedTripIds, equals({'trip_03', 'trip_02'}));
        expect(await service.hasTimeseries('trip_03'), isTrue);
        expect(await service.hasTimeseries('trip_02'), isTrue);
        expect(await service.hasTimeseries('trip_01'), isFalse);

        final timeseriesDir = Directory('${tempDir.path}/timeseries');
        expect(
          File('${timeseriesDir.path}/trip_trip_01.jsonl').existsSync(),
          isFalse,
        );
        expect(
          File('${timeseriesDir.path}/trip_trip_02.jsonl').existsSync(),
          isTrue,
        );
        expect(
          File('${timeseriesDir.path}/trip_trip_03.jsonl').existsSync(),
          isTrue,
        );
      },
    );

    test(
      'finishTrip with keep: false deletes the raw timeseries file and returns false',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
        );

        await service.startRecording(
          'trip_discarded',
          DateTime(2026, 10, 17, 8, 30),
        );
        service.recordSample(createFullFidelityObdData(rpm: 1200));
        await service.flush();

        expect(await service.hasTimeseries('trip_discarded'), isTrue);

        final kept = await service.finishTrip('trip_discarded', keep: false);
        expect(kept, isFalse);
        expect(await service.hasTimeseries('trip_discarded'), isFalse);
      },
    );

    test('deleteTimeseries explicitly deletes the timeseries file', () async {
      final service = TripTimeseriesService(
        customDirectory: tempDir,
        customExportDirectory: exportTempDir,
      );

      await service.startRecording('trip_del', DateTime(2026, 10, 17, 9, 0));
      service.recordSample(createFullFidelityObdData(rpm: 1500));
      await service.finishTrip('trip_del', keep: true);

      expect(await service.hasTimeseries('trip_del'), isTrue);
      await service.deleteTimeseries('trip_del');
      expect(await service.hasTimeseries('trip_del'), isFalse);
    });
  });

  group('Requirement 4: Local CSV & JSON Export & Pruning Isolation', () {
    test(
      'exports CSV and JSON with exact header, calculated total_trim_pct, active_problems, and structured JSON',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
        );

        final tripId = 'trip_export_test';
        final startTime = DateTime(2026, 10, 17, 14, 0, 0);

        await service.startRecording(tripId, startTime);

        final obd1 = createFullFidelityObdData(
          rpm: 3200,
          speed: 75,
          engineLoad: 62.0,
          throttlePosition: 45.0,
          relativeThrottle: 35.0,
          maf: 22.5,
          manifoldPressure: 85.0,
          shortTermFuelTrim: 4.5,
          longTermFuelTrim: 2.5,
          timingAdvance: 15.0,
          coolantTemp: 90,
          intakeAirTemp: 26,
          voltage: 14.1,
          engineFuelRate: 5.2,
          fuelLevelPercent: 70.0,
          fuelSystemStatus: FuelSystemStatus.closedLoop,
          isDfcoActive: false,
        );

        final obd2 = createFullFidelityObdData(
          rpm: 4200,
          speed: 95,
          engineLoad: 80.0,
          throttlePosition: 60.0,
          relativeThrottle: 50.0,
          maf: 31.0,
          manifoldPressure: 98.0,
          shortTermFuelTrim: -1.2,
          longTermFuelTrim: -2.3,
          timingAdvance: 12.0,
          coolantTemp: 93,
          intakeAirTemp: 29,
          voltage: 13.9,
          engineFuelRate: 7.8,
          fuelLevelPercent: 69.5,
          fuelSystemStatus: FuelSystemStatus.openLoopLoadOrDecel,
          isDfcoActive: true,
        );

        service.recordSample(
          obd1,
          timestamp: startTime,
          activeProblems: ['powerLossHighRpm'],
          activeSuspicions: ['timingRetardLoad'],
        );

        service.recordSample(
          obd2,
          timestamp: startTime.add(const Duration(seconds: 4)),
          activeProblems: ['powerLossHighRpm', 'fuelTrimRich'],
          activeSuspicions: const [],
        );

        await service.finishTrip(tripId, keep: true);

        final anomalyEpisode = TripAnomalyEpisode(
          id: 'episode_001',
          severity: AnomalySeverity.problem,
          category: AnomalyCategory.powerLoss,
          title: 'Power Loss Episode',
          description: 'Load dropped under sustained high throttle',
          startTime: startTime,
          endTime: startTime.add(const Duration(seconds: 10)),
          peakMetrics: {'rpm': 3200, 'load': 62.0},
        );

        final trip = createTestTrip(
          id: tripId,
          startTime: startTime,
          endTime: startTime.add(const Duration(seconds: 10)),
          anomalies: [anomalyEpisode],
          recordedDtcs: ['P0171', 'P0300'],
        );

        final exportTimestamp = DateTime(2026, 10, 17, 14, 30, 45);
        final writtenFiles = await service.exportTripTimeseries(
          trip: trip,
          format: TimeseriesExportFormat.both,
          exportTime: exportTimestamp,
        );

        expect(writtenFiles.length, equals(2));
        final csvPath = writtenFiles.firstWhere((p) => p.endsWith('.csv'));
        final jsonPath = writtenFiles.firstWhere((p) => p.endsWith('.json'));

        expect(
          csvPath,
          endsWith('redrive_trip_${tripId}_20261017_143045.csv'),
        );
        expect(
          jsonPath,
          endsWith('redrive_trip_${tripId}_20261017_143045.json'),
        );

        // 1. Verify CSV contents
        final csvFile = File(csvPath);
        expect(csvFile.existsSync(), isTrue);
        final csvLines = await csvFile.readAsLines();

        // Exact header required by specification
        const expectedHeader =
            'timestamp_iso,elapsed_s,rpm,speed_kmh,engine_load_pct,throttle_raw_pct,throttle_rel_pct,maf_gps,map_kpa,stft_pct,ltft_pct,total_trim_pct,timing_adv_deg,coolant_c,iat_c,voltage_v,fuel_rate_lph,fuel_level_pct,fuel_system_status,is_dfco,active_problems,active_suspicions';
        expect(csvLines[0], equals(expectedHeader));

        // Sample 1 row verification
        final row1Fields = csvLines[1].split(',');
        expect(row1Fields.length, equals(22));
        expect(row1Fields[0], equals(startTime.toIso8601String()));
        expect(row1Fields[1], equals('0.0'));
        expect(row1Fields[2], equals('3200'));
        expect(row1Fields[3], equals('75'));
        expect(row1Fields[4], equals('62.0'));
        expect(row1Fields[9], equals('4.5')); // stft
        expect(row1Fields[10], equals('2.5')); // ltft
        expect(row1Fields[11], equals('7.0')); // total_trim_pct (4.5 + 2.5 = 7.0)
        expect(row1Fields[18], equals('closedLoop')); // fuel_system_status
        expect(row1Fields[19], equals('false')); // is_dfco
        expect(row1Fields[20], equals('powerLossHighRpm')); // active_problems
        expect(row1Fields[21], equals('timingRetardLoad')); // active_suspicions

        // Sample 2 row verification
        final row2Fields = csvLines[2].split(',');
        expect(row2Fields.length, equals(22));
        expect(row2Fields[1], equals('4.0'));
        expect(row2Fields[2], equals('4200'));
        expect(row2Fields[9], equals('-1.2'));
        expect(row2Fields[10], equals('-2.3'));
        expect(
          double.parse(row2Fields[11]),
          closeTo(-3.5, 1e-4),
        ); // total_trim_pct (-1.2 + -2.3 = -3.5)
        expect(row2Fields[18], equals('openLoopLoadOrDecel'));
        expect(row2Fields[19], equals('true'));
        expect(row2Fields[20], equals('powerLossHighRpm;fuelTrimRich'));
        expect(row2Fields[21], equals(''));

        // 2. Verify JSON contents
        final jsonFile = File(jsonPath);
        expect(jsonFile.existsSync(), isTrue);
        final decodedJson =
            jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;

        expect(decodedJson['trip']['id'], equals(tripId));
        expect(decodedJson['trip']['distanceKm'], equals(15.2));

        final anomalies = decodedJson['anomalies'] as List;
        expect(anomalies.length, equals(1));
        expect(anomalies[0]['title'], equals('Power Loss Episode'));
        expect(anomalies[0]['severity'], equals('problem'));
        expect(anomalies[0]['category'], equals('powerLoss'));

        expect(decodedJson['recordedDtcs'], equals(['P0171', 'P0300']));
        expect(decodedJson['sampleCount'], equals(2));

        final jsonSamples = decodedJson['samples'] as List;
        expect(jsonSamples.length, equals(2));
        expect(jsonSamples[0]['rpm'], equals(3200));
        expect(jsonSamples[0]['activeProblems'], equals(['powerLossHighRpm']));
        expect(
          jsonSamples[1]['activeProblems'],
          equals(['powerLossHighRpm', 'fuelTrimRich']),
        );
      },
    );

    test(
      'exported CSV/JSON files remain permanently untouched when retention policy prunes raw .jsonl files',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
          maxRetainedTrips: 2,
        );

        // 1. Record Trip 1 and Export it
        await service.startRecording(
          'trip_prune_1',
          DateTime(2026, 10, 17, 8, 0),
        );
        service.recordSample(createFullFidelityObdData(rpm: 2000));
        await service.finishTrip('trip_prune_1', keep: true);

        final trip1 = createTestTrip(id: 'trip_prune_1');
        final exported = await service.exportTripTimeseries(
          trip: trip1,
          format: TimeseriesExportFormat.both,
          exportTime: DateTime(2026, 10, 17, 8, 30, 0),
        );
        expect(exported.length, equals(2));
        final csvExportFile = File(exported[0]);
        final jsonExportFile = File(exported[1]);
        expect(csvExportFile.existsSync(), isTrue);
        expect(jsonExportFile.existsSync(), isTrue);

        // 2. Record Trip 2 and Trip 3
        await service.startRecording(
          'trip_prune_2',
          DateTime(2026, 10, 17, 9, 0),
        );
        service.recordSample(createFullFidelityObdData(rpm: 2100));
        await service.finishTrip('trip_prune_2', keep: true);

        await service.startRecording(
          'trip_prune_3',
          DateTime(2026, 10, 17, 10, 0),
        );
        service.recordSample(createFullFidelityObdData(rpm: 2200));
        await service.finishTrip('trip_prune_3', keep: true);

        // 3. Enforce 2-trip retention (keeps 3 and 2, prunes raw .jsonl for 1)
        final retained = await service.enforceRetentionPolicy(
          ['trip_prune_3', 'trip_prune_2', 'trip_prune_1'],
        );
        expect(retained, equals({'trip_prune_3', 'trip_prune_2'}));

        // Raw .jsonl for trip 1 must be pruned
        expect(await service.hasTimeseries('trip_prune_1'), isFalse);

        // Exported files for trip 1 MUST STILL EXIST intact
        expect(csvExportFile.existsSync(), isTrue);
        expect(jsonExportFile.existsSync(), isTrue);
        expect(csvExportFile.lengthSync(), greaterThan(0));
        expect(jsonExportFile.lengthSync(), greaterThan(0));
      },
    );

    test('exportTripTimeseries throws StateError when no samples exist', () {
      final service = TripTimeseriesService(
        customDirectory: tempDir,
        customExportDirectory: exportTempDir,
      );
      final emptyTrip = createTestTrip(id: 'empty_trip');

      expect(
        () => service.exportTripTimeseries(trip: emptyTrip),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'exportTripTimeseries respects csv-only and json-only formats',
      () async {
        final service = TripTimeseriesService(
          customDirectory: tempDir,
          customExportDirectory: exportTempDir,
        );

        await service.startRecording('trip_formats', DateTime(2026, 10, 17, 12));
        service.recordSample(createFullFidelityObdData(rpm: 1900));
        await service.finishTrip('trip_formats', keep: true);

        final trip = createTestTrip(id: 'trip_formats');

        // CSV only
        final csvOnly = await service.exportTripTimeseries(
          trip: trip,
          format: TimeseriesExportFormat.csv,
          exportTime: DateTime(2026, 10, 17, 12, 10),
        );
        expect(csvOnly.length, equals(1));
        expect(csvOnly.first.endsWith('.csv'), isTrue);

        // JSON only
        final jsonOnly = await service.exportTripTimeseries(
          trip: trip,
          format: TimeseriesExportFormat.json,
          exportTime: DateTime(2026, 10, 17, 12, 15),
        );
        expect(jsonOnly.length, equals(1));
        expect(jsonOnly.first.endsWith('.json'), isTrue);
      },
    );
  });
}
