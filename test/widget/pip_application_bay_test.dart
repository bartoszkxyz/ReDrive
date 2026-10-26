import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:redrive/core/theme/theme_engine.dart';
import 'package:redrive/services/headunit/native_app_launcher_service.dart';
import 'package:redrive/widget/cockpit/pip_application_bay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> methodCalls;
  late NativeAppLauncherService launcherService;

  setUp(() {
    methodCalls = <MethodCall>[];
    channel = const MethodChannel('com.example.redrive/storage');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      if (call.method == 'setPipWindow') {
        return true;
      }
      if (call.method == 'launchApp') {
        return true;
      }
      if (call.method == 'getAudioState') {
        return {
          'volume': 15,
          'maxVolume': 30,
          'isMuted': false,
          'isMusicActive': true,
        };
      }
      if (call.method == 'adjustVolume') {
        final dir = call.arguments['direction'] as int? ?? 0;
        return {
          'volume': (15 + dir).clamp(0, 30),
          'maxVolume': 30,
        };
      }
      if (call.method == 'setVolume') {
        return true;
      }
      if (call.method == 'sendMediaKey') {
        return true;
      }
      return null;
    });

    launcherService = NativeAppLauncherService(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget buildHarness({
    void Function(PipSlotConfig)? onSlotChanged,
    bool autoSetPipWindow = false,
  }) {
    final themeEngine = ThemeEngine(inMemory: true);
    return MaterialApp(
      home: ChangeNotifierProvider<ThemeEngine>.value(
        value: themeEngine,
        child: Scaffold(
          body: SizedBox(
            width: 510,
            height: 564,
            child: PipApplicationBay(
              launcherService: launcherService,
              onSlotChanged: onSlotChanged,
              autoSetPipWindow: autoSetPipWindow,
            ),
          ),
        ),
      ),
    );
  }

  group('PipApplicationBay Radio & Audio Controls Widget Tests', () {
    testWidgets('renders radio controls panel and FM frequency display by default',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pip_application_bay')), findsOneWidget);
      expect(find.byKey(const Key('pip_live_surface')), findsOneWidget);
      expect(find.byKey(const Key('pip_tab_radio')), findsOneWidget);
      expect(find.byKey(const Key('radio_band_am')), findsOneWidget);
      expect(find.byKey(const Key('pip_maximize_button')), findsOneWidget);

      // Default FM readout (98.50 MHz)
      expect(find.text('98.50'), findsOneWidget);
      expect(find.text('MHz'), findsOneWidget);
      expect(find.text('STEREO • TS18 LIVE AUDIO'), findsOneWidget);

      // Presets P1 to P6
      for (int i = 1; i <= 6; i++) {
        expect(find.byKey(Key('radio_preset_$i')), findsOneWidget);
      }

      // Master volume and media buttons
      expect(find.byKey(const Key('pip_volume_down_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_volume_up_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_volume_mute_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_media_prev_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_media_play_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_media_next_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_action_launch_radio')), findsOneWidget);
    });

    testWidgets('autoSetPipWindow triggers setPipWindow when enabled',
        (tester) async {
      PipSlotConfig? slot;
      await tester.pumpWidget(buildHarness(
        autoSetPipWindow: true,
        onSlotChanged: (s) => slot = s,
      ));
      await tester.pumpAndSettle();

      expect(slot?.id, 'radio');
      expect(
        methodCalls.any((c) =>
            c.method == 'setPipWindow' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgRadio),
        isTrue,
      );
    });

    testWidgets('switching between FM and AM band updates frequency and units',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Tap AM
      await tester.tap(find.byKey(const Key('radio_band_am')));
      await tester.pumpAndSettle();

      expect(find.text('648'), findsNWidgets(2)); // Main readout and Preset P2
      expect(find.text('kHz'), findsOneWidget);

      // Tap FM
      await tester.tap(find.byKey(const Key('pip_tab_radio')));
      await tester.pumpAndSettle();

      expect(find.text('98.50'), findsOneWidget);
      expect(find.text('MHz'), findsOneWidget);
    });

    testWidgets('stepping frequency and selecting preset updates display',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Step up +0.1
      await tester.tap(find.byKey(const Key('radio_step_up')));
      await tester.pumpAndSettle();
      expect(find.text('98.60'), findsOneWidget);

      // Step down -0.1
      await tester.tap(find.byKey(const Key('radio_step_down')));
      await tester.pumpAndSettle();
      expect(find.text('98.50'), findsOneWidget);

      // Tap Preset P1 (89.1)
      await tester.tap(find.byKey(const Key('radio_preset_1')));
      await tester.pumpAndSettle();
      expect(find.text('89.10'), findsOneWidget);
    });

    testWidgets('volume controls and media skip buttons trigger launcherService',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      methodCalls.clear();

      // Volume Down
      await tester.tap(find.byKey(const Key('pip_volume_down_button')));
      await tester.pumpAndSettle();
      expect(
        methodCalls.any((c) => c.method == 'adjustVolume' && c.arguments['direction'] == -1),
        isTrue,
      );

      methodCalls.clear();

      // Volume Up
      await tester.tap(find.byKey(const Key('pip_volume_up_button')));
      await tester.pumpAndSettle();
      expect(
        methodCalls.any((c) => c.method == 'adjustVolume' && c.arguments['direction'] == 1),
        isTrue,
      );

      methodCalls.clear();

      // Mute Toggle
      await tester.tap(find.byKey(const Key('pip_volume_mute_button')));
      await tester.pumpAndSettle();
      expect(
        methodCalls.any((c) => c.method == 'setVolume'),
        isTrue,
      );

      methodCalls.clear();

      // Media Next
      await tester.tap(find.byKey(const Key('pip_media_next_button')));
      await tester.pumpAndSettle();
      expect(
        methodCalls.any((c) =>
            c.method == 'sendMediaKey' &&
            c.arguments['keyCode'] == NativeAppLauncherService.keyCodeMediaNext),
        isTrue,
      );
    });

    testWidgets('fullscreen maximize button and open radio button launch Radio app',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      methodCalls.clear();

      // Tap Corner Maximize button
      await tester.tap(find.byKey(const Key('pip_maximize_button')));
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgRadio),
        isTrue,
      );

      methodCalls.clear();

      // Tap Open Radio App button
      await tester.tap(find.byKey(const Key('pip_action_launch_radio')));
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgRadio),
        isTrue,
      );
    });
  });
}
