import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:redrive/obd/pid/pid_key.dart';
import 'package:redrive/obd/polling/polling_controller.dart';
import 'package:redrive/providers/bluetooth_provider.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/widget/settings/headunit_background_sheet.dart';
import 'package:redrive/widget/settings/obd_adapter_test_sheet.dart';

import '../obd/fakes/fake_obd_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Headunit Enhancements — Coolant Overheat Detection', () {
    late ObdProvider provider;
    late FakeObdConnection connection;

    setUp(() async {
      provider = ObdProvider();
      provider.clearWatchlist(WatchSource.session);
      provider.setWatchlist(WatchSource.visibleScreen, {PidKey.coolantTemperature});
      connection = FakeObdConnection();
      await connection.connect();
      provider.attachConnection(connection);
    });

    tearDown(() async {
      provider.dispose();
      await connection.dispose();
    });

    test('isCoolantOverheating is false initially and triggers at >102°C with hysteresis reset at <96°C', () async {
      expect(provider.isCoolantOverheating, isFalse);

      final startFuture = provider.startRealMode();
      await _completeHandshake(connection);
      await startFuture;

      // 1. Normal operating temp: 90°C -> No overheat alert
      await _waitForCommand(connection, '0105\r', occurrence: 1);
      connection.emit('41 05 82\r>'); // 0x82 = 130 - 40 = 90°C
      await _waitUntil(() => provider.data.coolantTemp == 90, 'coolant 90°C');
      expect(provider.isCoolantOverheating, isFalse);

      // 2. Approaching high temp: 102°C -> Boundary, still false (trigger is >102)
      await _waitForCommand(connection, '0105\r', occurrence: 2);
      connection.emit('41 05 8E\r>'); // 0x8E = 142 - 40 = 102°C
      await _waitUntil(() => provider.data.coolantTemp == 102, 'coolant 102°C');
      expect(provider.isCoolantOverheating, isFalse);

      // 3. Overheating: 103°C -> Triggers alert (>102°C)
      await _waitForCommand(connection, '0105\r', occurrence: 3);
      connection.emit('41 05 8F\r>'); // 0x8F = 143 - 40 = 103°C
      await _waitUntil(() => provider.data.coolantTemp == 103, 'coolant 103°C');
      expect(provider.isCoolantOverheating, isTrue);

      // 4. Slight cooling to 98°C -> Hysteresis retains overheating alert until <96°C
      await _waitForCommand(connection, '0105\r', occurrence: 4);
      connection.emit('41 05 8A\r>'); // 0x8A = 138 - 40 = 98°C
      await _waitUntil(() => provider.data.coolantTemp == 98, 'coolant 98°C');
      expect(provider.isCoolantOverheating, isTrue);

      // 5. Cooling to 95°C -> Hysteresis resets overheating alert (<96°C)
      await _waitForCommand(connection, '0105\r', occurrence: 5);
      connection.emit('41 05 87\r>'); // 0x87 = 135 - 40 = 95°C
      await _waitUntil(() => provider.data.coolantTemp == 95, 'coolant 95°C');
      expect(provider.isCoolantOverheating, isFalse);
    });
  });

  group('Headunit Enhancements — Bluetooth Provider Auto-Connect Settle', () {
    test('autoConnectLastDevice handles unconfigured device gracefully', () async {
      final bt = BluetoothProvider();
      await expectLater(bt.autoConnectLastDevice(), completes);
      expect(bt.isConnected, isFalse);
      expect(bt.isConnecting, isFalse);
    });
  });

  group('Headunit Enhancements — UI Sheets', () {
    testWidgets('HeadunitBackgroundSheet renders expected badges and info', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeadunitBackgroundSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Headunit Background Architecture'), findsOneWidget);
      expect(find.text('Foreground Service'), findsOneWidget);
      expect(find.text('Partial WakeLock'), findsOneWidget);
      expect(find.text('Insecure RFCOMM'), findsOneWidget);
      expect(find.text('Auto-Launch App on Ignition'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Why standard Android permission popups fail'), 100);
      expect(find.text('Why standard Android permission popups fail'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('How ReDrive operates (Car Scanner paradigm)'), 100);
      expect(find.text('How ReDrive operates (Car Scanner paradigm)'), findsOneWidget);
    });

    testWidgets('ObdAdapterTestSheet renders in idle state with test button', (tester) async {
      final obd = ObdProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObdAdapterTestSheet(obdProvider: obd),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test OBD Adapter'), findsOneWidget);
      expect(find.text('Run Handshake Test'), findsOneWidget);
      expect(find.text('Tap below to run the handshake test sequence.'), findsOneWidget);

      obd.dispose();
    });
  });
}

Future<void> _completeHandshake(
  FakeObdConnection connection, {
  int occurrence = 1,
}) async {
  await _waitForCommand(connection, 'ATZ\r', occurrence: occurrence);
  connection.emit('ELM327 v1.5\r>');

  await _waitForCommand(connection, 'ATE0\r', occurrence: occurrence);
  connection.emit('OK\r>');

  await _waitForCommand(connection, 'ATL0\r', occurrence: occurrence);
  connection.emit('OK\r>');

  await _waitForCommand(connection, 'ATSP0\r', occurrence: occurrence);
  connection.emit('OK\r>');

  await _waitForCommand(connection, '0100\r', occurrence: occurrence);
  // 08 in byte 1 = PID 0105 (coolant), 00 in byte 2,3,4 = only coolant, no 0120
  connection.emit('41 00 08 00 00 00\r>');
}

Future<void> _waitForCommand(
  FakeObdConnection connection,
  String command, {
  int occurrence = 1,
}) => _waitUntil(
  () => _commandCount(connection, command) >= occurrence,
  '$command occurrence $occurrence',
);

int _commandCount(FakeObdConnection connection, String command) =>
    connection.sentCommands.where((sent) => sent == command).length;

Future<void> _waitUntil(bool Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
