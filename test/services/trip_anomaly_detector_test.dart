import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/obd/models/obd_data.dart';
import 'package:obdrive/services/trip/trip_anomaly_detector.dart';

void main() {
  group('TripAnomalyDetector', () {
    late TripAnomalyDetector detector;
    final t0 = DateTime(2026, 10, 17, 12, 0, 0);

    setUp(() {
      detector = TripAnomalyDetector();
    });

    test('healthy telemetry produces 0 problems and 0 suspicions', () {
      detector.evaluateSample(
        const ObdData(
          rpm: 2200,
          speed: 70,
          coolantTemp: 89,
          voltage: 14.1,
          engineLoad: 48.0,
          throttlePosition: 32.0,
          relativeThrottle: 26.4,
          shortTermFuelTrim: 2.3,
          longTermFuelTrim: -1.5,
          timingAdvance: 18.0,
          manifoldPressure: 52.0,
          fuelSystemStatus: FuelSystemStatus.closedLoop,
        ),
        timestamp: t0,
      );

      expect(detector.problemCount, 0);
      expect(detector.suspicionCount, 0);
      expect(detector.episodes, isEmpty);
    });

    test('detects coolant suspicion (99-104°C) and upgrades to problem (>104°C) within merge window', () {
      detector.evaluateSample(
        const ObdData(rpm: 2000, speed: 50, coolantTemp: 101),
        timestamp: t0,
      );
      expect(detector.suspicionCount, 1);
      expect(detector.problemCount, 0);

      // 4 seconds later, coolant rises to 106°C -> merges and upgrades to problem
      final upgraded = detector.evaluateSample(
        const ObdData(rpm: 2000, speed: 50, coolantTemp: 106),
        timestamp: t0.add(const Duration(seconds: 4)),
      );
      expect(upgraded, isTrue);
      expect(detector.suspicionCount, 0);
      expect(detector.problemCount, 1);
      expect(detector.episodes.single.category, AnomalyCategory.thermal);
      expect(detector.episodes.single.peakMetrics['coolantTemp'], 106);
    });

    test('detects high-RPM / high-load power loss (airflow shortfall + fuel starvation + timing retard)', () {
      // Sample 1: Single-cycle high-load shortfall -> suspicion
      detector.evaluateSample(
        const ObdData(
          rpm: 3600,
          speed: 80,
          relativeThrottle: 65.0,
          engineLoad: 34.0,
          maf: 11.5,
          shortTermFuelTrim: 14.0,
          longTermFuelTrim: 6.0, // total trim +20% -> fuel starvation problem
          coolantTemp: 90,
          timingAdvance: 12.0,
        ),
        timestamp: t0,
      );

      // Load shortfall is suspicion on cycle 1, STFT 14% is suspicion, fuel starvation is problem immediately
      expect(detector.suspicionCount, 2);
      expect(detector.problemCount, 1);

      // Sample 2 (500ms later): Second consecutive cycle of high-load shortfall -> upgrades load episode to problem
      detector.evaluateSample(
        const ObdData(
          rpm: 3700,
          speed: 82,
          relativeThrottle: 68.0,
          engineLoad: 32.0,
          maf: 11.0,
          shortTermFuelTrim: 15.5,
          longTermFuelTrim: 6.0,
          coolantTemp: 90,
          timingAdvance: -1.5, // Negative timing under load -> problem
        ),
        timestamp: t0.add(const Duration(milliseconds: 500)),
      );

      expect(detector.suspicionCount, 0);
      // 1) power_loss_high_load (upgraded), 2) power_loss_fuel_trim, 3) fuel_trim_single (STFT 15.5%), 4) power_loss_timing_retard
      expect(detector.problemCount, greaterThanOrEqualTo(3));
      expect(detector.activeProblems, contains('HIGH_RPM_POWER_LOSS'));
      expect(detector.activeProblems, contains('HIGH_LOAD_FUEL_STARVATION'));
    });

    test('debounces contiguous anomalies within 10s window and splits episodes >10s apart', () {
      for (int i = 0; i < 6; i++) {
        detector.evaluateSample(
          const ObdData(rpm: 2000, speed: 60, shortTermFuelTrim: 18.0),
          timestamp: t0.add(Duration(seconds: i * 2)),
        );
      }
      // All 6 samples are spaced by 2s (<= 10s merge window) -> 1 episode
      expect(detector.problemCount, 1);
      expect(
        detector.episodes.single.duration,
        const Duration(seconds: 10),
      );

      // 15 seconds after the last sample, another STFT spike occurs -> 2nd episode
      detector.evaluateSample(
        const ObdData(rpm: 2000, speed: 60, shortTermFuelTrim: 19.5),
        timestamp: t0.add(const Duration(seconds: 25)),
      );
      expect(detector.problemCount, 2);
    });

    test('records Mode 03 confirmed DTC as problem and baseline Mode 07 pending DTC as suspicion', () {
      detector.recordDtcs(
        const [
          DtcCode(
            code: 'P0420',
            system: 'Powertrain',
            title: 'Catalyst System Efficiency Below Threshold',
            description: 'Bank 1 catalyst efficiency low',
            isPending: true,
          ),
          DtcCode(
            code: 'P0171',
            system: 'Powertrain',
            title: 'System Too Lean (Bank 1)',
            description: 'Fuel system lean',
            isPending: false,
          ),
        ],
        timestamp: t0,
        isTripStart: true,
      );

      expect(detector.suspicionCount, 1);
      expect(detector.problemCount, 1);
      expect(detector.recordedDtcs, containsAll(['P0420', 'P0171']));
    });
  });
}
