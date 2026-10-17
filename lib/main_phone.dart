import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_flavor.dart';
import 'main.dart' show RedriveApp;
import 'providers/bluetooth_provider.dart';
import 'providers/obd_provider.dart';
import 'providers/trip_provider.dart';
import 'services/bluetooth/connection/bluetooth_obd_connection.dart';
import 'services/logging/log_service.dart';

/// Entrypoint for the ReDrive Phone companion target.
///
/// Configures portrait orientation and initializes logging and providers
/// without headunit background service or MCU background proxy.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.initialize(
    flavor: AppFlavor.phone,
    appTitle: 'ReDrive',
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await LogService.init();
  LogService.i('ReDrive Phone companion starting up', tag: 'App');

  final bluetoothProvider = BluetoothProvider();
  final obdProvider = ObdProvider();
  obdProvider.attachConnection(
    BluetoothObdConnection(bluetoothProvider),
  );
  final tripProvider = TripProvider()..bindToObd(obdProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bluetoothProvider),
        ChangeNotifierProvider.value(value: obdProvider),
        ChangeNotifierProvider.value(value: tripProvider),
      ],
      child: const RedriveApp(),
    ),
  );
}
