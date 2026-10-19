import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/core/theme/theme_engine.dart';
import 'package:redrive/l10n/app_localizations.dart';
import 'package:redrive/providers/bluetooth_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/providers/sync_provider.dart';
import 'package:redrive/screens/connection_screen.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/widget/settings/obd_adapter_test_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Widget buildConnectionScreenHarness({
    required BluetoothProvider bluetoothProvider,
    required ObdProvider obdProvider,
    required SyncProvider syncProvider,
    ThemeEngine? themeEngine,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BluetoothProvider>.value(value: bluetoothProvider),
        ChangeNotifierProvider<ObdProvider>.value(value: obdProvider),
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
        ChangeNotifierProvider<ThemeEngine>.value(
          value: themeEngine ?? ThemeEngine(inMemory: true),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConnectionScreen(),
      ),
    );
  }

  group('ConnectionScreen Operations Center', () {
    testWidgets('renders OBD-II operations tab by default with manual connect & demo buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final bluetoothProvider = BluetoothProvider();
      final obdProvider = ObdProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildConnectionScreenHarness(
          bluetoothProvider: bluetoothProvider,
          obdProvider: obdProvider,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // Top title and tabs exist
      expect(find.text('Operations & Diagnostics Center'), findsOneWidget);
      expect(find.byKey(const Key('tab_obd')), findsOneWidget);
      expect(find.byKey(const Key('tab_sync')), findsOneWidget);
      expect(find.byKey(const Key('tab_wifi')), findsOneWidget);
      expect(find.byKey(const Key('tab_troubleshoot')), findsOneWidget);

      // Auto-connect toggle pill & hero manual buttons
      final autoPill = find.byKey(const Key('auto_connect_toggle_pill'));
      expect(autoPill, findsOneWidget);
      expect(find.text('Auto-Connect: ON'), findsOneWidget);

      await tester.tap(autoPill);
      await tester.pumpAndSettle();
      expect(find.text('Auto-Connect: OFF'), findsOneWidget);

      expect(find.byKey(const Key('manual_obd_connect_button')), findsOneWidget);
      expect(find.text('CONNECT TO OBD'), findsOneWidget);

      final demoBtn = find.byKey(const Key('manual_obd_demo_button'));
      expect(demoBtn, findsOneWidget);
      expect(find.text('DEMO MODE'), findsOneWidget);

      // Diagnostic test button
      expect(find.byKey(const Key('run_adapter_test_button')), findsOneWidget);
      expect(find.text('Test OBD Adapter'), findsOneWidget);

      // Tap demo button -> toggles demo mode
      await tester.tap(demoBtn);
      await tester.pumpAndSettle();

      expect(obdProvider.mode, ObdMode.demo);
      expect(find.text('STOP DEMO'), findsOneWidget);
      expect(find.text('Demo Simulator Active'), findsOneWidget);

      // Stop demo mode
      await tester.tap(find.byKey(const Key('manual_obd_demo_button')));
      await tester.pumpAndSettle();
      expect(obdProvider.mode, ObdMode.idle);
      expect(find.text('DEMO MODE'), findsOneWidget);
    });

    testWidgets('tapping Test OBD Adapter opens ObdAdapterTestSheet', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final bluetoothProvider = BluetoothProvider();
      final obdProvider = ObdProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildConnectionScreenHarness(
          bluetoothProvider: bluetoothProvider,
          obdProvider: obdProvider,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      final testBtn = find.byKey(const Key('run_adapter_test_button'));
      expect(testBtn, findsOneWidget);
      await tester.tap(testBtn);
      await tester.pumpAndSettle();

      expect(find.byType(ObdAdapterTestSheet), findsOneWidget);
      expect(find.text('Run Handshake Test'), findsOneWidget);
    });

    testWidgets('switching to Phone Sync tab displays sync controls and Android Auto briefing',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final bluetoothProvider = BluetoothProvider();
      final obdProvider = ObdProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildConnectionScreenHarness(
          bluetoothProvider: bluetoothProvider,
          obdProvider: obdProvider,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Phone Sync tab
      final syncTab = find.byKey(const Key('tab_sync'));
      await tester.tap(syncTab);
      await tester.pumpAndSettle();

      // Verify sync hero card and buttons
      expect(find.byKey(const Key('sync_now_button')), findsOneWidget);
      expect(find.text('Android Auto Wi-Fi Network'), findsOneWidget);
      expect(find.text('Android Auto & Sync Compatibility Note'), findsOneWidget);
      expect(find.byKey(const Key('open_mechanic_report_card_button')), findsOneWidget);
    });

    testWidgets('switching to Diagnostics tab displays checklists and tools',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final bluetoothProvider = BluetoothProvider();
      final obdProvider = ObdProvider();
      final syncService = BluetoothSyncService(
        deviceId: 'test_dev',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final syncProvider = SyncProvider(syncService: syncService);

      await tester.pumpWidget(
        buildConnectionScreenHarness(
          bluetoothProvider: bluetoothProvider,
          obdProvider: obdProvider,
          syncProvider: syncProvider,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Diagnostics tab
      final diagTab = find.byKey(const Key('tab_troubleshoot'));
      await tester.tap(diagTab);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('troubleshoot_test_obd_button')), findsOneWidget);
      expect(find.byKey(const Key('troubleshoot_view_logs_button')), findsOneWidget);
      expect(find.text('OBD-II (ELM327) Connection Checklist'), findsOneWidget);
      expect(find.text('Phone Companion & Android Auto Sync Checklist'), findsOneWidget);
    });
  });
}
