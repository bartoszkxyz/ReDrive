/// Represents the OBD-II Fuel System Loop Status (PID 0103).
enum FuelSystemStatus {
  closedLoop,
  openLoopWarmup,
  openLoopLoadOrDecel,
  openLoopFault,
  closedLoopFault,
  unknown;

  static FuelSystemStatus fromNumeric(num value) {
    final v = value.toInt();
    if (v == 2) return FuelSystemStatus.closedLoop;
    if (v == 1) return FuelSystemStatus.openLoopWarmup;
    if (v == 4) return FuelSystemStatus.openLoopLoadOrDecel;
    if (v == 8) return FuelSystemStatus.openLoopFault;
    if (v == 16) return FuelSystemStatus.closedLoopFault;
    return FuelSystemStatus.unknown;
  }

  String get label {
    switch (this) {
      case FuelSystemStatus.closedLoop:
        return 'Closed Loop (O2 Feedback)';
      case FuelSystemStatus.openLoopWarmup:
        return 'Open Loop (Cold Warmup)';
      case FuelSystemStatus.openLoopLoadOrDecel:
        return 'Open Loop (Power / Decel)';
      case FuelSystemStatus.openLoopFault:
        return 'Open Loop (System Fault)';
      case FuelSystemStatus.closedLoopFault:
        return 'Closed Loop (Feedback Fault)';
      case FuelSystemStatus.unknown:
        return 'Unknown';
    }
  }

  String get shortCode {
    switch (this) {
      case FuelSystemStatus.closedLoop:
        return 'CL';
      case FuelSystemStatus.openLoopWarmup:
        return 'OL-Warm';
      case FuelSystemStatus.openLoopLoadOrDecel:
        return 'OL-Drive';
      case FuelSystemStatus.openLoopFault:
        return 'OL-Fault';
      case FuelSystemStatus.closedLoopFault:
        return 'CL-Fault';
      case FuelSystemStatus.unknown:
        return '--';
    }
  }

  bool get isClosedLoop => this == FuelSystemStatus.closedLoop || this == FuelSystemStatus.closedLoopFault;
}
