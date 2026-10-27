import 'dart:math' as math;

import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/models/trip_anomaly.dart';
import 'package:obdrive/models/vehicle_profile.dart';
import 'package:obdrive/obd/models/obd_data.dart';

/// Evaluates real-time [ObdData] telemetry and [DtcCode] scans against
/// Suzuki Swift 3 (M15A 1.5L) single-metric and composite high-load power-loss
/// rules, debouncing contiguous breaches into [TripAnomalyEpisode] items.
class TripAnomalyDetector {
  /// Merge window for contiguous or closely spaced breaches of the same rule.
  final Duration episodeMergeWindow;

  VehicleProfile _vehicleProfile = VehicleProfile.defaultSuzukiSwiftM15A();
  VehicleProfile get vehicleProfile => _vehicleProfile;

  void applyVehicleProfile(VehicleProfile profile) {
    _vehicleProfile = profile;
  }

  final List<TripAnomalyEpisode> _episodes = [];
  final Set<String> _recordedDtcs = {};
  final Set<String> _baselinePendingDtcs = {};

  final List<String> _activeProblems = [];
  final List<String> _activeSuspicions = [];

  // Consecutive sample counters for multi-cycle confirmation
  int _consecutiveHighLoadShortfall = 0;
  int _consecutiveTimingRetardUnderLoad = 0;
  int _episodeCounter = 0;

  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastElapsedSeconds;

  // Maps ruleKey -> index in _episodes for active/recent episode merging
  final Map<String, int> _lastEpisodeIndexByRule = {};

  TripAnomalyDetector({
    this.episodeMergeWindow = const Duration(seconds: 10),
  });

  List<TripAnomalyEpisode> get episodes => List.unmodifiable(_episodes);

  int get problemCount =>
      _episodes.where((e) => e.severity == AnomalySeverity.problem).length;

  int get suspicionCount =>
      _episodes.where((e) => e.severity == AnomalySeverity.suspicion).length;

  List<String> get recordedDtcs => List.unmodifiable(_recordedDtcs);

  /// Active problem codes/labels triggered on the most recently evaluated sample.
  List<String> get activeProblems => List.unmodifiable(_activeProblems);

  /// Active suspicion codes/labels triggered on the most recently evaluated sample.
  List<String> get activeSuspicions => List.unmodifiable(_activeSuspicions);

  void reset() {
    _episodes.clear();
    _recordedDtcs.clear();
    _baselinePendingDtcs.clear();
    _activeProblems.clear();
    _activeSuspicions.clear();
    _consecutiveHighLoadShortfall = 0;
    _consecutiveTimingRetardUnderLoad = 0;
    _episodeCounter = 0;
    _lastLatitude = null;
    _lastLongitude = null;
    _lastElapsedSeconds = null;
    _lastEpisodeIndexByRule.clear();
  }

