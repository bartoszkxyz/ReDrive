import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/headunit/native_app_launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.example.redrive/storage';
  final channel = const MethodChannel(channelName);
  late NativeAppLauncherService launcherService;
  late List<MethodCall> methodCalls;
  dynamic mockResult;
  Exception? mockException;

  setUp(() {
    methodCalls = <MethodCall>[];
    mockResult = null;
    mockException = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      if (mockException != null) {
        throw mockException!;
      }
      return mockResult;
    });

    launcherService = NativeAppLauncherService();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('DiscoveredAppInfo Model', () {
    test('serializes to and from JSON correctly', () {
      final app = const DiscoveredAppInfo(
        packageName: 'com.tw.radio',
        activityName: 'com.tw.radio.RadioActivity',
        label: 'Radio',
      );

      final json = app.toJson();
      expect(json, {
        'packageName': 'com.tw.radio',
        'activityName': 'com.tw.radio.RadioActivity',
        'label': 'Radio',
      });

      final fromJson = DiscoveredAppInfo.fromJson(json);
      expect(fromJson, equals(app));
      expect(fromJson.hashCode, equals(app.hashCode));
      expect(fromJson.toString(), contains('com.tw.radio'));
    });

    test('handles missing or null fields in fromJson', () {
      final app = DiscoveredAppInfo.fromJson(const {});
      expect(app.packageName, isEmpty);
      expect(app.activityName, isNull);
      expect(app.label, isEmpty);
    });

    test('equality checks all fields', () {
      const app1 = DiscoveredAppInfo(
        packageName: 'com.tw.radio',
        activityName: 'act1',
        label: 'Radio',
      );
      const app2 = DiscoveredAppInfo(
        packageName: 'com.tw.radio',
        activityName: 'act1',
        label: 'Radio',
      );
      const app3 = DiscoveredAppInfo(
        packageName: 'com.tw.radio',
        activityName: 'act2',
        label: 'Radio',
      );

      expect(app1, equals(app2));
      expect(app1 == app3, isFalse);
    });
  });

  group('NativeAppLauncherService - launchApp', () {
    test('invokes launchApp with packageName and null activityName and returns true', () async {
      mockResult = true;

      final success = await launcherService.launchApp('com.google.maps');

      expect(success, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'launchApp');
      expect(methodCalls.first.arguments, {
        'packageName': 'com.google.maps',
        'activityName': null,
      });
    });

    test('invokes launchApp with packageName and activityName and returns true', () async {
      mockResult = true;

      final success = await launcherService.launchApp(
        'com.google.maps',
        activityName: 'com.google.maps.MapsActivity',
      );

      expect(success, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'launchApp');
      expect(methodCalls.first.arguments, {
        'packageName': 'com.google.maps',
        'activityName': 'com.google.maps.MapsActivity',
      });
    });

    test('returns false when channel returns null or false', () async {
      mockResult = false;
      expect(await launcherService.launchApp('com.foo.bar'), isFalse);

      mockResult = null;
      expect(await launcherService.launchApp('com.foo.bar'), isFalse);
    });

    test('returns false on PlatformException', () async {
      mockException = PlatformException(
        code: 'LAUNCH_FAILED',
        message: 'Application not found',
      );

      final success = await launcherService.launchApp('non.existent.app');

      expect(success, isFalse);
      expect(methodCalls, hasLength(1));
    });
  });

  group('NativeAppLauncherService - Well-Known App Shortcuts', () {
    test('launchTlink passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchTlink();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgTlink5,
        'activityName': NativeAppLauncherService.actTlink5,
      });
      expect(NativeAppLauncherService.pkgTlink5, 'com.zjinnova.zlink');
      expect(
        NativeAppLauncherService.actTlink5,
        'com.zjinnova.android.zlink.features.main.MainActivity',
      );
    });

    test('launchRadio passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchRadio();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgRadio,
        'activityName': NativeAppLauncherService.actRadio,
      });
      expect(NativeAppLauncherService.pkgRadio, 'com.tw.radio');
      expect(NativeAppLauncherService.actRadio, 'com.tw.radio.RadioActivity');
    });

    test('launchDsp passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchDsp();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgDsp,
        'activityName': NativeAppLauncherService.actDsp,
      });
      expect(NativeAppLauncherService.pkgDsp, 'com.tw.eq');
      expect(NativeAppLauncherService.actDsp, 'com.tw.eq.DSPActivity');
    });

    test('launchDvr passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchDvr();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgDvr,
        'activityName': NativeAppLauncherService.actDvr,
      });
      expect(NativeAppLauncherService.pkgDvr, 'com.ankai.cardvr');
      expect(NativeAppLauncherService.actDvr, 'com.ankai.cardvr.ui.MainActivity');
    });

    test('launchBluetooth passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchBluetooth();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgBluetooth,
        'activityName': NativeAppLauncherService.actBluetooth,
      });
      expect(NativeAppLauncherService.pkgBluetooth, 'com.tw.bt');
      expect(NativeAppLauncherService.actBluetooth, 'com.tw.bt.ATBluetoothActivity');
    });

    test('launchFan passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchFan();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgFan,
        'activityName': NativeAppLauncherService.actFan,
      });
      expect(NativeAppLauncherService.pkgFan, 'com.tw.devicefan');
      expect(NativeAppLauncherService.actFan, 'com.tw.devicefan.MainActivity');
    });

    test('launchSettings passes exact known package and activity names', () async {
      mockResult = true;

      final success = await launcherService.launchSettings();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'launchApp');
      expect(methodCalls.last.arguments, {
        'packageName': NativeAppLauncherService.pkgCarSettings,
        'activityName': NativeAppLauncherService.actCarSettings,
      });
      expect(NativeAppLauncherService.pkgCarSettings, 'com.dofun.carsetting');
      expect(NativeAppLauncherService.actCarSettings, 'com.dofun.carsetting.ui.MainActivity');
    });
  });

  group('NativeAppLauncherService - DVR Controls', () {
    test('startDvrRecording invokes startDvrService and returns result', () async {
      mockResult = true;

      final started = await launcherService.startDvrRecording();

      expect(started, isTrue);
      expect(launcherService.isDvrActive, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'startDvrService');
    });

    test('startDvrRecording success activates isDvrActive and isDvrRecording returns true', () async {
      mockResult = true;
      expect(await launcherService.startDvrRecording(), isTrue);
      expect(launcherService.isDvrActive, isTrue);

      methodCalls.clear();
      // Since isDvrActive is true, isDvrRecording returns true immediately without extra platform call
      expect(await launcherService.isDvrRecording(), isTrue);
      expect(methodCalls, isEmpty);
    });

    test('launchDvr success sets isDvrActive to true and isDvrRecording reflects it', () async {
      mockResult = true;
      expect(await launcherService.launchDvr(), isTrue);
      expect(launcherService.isDvrActive, isTrue);
      expect(await launcherService.isDvrRecording(), isTrue);
    });

    test('startDvrRecording returns false on exception or null', () async {
      mockException = PlatformException(code: 'DVR_START_FAILED', message: 'Failed');
      expect(await launcherService.startDvrRecording(), isFalse);
      expect(launcherService.isDvrActive, isFalse);

      mockException = null;
      mockResult = null;
      expect(await launcherService.startDvrRecording(), isFalse);
      expect(launcherService.isDvrActive, isFalse);
    });

    test('isDvrRecording invokes isDvrRunning and updates isDvrActive when channel returns true', () async {
      mockResult = true;

      final running = await launcherService.isDvrRecording();

      expect(running, isTrue);
      expect(launcherService.isDvrActive, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'isDvrRunning');
    });

    test('isDvrRecording returns false on exception or null when not active', () async {
      mockException = PlatformException(code: 'ERROR', message: 'Failed');
      expect(await launcherService.isDvrRecording(), isFalse);

      mockException = null;
      mockResult = null;
      expect(await launcherService.isDvrRecording(), isFalse);
    });

    test('isDvrActive setter allows override for testing or UI previews', () {
      expect(launcherService.isDvrActive, isFalse);
      launcherService.isDvrActive = true;
      expect(launcherService.isDvrActive, isTrue);
    });
  });

  group('NativeAppLauncherService - getInstalledApps', () {
    test('decodes list of maps into DiscoveredAppInfo objects', () async {
      mockResult = [
        {
          'packageName': 'com.tw.radio',
          'activityName': 'com.tw.radio.RadioActivity',
          'label': 'Radio',
        },
        {
          'packageName': 'com.spotify.music',
          'activityName': 'com.spotify.music.MainActivity',
          'label': 'Spotify',
        },
      ];

      final apps = await launcherService.getInstalledApps();

      expect(apps, hasLength(2));
      expect(apps[0].packageName, 'com.tw.radio');
      expect(apps[0].activityName, 'com.tw.radio.RadioActivity');
      expect(apps[0].label, 'Radio');

      expect(apps[1].packageName, 'com.spotify.music');
      expect(apps[1].activityName, 'com.spotify.music.MainActivity');
      expect(apps[1].label, 'Spotify');
    });

    test('handles empty list or null result', () async {
      mockResult = <dynamic>[];
      expect(await launcherService.getInstalledApps(), isEmpty);

      mockResult = null;
      expect(await launcherService.getInstalledApps(), isEmpty);
    });

    test('returns empty list on exception', () async {
      mockException = PlatformException(code: 'QUERY_FAILED', message: 'Error');
      final apps = await launcherService.getInstalledApps();
      expect(apps, isEmpty);
    });
  });

  group('TS18 Hardware PIP Window Control', () {
    test('setPipWindow invokes setPipWindow with correct arguments', () async {
      mockResult = true;
      final success = await launcherService.setPipWindow(
        packageName: 'com.tw.radio',
        activityName: 'com.tw.radio.RadioActivity',
        x: 742,
        y: 68,
        width: 510,
        height: 564,
      );

      expect(success, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'setPipWindow');
      expect(methodCalls.first.arguments, {
        'packageName': 'com.tw.radio',
        'activityName': 'com.tw.radio.RadioActivity',
        'x': 742,
        'y': 68,
        'width': 510,
        'height': 564,
      });
    });

    test('setPipWindow returns false on platform exception', () async {
      mockException = PlatformException(code: 'PIP_FAILED', message: 'Failed to set PIP');
      final success = await launcherService.setPipWindow(packageName: 'com.tw.radio');
      expect(success, isFalse);
    });

    test('releasePipWindow invokes releasePipWindow on channel', () async {
      mockResult = true;
      final success = await launcherService.releasePipWindow();
      expect(success, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'releasePipWindow');
    });

    test('releasePipWindow returns false on exception', () async {
      mockException = PlatformException(code: 'ERR', message: 'Failed');
      final success = await launcherService.releasePipWindow();
      expect(success, isFalse);
    });
  });

  group('Custom Channel Injection', () {
    test('uses custom MethodChannel if provided in constructor', () async {
      const customChannelName = 'com.custom/channel';
      final customChannel = const MethodChannel(customChannelName);
      final customService = NativeAppLauncherService(channel: customChannel);

      expect(customService.channel.name, customChannelName);
    });
  });
}
