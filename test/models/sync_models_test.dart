import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/models/dtc_code.dart';
import 'package:redrive/models/sync_models.dart';
import 'package:redrive/models/trip_anomaly.dart';
import 'package:redrive/models/vehicle_profile.dart';

void main() {
  final fixedDate = DateTime.utc(2026, 10, 19, 14, 0, 0);

  final testVehicle = VehicleProfile.defaultSuzukiSwiftM15A().copyWith(
    vin: 'VIN1234567890PL',
    fuelType: FuelType.gasoline,
  );

  const storedDtc = DtcCode(
    code: 'P0300',
    system: 'Powertrain',
    title: 'Random/Multiple Cylinder Misfire Detected',
    description: 'Multiple cylinders misfiring',
    severity: 'Critical',
    isPending: false,
    symptoms: 'Engine light blinking',
    possibleCauses: 'Faulty spark plugs or ignition coils',
  );

  const pendingDtc = DtcCode(
    code: 'P0171',
    system: 'Powertrain',
    title: 'System Too Lean (Bank 1)',
    description: 'Air-fuel mixture too lean',
    severity: 'Warning',
    isPending: true,
    symptoms: 'Hesitation during acceleration',
    possibleCauses: 'Intake manifold vacuum leak',
  );

  final anomaly = TripAnomalyEpisode(
    id: 'anom_01',
    severity: AnomalySeverity.problem,
    category: AnomalyCategory.powerLoss,
    title: 'Severe Engine Misfire',
    description: 'RPM stutter under heavy load',
    startTime: fixedDate,
    endTime: fixedDate.add(const Duration(seconds: 15)),
    latitude: 52.2297,
    longitude: 21.0122,
    dtcCodes: const ['P0300'],
  );

  final testSnapshot = ParkedCarSnapshot(
    vehicleId: 'veh_01',
    vehicleName: 'Suzuki Swift 3',
    timestamp: fixedDate,
    latitude: 52.2297,
    longitude: 21.0122,
    fuelLevelPercent: 70.0,
    remainingFuelLiters: 35.0,
    estimatedRangeKm: 450.0,
    batteryVoltage: 12.60,
    odometerKm: 154210.0,
    coolantTempC: 88.5,
  );

  group('MechanicDiagnosticReport summary generation', () {
    test('toFormattedTextSummary defaults to English with OBDrive header', () {
      final report = MechanicDiagnosticReport(
        reportId: 'REP-001',
        generatedAt: fixedDate,
        vehicle: testVehicle,
        currentOdometerKm: 154210.0,
        storedDtcs: const [storedDtc],
        pendingDtcs: const [pendingDtc],
        recentAnomalies: [anomaly],
        latestSnapshot: testSnapshot,
      );

      final summary = report.toFormattedTextSummary();

      expect(summary, contains('OBDRIVE DIAGNOSTIC REPORT'));
      expect(summary, isNot(contains('REDRIVE DIAGNOSTIC REPORT')));
      expect(summary, contains('Report ID: REP-001'));
      expect(summary, contains('--- VEHICLE INFORMATION ---'));
      expect(summary, contains('Vehicle: Suzuki Swift 3'));
      expect(summary, contains('VIN: VIN1234567890PL'));
      expect(summary, contains('Fuel Type: Gasoline'));
      expect(summary, contains('Odometer: 154210.0 km'));
      expect(summary, contains('--- STORED DIAGNOSTIC CODES (MODE 03) ---'));
      expect(summary, contains('[P0300] (Critical) Random/Multiple Cylinder Misfire Detected'));
      expect(summary, contains('  System: Powertrain'));
      expect(summary, contains('--- PENDING DIAGNOSTIC CODES (MODE 07) ---'));
      expect(summary, contains('[P0171] (Warning) System Too Lean (Bank 1)'));
      expect(summary, contains('--- RECENT ANOMALY EPISODES ---'));
      expect(summary, contains('• Severe Engine Misfire [PROBLEM]'));
      expect(summary, contains('  GPS Coordinates: 52.2297, 21.0122'));
      expect(summary, contains('--- LATEST PARKED TELEMETRY ---'));
      expect(summary, contains('Battery Voltage: 12.60 V'));
      expect(summary, contains('Coolant Temp: 88.5 °C'));
      expect(summary, contains('Fuel Remaining: 35.0 L (70.0%)'));
      expect(summary, contains('Estimated Range: 450.0 km'));
    });

    test('toFormattedTextSummary in Polish language produces full Polish report', () {
      final report = MechanicDiagnosticReport(
        reportId: 'REP-002',
        generatedAt: fixedDate,
        vehicle: testVehicle,
        currentOdometerKm: 154210.0,
        storedDtcs: const [storedDtc],
        pendingDtcs: const [pendingDtc],
        recentAnomalies: [anomaly],
        latestSnapshot: testSnapshot,
        attachedTripId: 'TRIP-77',
        attachedSampleCount: 150,
      );

      final summary = report.toFormattedTextSummary(language: 'pl');

      expect(summary, contains('RAPORT DIAGNOSTYCZNY OBDRIVE'));
      expect(summary, contains('Identyfikator raportu: REP-002'));
      expect(summary, contains('Wygenerowano: ${fixedDate.toIso8601String()}'));
      expect(summary, contains('--- INFORMACJE O POJEŹDZIE ---'));
      expect(summary, contains('Pojazd: Suzuki Swift 3'));
      expect(summary, contains('VIN: VIN1234567890PL'));
      expect(summary, contains('Rodzaj paliwa: Benzyna'));
      expect(summary, contains('Przebieg całkowity: 154210.0 km'));
      expect(summary, contains('Załączona trasa: TRIP-77 (150 próbek)'));

      // Stored DTCs
      expect(summary, contains('--- ZAPISANE KODY BŁĘDÓW (TRYB 03) ---'));
      expect(summary, contains('[P0300] (Krytyczny) Random/Multiple Cylinder Misfire Detected'));
      expect(summary, contains('  Układ: Układ napędowy'));
      expect(summary, contains('  Opis: Multiple cylinders misfiring'));
      expect(summary, contains('  Możliwe przyczyny / zalecane kroki: Faulty spark plugs or ignition coils'));

      // Pending DTCs
      expect(summary, contains('--- OCZEKUJĄCE KODY BŁĘDÓW (TRYB 07) ---'));
      expect(summary, contains('[P0171] (Ostrzeżenie) System Too Lean (Bank 1)'));

      // Anomalies
      expect(summary, contains('--- OSTATNIE WYKRYTE ANOMALIE ---'));
      expect(summary, contains('• Severe Engine Misfire [PROBLEM]'));
      expect(summary, contains('  Czas: ${fixedDate.toIso8601String()}'));
      expect(summary, contains('  Pozycja GPS: 52.2297, 21.0122'));
      expect(summary, contains('  Opis: RPM stutter under heavy load'));
      expect(summary, contains('  Powiązane kody DTC: P0300'));

      // Telemetry
      expect(summary, contains('--- OSTATNIA TELEMETRIA POSTOJU ---'));
      expect(summary, contains('Napięcie akumulatora: 12.60 V'));
      expect(summary, contains('Temperatura płynu chłodzącego: 88.5 °C'));
      expect(summary, contains('Pozostałe paliwo: 35.0 L (70.0%)'));
      expect(summary, contains('Szacowany zasięg: 450.0 km'));
      expect(summary, contains('Pozycja GPS: 52.2297, 21.0122'));
    });

    test('Polish summary handles empty fault lists and null snapshot gracefully', () {
      final emptyReport = MechanicDiagnosticReport(
        reportId: 'REP-EMPTY',
        generatedAt: fixedDate,
        vehicle: VehicleProfile.defaultSuzukiSwiftM15A(),
        currentOdometerKm: 50000.0,
      );

      final summary = emptyReport.toFormattedTextSummary(language: 'PL');

      expect(summary, contains('VIN: Brak danych'));
      expect(summary, contains('Brak zapisanych kodów DTC.'));
      expect(summary, contains('Brak oczekujących kodów DTC.'));
      expect(summary, contains('Brak wykrytych anomalii.'));
      expect(summary, contains('Brak danych telemetrycznych postoju.'));
    });
  });

  group('MechanicDiagnosticReport Polish translation helpers', () {
    test('fuelTypeToPl translates all FuelType values accurately', () {
      expect(MechanicDiagnosticReport.fuelTypeToPl(FuelType.gasoline), 'Benzyna');
      expect(MechanicDiagnosticReport.fuelTypeToPl(FuelType.lpg), 'LPG');
      expect(MechanicDiagnosticReport.fuelTypeToPl(FuelType.diesel), 'Diesel');
      expect(MechanicDiagnosticReport.fuelTypeToPl(FuelType.hybrid), 'Hybryda');
    });

    test('severityToPl translates severity levels accurately', () {
      expect(MechanicDiagnosticReport.severityToPl('Critical'), 'Krytyczny');
      expect(MechanicDiagnosticReport.severityToPl('Warning'), 'Ostrzeżenie');
      expect(MechanicDiagnosticReport.severityToPl('problem'), 'Problem');
      expect(MechanicDiagnosticReport.severityToPl('info'), 'Informacja');
      expect(MechanicDiagnosticReport.severityToPl('Custom'), 'Custom');
    });

    test('systemToPl translates OBD subsystems accurately', () {
      expect(MechanicDiagnosticReport.systemToPl('Powertrain'), 'Układ napędowy');
      expect(MechanicDiagnosticReport.systemToPl('Chassis'), 'Podwozie');
      expect(MechanicDiagnosticReport.systemToPl('Body'), 'Nadwozie');
      expect(MechanicDiagnosticReport.systemToPl('Network'), 'Sieć / Komunikacja');
      expect(MechanicDiagnosticReport.systemToPl('CustomSys'), 'CustomSys');
    });
  });

  group('AppLocalizations Polish translations', () {
    const polishLocale = Locale('pl');
    final localizations = AppLocalizations(polishLocale);

    test('isPolish and isChinese reflection', () {
      expect(localizations.isPolish, isTrue);
      expect(localizations.isChinese, isFalse);
      expect(localizations.isTraditionalChinese, isFalse);
    });

    test('getters return Polish strings', () {
      expect(localizations.home, 'Główny');
      expect(localizations.dashboard, 'Pulpit');
      expect(localizations.connection, 'Połączenie');
      expect(localizations.garage, 'Garaż');
      expect(localizations.dtc, 'Błędy DTC');
      expect(localizations.trips, 'Trasy');
      expect(localizations.speed, 'Prędkość');
      expect(localizations.rpm, 'Obr/min');
      expect(localizations.coolantTemp, 'Płyn chłodzący');
      expect(localizations.engineTemp, 'Temp. silnika');
      expect(localizations.readyToDrive, 'Gotowy do jazdy');
      expect(localizations.warmingUp, 'Rozgrzewanie');
      expect(localizations.activeTrip, 'Aktywna trasa');
      expect(localizations.avgFuel, 'Średnie spalanie');
      expect(localizations.instantFuel, 'Chwilowe spalanie');
      expect(localizations.fuelLoad, 'Dawka paliwa');
      expect(localizations.engineLoad, 'Obciążenie silnika');
      expect(localizations.preparing, 'Przygotowywanie połączenia...');
      expect(localizations.connectingEcu, 'Łączenie z ECU pojazdu...');
      expect(localizations.initializing, 'Inicjalizacja ELM327...');
      expect(localizations.connected, 'Połączono');
      expect(localizations.recovering, 'Wznawianie połączenia...');
      expect(localizations.connectionError, 'Błąd połączenia');
      expect(localizations.cancel, 'Anuluj');
      expect(localizations.settings, 'Ustawienia');
      expect(localizations.bluetooth, 'Bluetooth');
      expect(localizations.wifi, 'Wi-Fi');
      expect(localizations.wifiDeveloping, 'Połączenie Wi-Fi w trakcie realizacji');
      expect(localizations.usbDeveloping, 'Połączenie USB w trakcie realizacji');
      expect(localizations.bluetoothConnection, 'Połączenie Bluetooth');
      expect(localizations.bluetoothDescription,
          'Połącz adapter OBD2, aby wyświetlić dane pojazdu w czasie rzeczywistym.');
      expect(localizations.startScanning, 'Rozpocznij skanowanie');
      expect(localizations.scanning, 'Skanowanie...');
      expect(localizations.scanningComplete, 'Skanowanie zakończone');
      expect(localizations.searchingAdapter, 'Wyszukiwanie adaptera...');
      expect(localizations.devicesFound(4), 'Znaleziono 4 urządzeń');
      expect(localizations.permissionTitle, 'Wymagane uprawnienia Bluetooth');
      expect(localizations.permissionDescription,
          'Uprawnienia Bluetooth zostały trwale odrzucone. Włącz je w ustawieniach systemu.');
      expect(localizations.openSettings, 'Otwórz ustawienia');
      expect(localizations.garageTitle, 'Mój Garaż');
      expect(localizations.garageDescription, 'Tutaj pojawią się Twoje pojazdy');
      expect(localizations.noVehicles, 'Brak pojazdów');
      expect(localizations.addFirstVehicle, 'Dodaj swój\npierwszy pojazd');
      expect(localizations.addVehicle, 'Dodaj pojazd');
      expect(localizations.vehicleConnected, 'Pojazd połączony');
      expect(localizations.connect, 'Połącz');
      expect(localizations.disconnectDemo, 'Odłącz');
      expect(localizations.bannerRestoring, 'Wznawianie sesji diagnostycznej OBD...');
      expect(localizations.bannerReconnecting, 'Ponowne łączenie z adapterem OBD...');
      expect(localizations.connectionLost, 'Utracono połączenie z OBD');
      expect(localizations.protocol, 'Protokół');
      expect(localizations.autoDetect, 'Wykryj automatycznie');
      expect(localizations.adapterNotResponding('OBDLink CX'),
          "Błąd: urządzenie 'OBDLink CX' nie odpowiada");
    });

    test('supportedLocales includes pl and delegate supports pl', () {
      expect(AppLocalizations.supportedLocales.contains(const Locale('pl')), isTrue);
      expect(AppLocalizations.delegate.isSupported(const Locale('pl')), isTrue);
      expect(AppLocalizations.delegate.isSupported(const Locale('PL')), isTrue);
    });
  });
}
