import '../obd/pid/pid_key.dart';

/// Represents a live vehicle sensor with dynamic statistical tracking.
class LiveSensorItem {
  final PidKey key;
  final String name;
  final String category; // 'Engine', 'Air & Fuel', 'Temperatures', 'Electrical', 'Speed'
  final String unit;
  final int decimalPlaces;
  final double normalMin;
  final double normalMax;

  final double currentValue;
  final double minValue;
  final double maxValue;
  final double avgValue;
  final int sampleCount;
  final double sumValue;

  const LiveSensorItem({
    required this.key,
    required this.name,
    required this.category,
    required this.unit,
    this.decimalPlaces = 1,
    this.normalMin = 0.0,
    this.normalMax = 100.0,
    this.currentValue = 0.0,
    this.minValue = 0.0,
    this.maxValue = 0.0,
    this.avgValue = 0.0,
    this.sampleCount = 0,
    this.sumValue = 0.0,
  });

  LiveSensorItem updateValue(double newValue) {
    final newCount = sampleCount + 1;
    final newSum = sumValue + newValue;
    final newMin = sampleCount == 0 ? newValue : (newValue < minValue ? newValue : minValue);
    final newMax = sampleCount == 0 ? newValue : (newValue > maxValue ? newValue : maxValue);
    final newAvg = newSum / newCount;

    return LiveSensorItem(
      key: key,
      name: name,
      category: category,
      unit: unit,
      decimalPlaces: decimalPlaces,
      normalMin: normalMin,
      normalMax: normalMax,
      currentValue: newValue,
      minValue: newMin,
      maxValue: newMax,
      avgValue: newAvg,
      sampleCount: newCount,
      sumValue: newSum,
    );
  }

  /// Value formatted with unit (e.g. "2,450 rpm" or "89.2 °C")
  String get formattedValue {
    if (decimalPlaces == 0) {
      return '${currentValue.toInt()} $unit';
    }
    return '${currentValue.toStringAsFixed(decimalPlaces)} $unit';
  }

  /// Statistical summary string (e.g. "Min: 800 • Max: 3,200 • Avg: 1,840")
  String get statsSummary {
    if (sampleCount == 0) return 'Awaiting telemetry...';
    if (decimalPlaces == 0) {
      return 'Min: ${minValue.toInt()} • Max: ${maxValue.toInt()} • Avg: ${avgValue.toInt()}';
    }
    return 'Min: ${minValue.toStringAsFixed(decimalPlaces)} • Max: ${maxValue.toStringAsFixed(decimalPlaces)} • Avg: ${avgValue.toStringAsFixed(decimalPlaces)}';
  }

  /// Percentage position between normal min and max for gauge/progress bar
  double get progressPercentage {
    if (normalMax <= normalMin) return 0.0;
    return ((currentValue - normalMin) / (normalMax - normalMin)).clamp(0.0, 1.0);
  }

  /// Indicates if the current reading is outside normal operating range
  bool get isAbnormal => sampleCount > 0 && (currentValue < normalMin || currentValue > normalMax);
}
