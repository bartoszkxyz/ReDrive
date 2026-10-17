import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_flavor.dart';
import 'main.dart' show RedriveApp;
import 'providers/bluetooth_provider.dart';
import 'providers/obd_provider.dart';
import 'providers/trip_provider.dart';
import 'services/background_service.dart';
import 'services/bluetooth/connection/bluetooth_obd_connection.dart';
import 'services/logging/log_service.dart';
import 'services/obd_background_proxy.dart';

/// Entrypoint for the ReDrive Headunit launcher target.
///
/// Configures landscape orientation, starts headunit background services,
/// and initializes the OBD2 / Trip providers.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.initialize(
    flavor: AppFlavor.headunit,
    appTitle: 'ReDrive Headunit',
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await LogService.init();
  LogService.i('ReDrive Headunit launcher starting up', tag: 'App');

  await initializeBackgroundService();
  ObdBackgroundProxy().init();

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
