import 'dart:async';
import 'dart:math';
import '../models/obd_data.dart';

class DemoDataGenerator {
  Timer? _timer;
  final _random = Random();
  int _currentSpeed = 45;
  int _currentRpm = 1800;

  void start(void Function(ObdData) onData) {
    stop();

    onData(_generateData());

    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      onData(_generateData());
    });
  }

  ObdData _generateData() {
    // Smooth speed transitions between 30 and 120 km/h
    final speedDelta = _random.nextInt(9) - 4; // -4 to +4 km/h
    _currentSpeed = (_currentSpeed + speedDelta).clamp(30, 130);

    // Realistic RPM correlating with speed
    _currentRpm = (800 + (_currentSpeed * 28) + _random.nextInt(200) - 100).clamp(800, 5500);

    final coolantTemp = 88 + _random.nextInt(6); // 88 to 93 °C
    final intakeAirTemp = 26 + _random.nextInt(5); // 26 to 30 °C
    final voltage = 14.1 + (_random.nextDouble() * 0.4); // 14.1 to 14.5 V
    final load = 22.0 + (_currentSpeed / 130.0) * 35.0 + (_random.nextDouble() * 10.0); // 22% - 67%
    final throttle = (load * 0.85).clamp(10.0, 95.0);

    // Instant fuel consumption (Suzuki Swift 3 M15A 1.5L displacement)
    final airGramsSec = (_currentRpm * 1.5 * (load / 100.0)) / 125.0;
    final fuelLPerH = (airGramsSec * 3600.0) / (14.7 * 820.0);
    final l100km = _currentSpeed > 0 ? (fuelLPerH / _currentSpeed) * 100.0 : 0.0;

    // Relative throttle & Derived power/torque
    final relThrottle = ((throttle - 13.0) / (85.0 - 13.0) * 100.0).clamp(0.0, 100.0);
    final hp = (airGramsSec * 1.25).clamp(0.0, 110.0);
    final kw = hp * 0.7457;
    final torque = _currentRpm > 500 ? ((kw * 9549.0) / _currentRpm).clamp(0.0, 145.0) : 0.0;
    final gForce = (speedDelta * (1000.0 / 3600.0) / 9.80665).clamp(-0.8, 0.8);

    // Category 2 sensors: trims, timing, MAP, fuel tank
    final stft = (_random.nextDouble() * 3.0) - 1.5; // -1.5% to +1.5%
    final ltft = 1.2 + (_random.nextDouble() * 1.0) - 0.5; // +0.7% to +1.7%
    final timing = (12.0 + (_currentRpm / 150.0)).clamp(8.0, 42.0);
    final mapKpa = (30.0 + (load * 0.55)).clamp(25.0, 100.0);
    const fuelPct = 68.5;
    const remainingLiters = (fuelPct / 100.0) * 45.0; // ~30.8 L
    final dte = l100km > 0 ? (remainingLiters / l100km) * 100.0 : 450.0;

    return ObdData(
      speed: _currentSpeed,
      rpm: _currentRpm,
      coolantTemp: coolantTemp,
      intakeAirTemp: intakeAirTemp,
      voltage: voltage,
      engineLoad: load,
      throttlePosition: throttle,
      relativeThrottle: relThrottle,
      maf: airGramsSec,
      engineFuelRate: fuelLPerH,
      instantFuelLPerHour: fuelLPerH,
      instantFuelL100km: l100km,
      shortTermFuelTrim: stft,
      longTermFuelTrim: ltft,
      timingAdvance: timing,
      manifoldPressure: mapKpa,
      fuelLevelPercent: fuelPct,
      fuelSystemStatus: FuelSystemStatus.closedLoop,
      horsepower: hp,
      torqueNm: torque,
      accelerationG: gForce,
      isDfcoActive: false,
      remainingFuelLiters: remainingLiters,
      estimatedRangeKm: dte,
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
