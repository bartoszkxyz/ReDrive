import '../../models/dtc_code.dart';

/// Comprehensive offline database of standard SAE J2012 OBD-II Diagnostic Trouble Codes.
class DtcDatabase {
  static const Map<String, DtcCode> _knownCodes = {
    'P0011': DtcCode(
      code: 'P0011',
      system: 'Powertrain',
      title: 'Camshaft Position - Timing Over-Advanced (Bank 1)',
      description:
          'Variable Valve Timing (VVT) intake camshaft timing is advanced beyond ECU target.',
      severity: 'Warning',
      symptoms:
          'Rattling engine noise on start, sluggish acceleration, erratic idle, CEL on.',
      possibleCauses:
          'Dirty engine oil, clogged VVT oil control valve (OCV) screen, stuck VVT solenoid, stretched timing chain.',
    ),
    'P0012': DtcCode(
      code: 'P0012',
      system: 'Powertrain',
      title: 'Camshaft Position - Timing Over-Retarded (Bank 1)',
      description:
          'Variable Valve Timing (VVT) intake camshaft timing is retarded beyond ECU target.',
      severity: 'Warning',
      symptoms:
          'Poor engine performance at high RPM, rough idling, increased emissions.',
      possibleCauses:
          'Low oil pressure, faulty VVT oil control valve, defective camshaft phaser.',
    ),
    'P0100': DtcCode(
      code: 'P0100',
      system: 'Powertrain',
      title: 'Mass Air Flow (MAF) Circuit Malfunction',
      description: 'The ECU detected an electrical issue with the MAF sensor circuit.',
      severity: 'Warning',
      symptoms: 'Rough idle, poor acceleration, stalling, check engine light.',
      possibleCauses: 'Dirty MAF sensor, faulty wiring, disconnected intake hose.',
    ),
    'P0101': DtcCode(
      code: 'P0101',
      system: 'Powertrain',
      title: 'Mass Air Flow (MAF) Sensor Range/Performance',
      description: 'The MAF sensor signal is outside normal operating parameters.',
      severity: 'Warning',
      symptoms: 'Black smoke from exhaust, surging engine, sluggish throttle response.',
      possibleCauses: 'Air intake vacuum leak, dirty or contaminated MAF sensor.',
    ),
    'P0102': DtcCode(
      code: 'P0102',
      system: 'Powertrain',
      title: 'Mass Air Flow (MAF) Sensor Circuit Low Input',
      description: 'The voltage signal from the MAF sensor is abnormally low.',
      severity: 'Warning',
      symptoms: 'Engine hesitates during acceleration, poor fuel efficiency.',
      possibleCauses: 'Broken wire, short to ground, unplugged sensor, faulty sensor.',
    ),
    'P0103': DtcCode(
      code: 'P0103',
      system: 'Powertrain',
      title: 'Mass Air Flow (MAF) Sensor Circuit High Input',
      description:
          'The MAF sensor voltage signal is higher than expected for current engine load.',
      severity: 'Warning',
      symptoms:
          'Black exhaust smoke, engine surging, poor fuel economy, rich air-fuel mixture.',
      possibleCauses:
          'Short to power in MAF sensor wiring, contaminated MAF hot-wire, faulty MAF sensor.',
    ),
    'P0113': DtcCode(
      code: 'P0113',
      system: 'Powertrain',
      title: 'Intake Air Temperature (IAT) Circuit High Input',
      description: 'The IAT sensor reported an electrical resistance indicating extreme cold (-40°C).',
      severity: 'Warning',
      symptoms: 'Hard cold starting, rich fuel mixture, black exhaust soot.',
      possibleCauses: 'Disconnected IAT plug, open circuit, broken wire.',
    ),
    'P0115': DtcCode(
      code: 'P0115',
      system: 'Powertrain',
      title: 'Engine Coolant Temperature (ECT) Circuit Malfunction',
      description: 'The ECU cannot read temperature data from the coolant sensor.',
      severity: 'Critical',
      symptoms: 'Cooling fans run at 100% constantly, erratic idle, rich mixture.',
      possibleCauses: 'Bad ECT sensor, corroded connector, thermostat failure.',
    ),
    'P0117': DtcCode(
      code: 'P0117',
      system: 'Powertrain',
      title: 'Engine Coolant Temperature (ECT) Circuit Low Input',
      description:
          'The ECT sensor reported high voltage indicating extreme high temperature or short to ground.',
      severity: 'Critical',
      symptoms:
          'Temperature gauge pegged hot, engine running rich, cooling fans at maximum speed.',
      possibleCauses:
          'Short circuit in ECT wiring harness, failed ECT sensor, defective ECU ground.',
    ),
    'P0118': DtcCode(
      code: 'P0118',
      system: 'Powertrain',
      title: 'Engine Coolant Temperature (ECT) Circuit High Input',
      description:
          'The ECT sensor voltage is abnormally high, indicating an open circuit or extreme low temperature (-40°C).',
      severity: 'Warning',
      symptoms:
          'Hard engine starting when hot, cooling fans running continuously, rich exhaust smell.',
      possibleCauses:
          'Disconnected ECT wiring connector, broken signal wire, open sensor circuit.',
    ),
    'P0121': DtcCode(
      code: 'P0121',
      system: 'Powertrain',
      title: 'Throttle Position Sensor (TPS) Range/Performance',
      description:
          'The TPS voltage reading does not correlate with calculated engine load and MAF sensor airflow.',
      severity: 'Warning',
      symptoms:
          'Hesitation during acceleration, sudden throttle cut, erratic automatic gear shifts.',
      possibleCauses:
          'Worn TPS potentiometer, dirty throttle body butterfly valve, loose throttle cable.',
    ),
    'P0128': DtcCode(
      code: 'P0128',
      system: 'Powertrain',
      title: 'Coolant Thermostat Temperature Below Regulating Temp',
      description: 'Engine takes too long to warm up or does not reach operating temperature.',
      severity: 'Warning',
      symptoms: 'Heater blows lukewarm air, engine running cooler than normal.',
      possibleCauses: 'Thermostat stuck open, low coolant level, faulty coolant sensor.',
    ),
    'P0130': DtcCode(
      code: 'P0130',
      system: 'Powertrain',
      title: 'O2 Sensor Circuit Malfunction (Bank 1, Sensor 1)',
      description: 'Upstream oxygen sensor circuit failure on cylinder bank 1.',
      severity: 'Warning',
      symptoms: 'Decreased fuel economy, rough idle, higher emissions.',
      possibleCauses: 'Contaminated O2 sensor, damaged wire harness, exhaust leak.',
    ),
    'P0133': DtcCode(
      code: 'P0133',
      system: 'Powertrain',
      title: 'O2 Sensor Circuit Slow Response (Bank 1, Sensor 1)',
      description: 'The upstream oxygen sensor is reacting too slowly between rich and lean states.',
      severity: 'Warning',
      symptoms: 'Degraded fuel economy, failed emissions inspection.',
      possibleCauses: 'Aged/poisoned oxygen sensor, exhaust leak before the sensor.',
    ),
    'P0134': DtcCode(
      code: 'P0134',
      system: 'Powertrain',
      title: 'O2 Sensor Circuit No Activity Detected (Bank 1, Sensor 1)',
      description:
          'Upstream O2 sensor voltage remains flat-lined with no voltage switching.',
      severity: 'Warning',
      symptoms:
          'Open loop fuel control, poor fuel economy, failed emissions.',
      possibleCauses:
          'Unplugged O2 sensor, broken signal wire, defective sensor zirconia element.',
    ),
    'P0135': DtcCode(
      code: 'P0135',
      system: 'Powertrain',
      title: 'O2 Sensor Heater Circuit Malfunction (Bank 1, Sensor 1)',
      description:
          'The electrical heating element in the upstream oxygen sensor failed.',
      severity: 'Warning',
      symptoms:
          'Delayed closed-loop operation on cold start, elevated cold emissions.',
      possibleCauses:
          'Blown O2 heater fuse, burnt heater resistance element, wiring open circuit.',
    ),
    'P0171': DtcCode(
      code: 'P0171',
      system: 'Powertrain',
      title: 'System Too Lean (Bank 1)',
      description: 'The ECU is adding maximum fuel trim compensation because the mixture has excess oxygen.',
      severity: 'Critical',
      symptoms: 'Engine hesitation, misfires under load, rough idling, pinging/knocking.',
      possibleCauses: 'Intake vacuum leak, clogged fuel injector, weak fuel pump, dirty MAF.',
    ),
    'P0172': DtcCode(
      code: 'P0172',
      system: 'Powertrain',
      title: 'System Too Rich (Bank 1)',
      description: 'The ECU is reducing fuel injection duration because the mixture has excess fuel.',
      severity: 'Warning',
      symptoms: 'Strong gasoline odor, dark exhaust smoke, fouled spark plugs.',
      possibleCauses: 'Leaking fuel injector, high fuel rail pressure, dirty air filter.',
    ),
    'P0300': DtcCode(
      code: 'P0300',
      system: 'Powertrain',
      title: 'Random/Multiple Cylinder Misfire Detected',
      description: 'Multiple engine cylinders are experiencing incomplete combustion.',
      severity: 'Critical',
      symptoms: 'Flashing check engine light, strong vehicle vibration, loss of power.',
      possibleCauses: 'Worn spark plugs, failing ignition coils, vacuum leak, low fuel pressure.',
    ),
    'P0301': DtcCode(
      code: 'P0301',
      system: 'Powertrain',
      title: 'Cylinder 1 Misfire Detected',
      description: 'Combustion failure detected specifically in cylinder 1.',
      severity: 'Critical',
      symptoms: 'Engine shaking under acceleration, unburnt fuel smell, check engine light.',
      possibleCauses: 'Cylinder 1 spark plug or ignition coil failure, faulty injector 1.',
    ),
    'P0302': DtcCode(
      code: 'P0302',
      system: 'Powertrain',
      title: 'Cylinder 2 Misfire Detected',
      description: 'Combustion failure detected specifically in cylinder 2.',
      severity: 'Critical',
      symptoms: 'Engine shaking, loss of power, check engine light.',
      possibleCauses: 'Cylinder 2 spark plug or ignition coil failure, faulty injector 2.',
    ),
    'P0303': DtcCode(
      code: 'P0303',
      system: 'Powertrain',
      title: 'Cylinder 3 Misfire Detected',
      description: 'Combustion failure detected specifically in cylinder 3.',
      severity: 'Critical',
      symptoms: 'Engine shaking, loss of power, check engine light.',
      possibleCauses: 'Cylinder 3 spark plug or ignition coil failure, faulty injector 3.',
    ),
    'P0304': DtcCode(
      code: 'P0304',
      system: 'Powertrain',
      title: 'Cylinder 4 Misfire Detected',
      description: 'Combustion failure detected specifically in cylinder 4.',
      severity: 'Critical',
      symptoms: 'Engine shaking, loss of power, check engine light.',
      possibleCauses: 'Cylinder 4 spark plug or ignition coil failure, faulty injector 4.',
    ),
    'P0325': DtcCode(
      code: 'P0325',
      system: 'Powertrain',
      title: 'Knock Sensor 1 Circuit Malfunction (Bank 1)',
      description:
          'The ECU cannot detect signal fluctuations from the piezoelectric knock sensor.',
      severity: 'Warning',
      symptoms:
          'Retarded ignition timing, reduced engine power under heavy acceleration.',
      possibleCauses:
          'Defective knock sensor on engine block, corroded wiring connector, improper sensor torque.',
    ),
    'P0335': DtcCode(
      code: 'P0335',
      system: 'Powertrain',
      title: 'Crankshaft Position Sensor (CKP) Circuit Malfunction',
      description:
          'The ECU lost pulse timing synchronization from the crankshaft reluctor wheel.',
      severity: 'Critical',
      symptoms:
          'Engine stalling, no-start/crank-no-start condition, sudden engine misfire.',
      possibleCauses:
          'Damaged CKP sensor tip, loose crankshaft sensor bracket, severed harness.',
    ),
    'P0340': DtcCode(
      code: 'P0340',
      system: 'Powertrain',
      title: 'Camshaft Position Sensor (CMP) Circuit Malfunction',
      description:
          'Missing or erratic camshaft angle reference signal during cylinder stroke recognition.',
      severity: 'Critical',
      symptoms:
          'Extended cranking time before start, rough idle, loss of high-RPM power.',
      possibleCauses:
          'Faulty CMP sensor on cylinder head, damaged reluctor notch, wiring harness break.',
    ),
    'P0420': DtcCode(
      code: 'P0420',
      system: 'Powertrain',
      title: 'Catalyst System Efficiency Below Threshold (Bank 1)',
      description: 'The catalytic converter is not cleaning exhaust emissions effectively.',
      severity: 'Warning',
      symptoms: 'Check engine light on, rotten egg exhaust odor, slightly reduced MPG.',
      possibleCauses: 'Aged catalytic converter, downstream O2 sensor failure, exhaust leak.',
    ),
    'P0430': DtcCode(
      code: 'P0430',
      system: 'Powertrain',
      title: 'Catalyst System Efficiency Below Threshold (Bank 2)',
      description: 'Bank 2 catalytic converter efficiency is below legal threshold.',
      severity: 'Warning',
      symptoms: 'Check engine light on, rotten egg exhaust odor.',
      possibleCauses: 'Faulty catalytic converter bank 2, downstream O2 sensor.',
    ),
    'P0440': DtcCode(
      code: 'P0440',
      system: 'Powertrain',
      title: 'Evaporative Emission (EVAP) System Malfunction',
      description: 'The fuel tank evaporative vapor recovery system failed its self-test.',
      severity: 'Information',
      symptoms: 'Check engine light on, fuel vapor smell near gas tank.',
      possibleCauses: 'Loose or cracked gas cap, leaking EVAP purge valve, vapor line crack.',
    ),
    'P0442': DtcCode(
      code: 'P0442',
      system: 'Powertrain',
      title: 'EVAP System Small Leak Detected',
      description: 'A small fuel vapor leak (under 0.040") was detected during vacuum testing.',
      severity: 'Information',
      symptoms: 'Gas cap warning, check engine light on.',
      possibleCauses: 'Loose gas cap gasket, cracked EVAP hose, faulty vent valve.',
    ),
    'P0500': DtcCode(
      code: 'P0500',
      system: 'Powertrain',
      title: 'Vehicle Speed Sensor (VSS) Malfunction',
      description: 'The vehicle speed sensor signal is missing or erratic.',
      severity: 'Warning',
      symptoms: 'Speedometer not working, erratic transmission gear shifting, ABS light on.',
      possibleCauses: 'Defective VSS sensor on transmission, broken wiring harness.',
    ),
    'P0505': DtcCode(
      code: 'P0505',
      system: 'Powertrain',
      title: 'Idle Air Control (IAC) System Malfunction',
      description: 'The ECU cannot maintain target idle RPM.',
      severity: 'Warning',
      symptoms: 'Engine stalls when stopping at red lights, surging idle RPM.',
      possibleCauses: 'Carbon-fouled throttle body, sticking IAC valve, vacuum leak.',
    ),
    'P0600': DtcCode(
      code: 'P0600',
      system: 'Powertrain',
      title: 'Serial Communication Link Malfunction',
      description: 'Internal ECU module serial bus communication failure.',
      severity: 'Critical',
      symptoms: 'Engine fails to start, multiple dashboard warning lights illuminated.',
      possibleCauses: 'Corroded ECU ground, battery voltage drop, damaged wiring.',
    ),
    'P0700': DtcCode(
      code: 'P0700',
      system: 'Powertrain',
      title: 'Transmission Control System (MIL Request)',
      description: 'The Transmission Control Module (TCM) reported an internal transmission fault.',
      severity: 'Critical',
      symptoms: 'Transmission in limp mode (stuck in 3rd gear), harsh gear engagement.',
      possibleCauses: 'Transmission solenoid failure, low transmission fluid, TCM fault.',
    ),
    'C0035': DtcCode(
      code: 'C0035',
      system: 'Chassis',
      title: 'Left Front Wheel Speed Sensor Circuit',
      description: 'The ABS module lost wheel rotational speed feedback from the left front wheel.',
      severity: 'Warning',
      symptoms: 'ABS and Traction Control lights illuminated, disabled cruise control.',
      possibleCauses: 'Damaged wheel speed sensor cable, broken tone ring, wheel bearing wear.',
    ),
    'B0001': DtcCode(
      code: 'B0001',
      system: 'Body',
      title: 'Driver Frontal Stage 1 Deployment Control',
      description: 'Fault detected in the steering wheel airbag deployment squib circuit.',
      severity: 'Critical',
      symptoms: 'Airbag (SRS) warning light illuminated, horn or buttons inoperative.',
      possibleCauses: 'Clock spring ribbon cable fracture, loose airbag connector.',
    ),
    'U0100': DtcCode(
      code: 'U0100',
      system: 'Network',
      title: 'Lost Communication with ECM/PCM "A"',
      description: 'CAN-bus communication timeout with the main Engine Control Module.',
      severity: 'Critical',
      symptoms: 'No-crank/no-start condition, instruments display dashes (---).',
      possibleCauses: 'CAN bus termination resistor open, blown ECU main fuse, dead battery.',
    ),
  };

