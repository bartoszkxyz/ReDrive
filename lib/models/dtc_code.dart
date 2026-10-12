/// Represents a Diagnostic Trouble Code (DTC) decoded from the vehicle ECU.
class DtcCode {
  final String code; // e.g. "P0300"
  final String system; // "Powertrain", "Chassis", "Body", "Network"
  final String title; // Short summary
  final String description; // Detailed description
  final String severity; // "Critical", "Warning", "Information"
  final bool isPending; // true if Mode 07 (pending), false if Mode 03 (confirmed)
  final String symptoms;
  final String possibleCauses;

  const DtcCode({
    required this.code,
    required this.system,
    required this.title,
    required this.description,
    this.severity = 'Warning',
    this.isPending = false,
    this.symptoms = 'Check Engine Light illuminated, possible performance decrease',
    this.possibleCauses = 'Sensor fault, wiring issue, or component wear',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DtcCode && runtimeType == other.runtimeType && code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$code: $title ($system)';
}
