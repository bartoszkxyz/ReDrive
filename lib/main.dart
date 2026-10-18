import 'l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:redrive/services/bluetooth/connection/bluetooth_obd_connection.dart';

import 'core/app_flavor.dart';
import 'providers/garage_provider.dart';
import 'providers/obd_provider.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/trip_provider.dart';
import 'core/app_themes.dart';
import 'screens/root_screen.dart';

import 'package:redrive/services/background_service.dart';
import 'package:redrive/services/obd_background_proxy.dart';
import 'package:redrive/services/logging/log_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final flavor = AppFlavor.fromString(appFlavor);
  AppConfig.initialize(
    flavor: flavor,
    appTitle: flavor.isPhone ? 'ReDrive' : 'ReDrive Headunit',
  );

  if (flavor.isPhone) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  await LogService.init();
  LogService.i(
    'ReDrive application starting up (flavor: ${flavor.name})',
    tag: 'App',
  );

  if (flavor.isHeadunit) {
    await initializeBackgroundService();
    ObdBackgroundProxy().init();
  }

  final bluetoothProvider = BluetoothProvider();
  final obdProvider = ObdProvider();
  obdProvider.attachConnection(
    BluetoothObdConnection(bluetoothProvider),
  );
  final tripProvider = TripProvider()..bindToObd(obdProvider);
  final garageProvider = GarageProvider()
    ..bindProviders(obdProvider: obdProvider, tripProvider: tripProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bluetoothProvider),
        ChangeNotifierProvider.value(value: obdProvider),
        ChangeNotifierProvider.value(value: tripProvider),
        ChangeNotifierProvider.value(value: garageProvider),
      ],
      child: const RedriveApp(),
    ),
  );
}

class RedriveApp extends StatelessWidget {
  const RedriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.current.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) {
        if (locale?.languageCode.toLowerCase() == 'zh') {
          final region = (locale?.countryCode ?? '').toUpperCase();
          final script = (locale?.scriptCode ?? '').toLowerCase();
          if (script == 'hant' ||
              region == 'HK' ||
              region == 'MO' ||
              region == 'TW') {
            return Locale('zh', region.isEmpty ? 'TW' : region);
          }
          return const Locale('zh', 'CN');
        }
        return const Locale('en');
      },
      theme: AppThemes.darkTheme,
      home: const RootScreen(),
    );
  }
}