  /// Looks up a DTC code or synthesizes a standard SAE J2012 description based on prefix.
  static DtcCode resolve(String code, {bool isPending = false}) {
    final normalized = code.trim().toUpperCase();
    final known = _knownCodes[normalized];
    if (known != null) {
      if (isPending && !known.isPending) {
        return DtcCode(
          code: known.code,
          system: known.system,
          title: '${known.title} (Pending)',
          description: known.description,
          severity: known.severity,
          isPending: true,
          symptoms: known.symptoms,
          possibleCauses: known.possibleCauses,
        );
      }
      return known;
    }

    // Generic SAE J2012 parsing for unlisted codes:
    final prefix = normalized.isNotEmpty ? normalized[0] : 'P';
    final system = switch (prefix) {
      'P' => 'Powertrain',
      'C' => 'Chassis',
      'B' => 'Body',
      'U' => 'Network',
      _ => 'Vehicle',
    };

    return DtcCode(
      code: normalized,
      system: system,
      title: '$system Diagnostic Trouble Code $normalized',
      description: 'Diagnostic fault detected by vehicle On-Board Diagnostics.',
      severity: isPending ? 'Information' : 'Warning',
      isPending: isPending,
      symptoms: 'Check Engine Light illuminated, vehicle diagnostics required',
      possibleCauses: 'Sensor or actuator fault in the $system subsystem',
    );
  }
}
