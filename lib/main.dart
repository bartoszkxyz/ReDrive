import 'dart:async';

import 'l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:obdrive/services/bluetooth/connection/bluetooth_obd_connection.dart';

import 'core/app_flavor.dart';
import 'providers/garage_provider.dart';
import 'providers/obd_provider.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/trip_provider.dart';
import 'providers/sync_provider.dart';
import 'services/sync/bluetooth_sync_service.dart';
import 'core/theme/theme_engine.dart';
import 'core/app_themes.dart';
import 'screens/phone_companion_screen.dart';
import 'screens/root_screen.dart';

import 'package:obdrive/services/background_service.dart';
import 'package:obdrive/services/obd_background_proxy.dart';
import 'package:obdrive/services/logging/log_service.dart';

Future<void> runOBDriveApp(AppFlavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Install robust top-level crash logging to guarantee errors are captured on disk
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    LogService.e(
      'Unhandled Flutter error: ${details.exceptionAsString()}',
      tag: 'FlutterCrash',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) {
    LogService.e(
      'Unhandled async exception: $error',
      tag: 'AsyncCrash',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  AppConfig.initialize(
    flavor: flavor,
    appTitle: flavor.isPhone ? 'OBDrive Companion' : 'OBDrive Headunit',
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
    'OBDrive application starting up (flavor: ${flavor.name})',
    tag: 'App',
  );

  if (flavor.isHeadunit) {
    await initializeBackgroundService();
    ObdBackgroundProxy().init();
  }

  final bluetoothProvider = BluetoothProvider();
  final obdProvider = ObdProvider();
  if (flavor.isHeadunit) {
    obdProvider.attachConnection(
      BluetoothObdConnection(bluetoothProvider),
    );
  }
  final themeEngine = ThemeEngine();
  final tripProvider = TripProvider()..bindToObd(obdProvider);
  final garageProvider = GarageProvider()
    ..bindProviders(obdProvider: obdProvider, tripProvider: tripProvider);
  final syncProvider = SyncProvider(
    syncService: BluetoothSyncService(
      deviceId: 'obdrive_${flavor.name}_${DateTime.now().millisecondsSinceEpoch}',
      deviceRole: flavor.name,
    ),
    themeEngine: themeEngine,
  )..bindProviders(
      tripProvider: tripProvider,
      garageProvider: garageProvider,
      obdProvider: obdProvider,
      themeEngine: themeEngine,
    );

  if (flavor.isHeadunit) {
    unawaited(syncProvider.startNetworkSyncServer());
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeEngine),
        ChangeNotifierProvider.value(value: bluetoothProvider),
        ChangeNotifierProvider.value(value: obdProvider),
        ChangeNotifierProvider.value(value: tripProvider),
        ChangeNotifierProvider.value(value: garageProvider),
        ChangeNotifierProvider.value(value: syncProvider),
      ],
      child: const OBDriveApp(),
    ),
  );
}

void main() async {
  const envFlavor = String.fromEnvironment('FLAVOR');
  final flavor = envFlavor.isNotEmpty
      ? AppFlavor.fromString(envFlavor)
      : AppFlavor.fromString(appFlavor);
  await runOBDriveApp(flavor);
}

class OBDriveApp extends StatelessWidget {
  const OBDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData activeTheme = AppThemes.darkTheme;
    try {
      activeTheme = context.watch<ThemeEngine>().materialTheme;
    } catch (_) {}

    return MaterialApp(
      title: AppConfig.current.appTitle,
      debugShowCheckedModeBanner: false,
      theme: activeTheme,
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
        if (locale?.languageCode.toLowerCase() == 'pl') {
          return const Locale('pl');
        }
        return const Locale('en');
      },
      home: AppConfig.isPhone
          ? const PhoneCompanionScreen()
          : const RootScreen(),
    );
  }
}