  /// Evaluates a single [ObdData] sample at [timestamp].
  /// Returns `true` if a new [AnomalySeverity.problem] episode was created or
  /// upgraded from a suspicion on this sample.
  bool evaluateSample(
    ObdData data, {
    required DateTime timestamp,
    double? latitude,
    double? longitude,
    double? elapsedSeconds,
  }) {
    _activeProblems.clear();
    _activeSuspicions.clear();
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastElapsedSeconds = elapsedSeconds;
    var triggeredNewProblem = false;

    final idleBase = _vehicleProfile.idleThrottleBaselinePercent;
    final wotBase = _vehicleProfile.wotThrottleBaselinePercent > idleBase
        ? _vehicleProfile.wotThrottleBaselinePercent
        : 85.0;
    final effectiveRelThrottle = data.relativeThrottle > 0
        ? data.relativeThrottle
        : (data.throttlePosition > idleBase
            ? ((data.throttlePosition - idleBase) / (wotBase - idleBase) * 100.0)
                .clamp(0.0, 100.0)
            : 0.0);

    final baseMetrics = <String, num>{
      'rpm': data.rpm,
      'speed': data.speed,
      'engineLoad': data.engineLoad,
      'throttlePosition': data.throttlePosition,
      'relativeThrottle': double.parse(effectiveRelThrottle.toStringAsFixed(1)),
      'maf': data.maf,
      'manifoldPressure': data.manifoldPressure,
      'shortTermFuelTrim': data.shortTermFuelTrim,
      'longTermFuelTrim': data.longTermFuelTrim,
      'timingAdvance': data.timingAdvance,
      'coolantTemp': data.coolantTemp,
      'voltage': data.voltage,
    };

    // -------------------------------------------------------------------------
    // 1. Single-Metric Dashboard Thresholds
    // -------------------------------------------------------------------------

    // 1a. Coolant Temperature (M15A default overheat=102°C -> problem >104°C, suspicion >=99°C)
    final criticalCoolantC = _vehicleProfile.coolantOverheatTempC + 2;
    final warningCoolantC = _vehicleProfile.coolantOverheatTempC - 3;
    if (data.coolantTemp > criticalCoolantC) {
      _activeProblems.add('COOLANT_OVERHEAT');
      if (_recordOrMergeEpisode(
        ruleKey: 'thermal_coolant',
        severity: AnomalySeverity.problem,
        category: AnomalyCategory.thermal,
        title: 'Engine Overheating (${data.coolantTemp}°C)',
        description:
            'Coolant temperature exceeded critical threshold (>$criticalCoolantC°C). Peak: ${data.coolantTemp}°C.',
        timestamp: timestamp,
        metrics: baseMetrics,
      )) {
        triggeredNewProblem = true;
      }
    } else if (data.coolantTemp >= warningCoolantC) {
      _activeSuspicions.add('COOLANT_HIGH');
      _recordOrMergeEpisode(
        ruleKey: 'thermal_coolant',
        severity: AnomalySeverity.suspicion,
        category: AnomalyCategory.thermal,
        title: 'Elevated Coolant Temp (${data.coolantTemp}°C)',
        description:
            'Coolant temperature entered warning range ($warningCoolantC–$criticalCoolantC°C). Peak: ${data.coolantTemp}°C.',
        timestamp: timestamp,
        metrics: baseMetrics,
      );
    }

    // 1b. Adapter / Battery Voltage (only evaluate when voltage sensor is active > 1.0V)
    if (data.voltage > 1.0) {
      if (data.voltage < 11.8 || data.voltage >= 15.4) {
        _activeProblems.add('VOLTAGE_CRITICAL');
        if (_recordOrMergeEpisode(
          ruleKey: 'electrical_voltage',
          severity: AnomalySeverity.problem,
          category: AnomalyCategory.electrical,
          title:
              'Charging System Fault (${data.voltage.toStringAsFixed(1)}V)',
          description: data.voltage < 11.8
              ? 'Battery/alternator voltage dropped below 11.8V (${data.voltage.toStringAsFixed(1)}V).'
              : 'Alternator over-voltage detected (>=15.4V: ${data.voltage.toStringAsFixed(1)}V).',
          timestamp: timestamp,
          metrics: baseMetrics,
        )) {
          triggeredNewProblem = true;
        }
      } else if (data.rpm >= 600 &&
          (data.voltage < 12.8 || data.voltage >= 15.0)) {
        _activeSuspicions.add('VOLTAGE_ABNORMAL');
        _recordOrMergeEpisode(
          ruleKey: 'electrical_voltage',
          severity: AnomalySeverity.suspicion,
          category: AnomalyCategory.electrical,
          title:
              'Abnormal Charging Voltage (${data.voltage.toStringAsFixed(1)}V)',
          description:
              'Running charging voltage outside optimal 12.8–14.9V range (${data.voltage.toStringAsFixed(1)}V).',
          timestamp: timestamp,
          metrics: baseMetrics,
        );
      }
    }

    // 1c. Warm Idle Manifold Pressure / Vacuum Leak
    // Warm idle: RPM 600..950, Speed == 0, Rel Throttle < 5%, Coolant >= 75°C
    final isWarmIdle = data.rpm >= 600 &&
        data.rpm <= 950 &&
        data.speed == 0 &&
        effectiveRelThrottle < 5.0 &&
        data.coolantTemp >= 75;
    if (isWarmIdle && data.manifoldPressure > 0) {
      if (data.manifoldPressure >= 55.0) {
        _activeProblems.add('IDLE_VACUUM_FAULT');
        if (_recordOrMergeEpisode(
          ruleKey: 'vacuum_idle_map',
          severity: AnomalySeverity.problem,
          category: AnomalyCategory.vacuumIntake,
          title:
              'Severe Idle Vacuum Loss (${data.manifoldPressure.toStringAsFixed(0)} kPa)',
          description:
              'Warm idle manifold pressure >= 55 kPa indicates a likely intake vacuum leak or PCV fault.',
          timestamp: timestamp,
          metrics: baseMetrics,
        )) {
          triggeredNewProblem = true;
        }
      } else if (data.manifoldPressure >= 46.0) {
        _activeSuspicions.add('IDLE_VACUUM_WEAK');
        _recordOrMergeEpisode(
          ruleKey: 'vacuum_idle_map',
          severity: AnomalySeverity.suspicion,
          category: AnomalyCategory.vacuumIntake,
          title:
              'Elevated Idle MAP (${data.manifoldPressure.toStringAsFixed(0)} kPa)',
          description:
              'Warm idle manifold pressure is higher than normal M15A baseline (46–54 kPa vs normal 28–40 kPa).',
          timestamp: timestamp,
          metrics: baseMetrics,
        );
      }
    }

    // 1d. Fuel System Status Fault
    if (data.fuelSystemStatus == FuelSystemStatus.openLoopFault ||
        data.fuelSystemStatus == FuelSystemStatus.closedLoopFault) {
      _activeProblems.add('FUEL_SYSTEM_FAULT');
      if (_recordOrMergeEpisode(
        ruleKey: 'fuel_system_fault',
        severity: AnomalySeverity.problem,
        category: AnomalyCategory.fuelSystemFault,
        title: 'Fuel System Loop Fault (${data.fuelSystemStatus.shortCode})',
        description:
            'ECU reported ${data.fuelSystemStatus.label}. O2 sensor or fuel feedback control issue.',
        timestamp: timestamp,
        metrics: baseMetrics,
      )) {
        triggeredNewProblem = true;
      }
    }

    // 1e. Single-Metric STFT & LTFT Thresholds (when not in DFCO)
    if (!data.isDfcoActive) {
      final absStft = data.shortTermFuelTrim.abs();
      final absLtft = data.longTermFuelTrim.abs();

      if (absStft >= 15.0 || absLtft >= 15.0) {
        _activeProblems.add('FUEL_TRIM_EXTREME');
        final leanOrRich =
            (data.shortTermFuelTrim + data.longTermFuelTrim) >= 0
                ? 'Lean correction (+)'
                : 'Rich correction (-)';
        if (_recordOrMergeEpisode(
          ruleKey: 'fuel_trim_single',
          severity: AnomalySeverity.problem,
          category: AnomalyCategory.fuelTrim,
          title:
              'Excessive Fuel Trim (STFT ${data.shortTermFuelTrim.toStringAsFixed(1)}%, LTFT ${data.longTermFuelTrim.toStringAsFixed(1)}%)',
          description:
              '$leanOrRich exceeded ±15% threshold (STFT ${data.shortTermFuelTrim.toStringAsFixed(1)}%, LTFT ${data.longTermFuelTrim.toStringAsFixed(1)}%).',
          timestamp: timestamp,
          metrics: baseMetrics,
        )) {
          triggeredNewProblem = true;
        }
      } else if (absStft >= 10.0 || absLtft >= 10.0) {
        _activeSuspicions.add('FUEL_TRIM_ELEVATED');
        _recordOrMergeEpisode(
          ruleKey: 'fuel_trim_single',
          severity: AnomalySeverity.suspicion,
          category: AnomalyCategory.fuelTrim,
          title:
              'Elevated Fuel Trim (STFT ${data.shortTermFuelTrim.toStringAsFixed(1)}%, LTFT ${data.longTermFuelTrim.toStringAsFixed(1)}%)',
          description:
              'Fuel trim in ±10% to ±15% range (STFT ${data.shortTermFuelTrim.toStringAsFixed(1)}%, LTFT ${data.longTermFuelTrim.toStringAsFixed(1)}%).',
          timestamp: timestamp,
          metrics: baseMetrics,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 2. Composite High-RPM / High-Load Power-Loss Detector
    // -------------------------------------------------------------------------
    final isHighDemand =
        data.rpm >= 2800 && effectiveRelThrottle >= 45.0 && !data.isDfcoActive;

    if (isHighDemand) {
      // Expected M15A 1.5L MAF at high demand: approx (rpm / 1000) * 7.5 g/s
      final expectedMinMaf = (data.rpm / 1000.0) * 5.2;
      final hasMafShortfall = data.maf > 0.0 && data.maf < expectedMinMaf;

      // 2a. Load / Airflow Shortfall under high throttle & RPM
      if (data.engineLoad > 0.0 && data.engineLoad < 42.0 || hasMafShortfall) {
        _consecutiveHighLoadShortfall++;
        if (_consecutiveHighLoadShortfall >= 2) {
          _activeProblems.add('HIGH_RPM_POWER_LOSS');
          if (_recordOrMergeEpisode(
            ruleKey: 'power_loss_high_load',
            severity: AnomalySeverity.problem,
            category: AnomalyCategory.powerLoss,
            title:
                'High-RPM Power / Airflow Loss (${data.rpm} RPM, ${data.engineLoad.toStringAsFixed(0)}% Load)',
            description:
                'Sustained load/airflow shortfall under heavy throttle (${effectiveRelThrottle.toStringAsFixed(0)}% rel throttle, '
                'Load ${data.engineLoad.toStringAsFixed(1)}%, MAF ${data.maf.toStringAsFixed(1)} g/s).',
            timestamp: timestamp,
            metrics: baseMetrics,
          )) {
            triggeredNewProblem = true;
          }
        } else {
          _activeSuspicions.add('HIGH_RPM_LOAD_DIP');
          _recordOrMergeEpisode(
            ruleKey: 'power_loss_high_load',
            severity: AnomalySeverity.suspicion,
            category: AnomalyCategory.powerLoss,
            title:
                'Transient High-RPM Load Dip (${data.rpm} RPM, ${data.engineLoad.toStringAsFixed(0)}% Load)',
            description:
                'Brief load/airflow dip under high throttle demand (${effectiveRelThrottle.toStringAsFixed(0)}% rel throttle).',
            timestamp: timestamp,
            metrics: baseMetrics,
          );
        }
      } else if (data.engineLoad >= 42.0 && data.engineLoad <= 52.0) {
        _consecutiveHighLoadShortfall = 0;
        _activeSuspicions.add('HIGH_RPM_WEAK_LOAD');
        _recordOrMergeEpisode(
          ruleKey: 'power_loss_high_load',
          severity: AnomalySeverity.suspicion,
          category: AnomalyCategory.powerLoss,
          title:
              'Lower-Than-Expected Load at High RPM (${data.rpm} RPM, ${data.engineLoad.toStringAsFixed(0)}% Load)',
          description:
              'Engine load remained moderate (42–52%) despite high throttle (${effectiveRelThrottle.toStringAsFixed(0)}%) at ${data.rpm} RPM.',
          timestamp: timestamp,
          metrics: baseMetrics,
        );
      } else {
        _consecutiveHighLoadShortfall = 0;
      }

      // 2b. Fuel Delivery Starvation / Trim Surge Under High Load
      final totalTrim = data.shortTermFuelTrim + data.longTermFuelTrim;
      final absTotalTrim = totalTrim.abs();
      if (absTotalTrim >= 18.0 || data.shortTermFuelTrim.abs() >= 15.0) {
        _activeProblems.add('HIGH_LOAD_FUEL_STARVATION');
        if (_recordOrMergeEpisode(
          ruleKey: 'power_loss_fuel_trim',
          severity: AnomalySeverity.problem,
          category: AnomalyCategory.powerLoss,
          title:
              'High-Load Fuel Starvation / Trim Anomaly (Total ${totalTrim.toStringAsFixed(1)}%)',
          description:
              'Combined fuel trim (${totalTrim.toStringAsFixed(1)}%) or STFT (${data.shortTermFuelTrim.toStringAsFixed(1)}%) '
              'spiked at ${data.rpm} RPM under heavy throttle (${effectiveRelThrottle.toStringAsFixed(0)}%).',
          timestamp: timestamp,
          metrics: baseMetrics,
        )) {
          triggeredNewProblem = true;
        }
      } else if (absTotalTrim >= 13.0) {
        _activeSuspicions.add('HIGH_LOAD_TRIM_STRAIN');
        _recordOrMergeEpisode(
          ruleKey: 'power_loss_fuel_trim',
          severity: AnomalySeverity.suspicion,
          category: AnomalyCategory.powerLoss,
          title:
              'High-Load Fuel Trim Strain (Total ${totalTrim.toStringAsFixed(1)}%)',
          description:
              'Combined STFT+LTFT reached ${totalTrim.toStringAsFixed(1)}% under high RPM load (${data.rpm} RPM).',
          timestamp: timestamp,
          metrics: baseMetrics,
        );
      }

      // 2c. Knock / Timing Retard Under High Load (RPM >= 3000 & Load >= 60%)
      final hasTimingTelemetry = data.timingAdvance != 0.0 ||
          data.coolantTemp > 0 ||
          data.manifoldPressure > 0 ||
          data.voltage > 0;
      if (data.rpm >= 3000 &&
          data.engineLoad >= 60.0 &&
          hasTimingTelemetry &&
          data.timingAdvance < 4.0) {
        _consecutiveTimingRetardUnderLoad++;
        if (_consecutiveTimingRetardUnderLoad >= 3 ||
            data.timingAdvance < 0.0) {
          _activeProblems.add('HIGH_LOAD_TIMING_RETARD');
          if (_recordOrMergeEpisode(
            ruleKey: 'power_loss_timing_retard',
            severity: AnomalySeverity.problem,
            category: AnomalyCategory.powerLoss,
            title:
                'Heavy Ignition Timing Pull (${data.timingAdvance.toStringAsFixed(1)}° at ${data.rpm} RPM)',
            description:
                'Ignition timing retarded to ${data.timingAdvance.toStringAsFixed(1)}° under high load '
                '(${data.engineLoad.toStringAsFixed(0)}%), indicating possible knock or power loss.',
            timestamp: timestamp,
            metrics: baseMetrics,
          )) {
            triggeredNewProblem = true;
          }
        } else {
          _activeSuspicions.add('HIGH_LOAD_LOW_TIMING');
          _recordOrMergeEpisode(
            ruleKey: 'power_loss_timing_retard',
            severity: AnomalySeverity.suspicion,
            category: AnomalyCategory.powerLoss,
            title:
                'Low Ignition Timing Advance (${data.timingAdvance.toStringAsFixed(1)}° at ${data.rpm} RPM)',
            description:
                'Timing advance below 4.0° (${data.timingAdvance.toStringAsFixed(1)}°) at ${data.rpm} RPM and ${data.engineLoad.toStringAsFixed(0)}% load.',
            timestamp: timestamp,
            metrics: baseMetrics,
          );
        }
      } else {
        _consecutiveTimingRetardUnderLoad = 0;
      }
    } else {
      _consecutiveHighLoadShortfall = 0;
      _consecutiveTimingRetardUnderLoad = 0;
    }

    return triggeredNewProblem;
  }

  /// Records confirmed (Mode 03) and pending (Mode 07) DTCs scanned during a trip.
  /// - Confirmed DTC (Mode 03): recorded as [AnomalySeverity.problem].
  /// - Pending DTC (Mode 07): recorded as [AnomalySeverity.suspicion] if present at trip
  ///   start, or [AnomalySeverity.problem] if newly triggered mid-trip.
  void recordDtcs(
    List<DtcCode> dtcs, {
    required DateTime timestamp,
    bool isTripStart = false,
    double? latitude,
    double? longitude,
    double? elapsedSeconds,
  }) {
    final effLat = latitude ?? _lastLatitude;
    final effLon = longitude ?? _lastLongitude;
    final effElapsed = elapsedSeconds ?? _lastElapsedSeconds;
    for (final dtc in dtcs) {
      if (dtc.code.isEmpty) continue;
      final isAlreadyRecorded = _recordedDtcs.contains(dtc.code);
      _recordedDtcs.add(dtc.code);

      if (dtc.isPending && isTripStart) {
        _baselinePendingDtcs.add(dtc.code);
      }

      if (isAlreadyRecorded) continue;

      final severity = (!dtc.isPending || !_baselinePendingDtcs.contains(dtc.code))
          ? AnomalySeverity.problem
          : AnomalySeverity.suspicion;

      final label = dtc.isPending ? 'Pending DTC' : 'Confirmed DTC';
      _episodeCounter++;
      _episodes.add(
        TripAnomalyEpisode(
          id: 'dtc_${dtc.code}_$_episodeCounter',
          severity: severity,
          category: AnomalyCategory.dtcFault,
          title: '$label ${dtc.code}: ${dtc.title}',
          description: dtc.description,
          startTime: timestamp,
          endTime: timestamp,
          peakMetrics: const {},
          dtcCodes: [dtc.code],
          latitude: effLat,
          longitude: effLon,
          elapsedSeconds: effElapsed,
        ),
      );
    }
  }

  /// Creates a new episode or merges into an existing episode for [ruleKey] if
  /// the previous episode ended within [episodeMergeWindow].
  /// Returns `true` if a new [AnomalySeverity.problem] episode was created or upgraded.
  bool _recordOrMergeEpisode({
    required String ruleKey,
    required AnomalySeverity severity,
    required AnomalyCategory category,
    required String title,
    required String description,
    required DateTime timestamp,
    required Map<String, num> metrics,
  }) {
    final existingIdx = _lastEpisodeIndexByRule[ruleKey];
    if (existingIdx != null && existingIdx < _episodes.length) {
      final existing = _episodes[existingIdx];
      final gap = timestamp.difference(existing.endTime);
      if (!gap.isNegative && gap <= episodeMergeWindow) {
        final upgradedToProblem =
            existing.severity == AnomalySeverity.suspicion &&
                severity == AnomalySeverity.problem;
        final mergedSeverity =
            (existing.severity == AnomalySeverity.problem ||
                    severity == AnomalySeverity.problem)
                ? AnomalySeverity.problem
                : AnomalySeverity.suspicion;

        final mergedMetrics = Map<String, num>.from(existing.peakMetrics);
        for (final entry in metrics.entries) {
          final prev = mergedMetrics[entry.key];
          if (prev == null) {
            mergedMetrics[entry.key] = entry.value;
          } else if (entry.key == 'shortTermFuelTrim' ||
              entry.key == 'longTermFuelTrim') {
            if (entry.value.abs() > prev.abs()) {
              mergedMetrics[entry.key] = entry.value;
            }
          } else {
            mergedMetrics[entry.key] = math.max(prev, entry.value);
          }
        }

        _episodes[existingIdx] = existing.copyWith(
          severity: mergedSeverity,
          title: (upgradedToProblem || existing.severity == severity)
              ? title
              : existing.title,
          description: (upgradedToProblem || existing.severity == severity)
              ? description
              : existing.description,
          endTime: timestamp,
          peakMetrics: mergedMetrics,
          latitude: existing.latitude ?? _lastLatitude,
          longitude: existing.longitude ?? _lastLongitude,
          elapsedSeconds: existing.elapsedSeconds ?? _lastElapsedSeconds,
        );
        return upgradedToProblem;
      }
    }

    _episodeCounter++;
    final episode = TripAnomalyEpisode(
      id: '${ruleKey}_$_episodeCounter',
      severity: severity,
      category: category,
      title: title,
      description: description,
      startTime: timestamp,
      endTime: timestamp,
      peakMetrics: metrics,
      latitude: _lastLatitude,
      longitude: _lastLongitude,
      elapsedSeconds: _lastElapsedSeconds,
    );
    _episodes.add(episode);
    _lastEpisodeIndexByRule[ruleKey] = _episodes.length - 1;
    return severity == AnomalySeverity.problem;
  }
}
