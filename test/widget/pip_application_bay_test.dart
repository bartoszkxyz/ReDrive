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
      if (call.method == 'getInstalledApps') {
        return [
          {
            'packageName': 'com.google.android.apps.maps',
            'activityName': 'com.google.android.maps.MapsActivity',
            'label': 'Maps',
          },
          {
            'packageName': 'com.spotify.music',
            'activityName': 'com.spotify.music.MainActivity',
            'label': 'Spotify',
          },
        ];
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
            ),
          ),
        ),
      ),
    );
  }

  group('PipApplicationBay Widget Tests', () {
    testWidgets('renders default slots and sets initial TS18 PIP window for Radio',
        (tester) async {
      PipSlotConfig? activeSlot;

      await tester.pumpWidget(
        buildHarness(onSlotChanged: (slot) => activeSlot = slot),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pip_application_bay')), findsOneWidget);
      expect(find.byKey(const Key('pip_tab_radio')), findsOneWidget);
      expect(find.byKey(const Key('pip_tab_dvr')), findsOneWidget);
      expect(find.byKey(const Key('pip_tab_tlink')), findsOneWidget);

      expect(activeSlot?.id, 'radio');
      expect(activeSlot?.packageName, NativeAppLauncherService.pkgRadio);

      // Verify native setPipWindow was called
      expect(
        methodCalls.any((c) =>
            c.method == 'setPipWindow' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgRadio &&
            c.arguments['x'] == 742 &&
            c.arguments['y'] == 68 &&
            c.arguments['width'] == 510 &&
            c.arguments['height'] == 564),
        isTrue,
      );
    });

    testWidgets('switching tabs updates active slot and invokes setPipWindow',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      methodCalls.clear();

      // Tap DVR tab
      await tester.tap(find.byKey(const Key('pip_tab_dvr')));
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((c) =>
            c.method == 'setPipWindow' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgDvr),
        isTrue,
      );

      methodCalls.clear();

      // Tap TLINK tab
      await tester.tap(find.byKey(const Key('pip_tab_tlink')));
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((c) =>
            c.method == 'setPipWindow' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgTlink5),
        isTrue,
      );
    });

    testWidgets('fullscreen maximize button launches current active app',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Switch to TLINK5
      await tester.tap(find.byKey(const Key('pip_tab_tlink')));
      await tester.pumpAndSettle();

      methodCalls.clear();

      // Tap Fullscreen maximize button
      await tester.tap(find.byKey(const Key('pip_maximize_button')));
      await tester.pumpAndSettle();

      expect(
        methodCalls.any((c) =>
            c.method == 'launchApp' &&
            c.arguments['packageName'] == NativeAppLauncherService.pkgTlink5),
        isTrue,
      );
    });

    testWidgets('radio tab volume controls and media skip buttons trigger launcherService',
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
        methodCalls.any((c) => c.method == 'sendMediaKey' && c.arguments['keyCode'] == NativeAppLauncherService.keyCodeMediaNext),
        isTrue,
      );
    });

    testWidgets('reassign button opens sheet and updates slot app',
        (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Radio is not configurable, switch to DVR (configurable)
      await tester.tap(find.byKey(const Key('pip_tab_dvr')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pip_reassign_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pip_reassign_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pip_reassign_sheet')), findsOneWidget);
      expect(find.text('Maps'), findsOneWidget);

      methodCalls.clear();

      // Select Maps
      await tester.tap(find.byKey(const Key('reassign_app_com.google.android.apps.maps')));
      await tester.pumpAndSettle();

      // Sheet should close and PIP window be set for Maps
      expect(find.byKey(const Key('pip_reassign_sheet')), findsNothing);
      expect(find.text('MAPS'), findsOneWidget);
      expect(
        methodCalls.any((c) =>
            c.method == 'setPipWindow' &&
            c.arguments['packageName'] == 'com.google.android.apps.maps'),
        isTrue,
      );
    });
  });
}
