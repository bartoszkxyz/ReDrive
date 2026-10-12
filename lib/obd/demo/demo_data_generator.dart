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
    final voltage = 14.1 + (_random.nextDouble() * 0.4); // 14.1 to 14.5 V
    final load = 22.0 + (_currentSpeed / 130.0) * 35.0 + (_random.nextDouble() * 10.0); // 22% - 67%
    final throttle = (load * 0.85).clamp(10.0, 95.0);

    // Instant fuel consumption
    final airGramsSec = (_currentRpm * 1.8 * (load / 100.0)) / 125.0;
    final fuelLPerH = (airGramsSec * 3600.0) / (14.7 * 820.0);
    final l100km = _currentSpeed > 0 ? (fuelLPerH / _currentSpeed) * 100.0 : 0.0;

    return ObdData(
      speed: _currentSpeed,
      rpm: _currentRpm,
      coolantTemp: coolantTemp,
      voltage: voltage,
      engineLoad: load,
      throttlePosition: throttle,
      maf: airGramsSec,
      engineFuelRate: fuelLPerH,
      instantFuelLPerHour: fuelLPerH,
      instantFuelL100km: l100km,
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
