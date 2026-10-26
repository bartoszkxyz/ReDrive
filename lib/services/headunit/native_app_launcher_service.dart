import 'package:flutter/services.dart';

/// Information about a launchable application discovered on the system.
class DiscoveredAppInfo {
  final String packageName;
  final String? activityName;
  final String label;

  const DiscoveredAppInfo({
    required this.packageName,
    this.activityName,
    required this.label,
  });

  factory DiscoveredAppInfo.fromJson(Map<String, dynamic> json) {
    return DiscoveredAppInfo(
      packageName: json['packageName'] as String? ?? '',
      activityName: json['activityName'] as String?,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'activityName': activityName,
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredAppInfo &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          activityName == other.activityName &&
          label == other.label;

  @override
  int get hashCode => Object.hash(packageName, activityName, label);

  @override
  String toString() =>
      'DiscoveredAppInfo(packageName: $packageName, activityName: $activityName, label: $label)';
}

/// Service bridge for launching native Android applications and managing headunit apps.
class NativeAppLauncherService {
  // Well-known automotive package & activity constants
  static const String pkgTlink5 = 'com.zjinnova.zlink';
  static const String actTlink5 = 'com.zjinnova.android.zlink.features.main.MainActivity';

  static const String pkgRadio = 'com.tw.radio';
  static const String actRadio = 'com.tw.radio.RadioActivity';

  static const String pkgDsp = 'com.tw.eq';
  static const String actDsp = 'com.tw.eq.DSPActivity';

  static const String pkgDvr = 'com.ankai.cardvr';
  static const String actDvr = 'com.ankai.cardvr.ui.MainActivity';

  static const String pkgBluetooth = 'com.tw.bt';
  static const String actBluetooth = 'com.tw.bt.ATBluetoothActivity';

  static const String pkgFan = 'com.tw.devicefan';
  static const String actFan = 'com.tw.devicefan.MainActivity';

  static const String pkgCarSettings = 'com.dofun.carsetting';
  static const String actCarSettings = 'com.dofun.carsetting.ui.MainActivity';

  // KeyCodes for automotive media controls
  static const int keyCodeMediaPlayPause = 85;
  static const int keyCodeMediaNext = 87;
  static const int keyCodeMediaPrevious = 88;

  final MethodChannel channel;

  NativeAppLauncherService({MethodChannel? channel})
      : channel = channel ?? const MethodChannel('com.example.redrive/storage');

  /// Retrieves current audio volume and stream status.
  Future<Map<String, dynamic>?> getAudioState() async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('getAudioState');
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Sets the media stream volume level (0 to maxVolume).
  Future<bool> setVolume(int volume) async {
    try {
      final result = await channel.invokeMethod<bool>('setVolume', {'volume': volume});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Adjusts volume up (direction = 1) or down (direction = -1).
  Future<Map<String, dynamic>?> adjustVolume(int direction) async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('adjustVolume', {
        'direction': direction,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Dispatches a media key event (Play/Pause, Next, Previous).
  Future<bool> sendMediaKey(int keyCode) async {
    try {
      final result = await channel.invokeMethod<bool>('sendMediaKey', {'keyCode': keyCode});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches an application by package name with an optional main activity name.
  Future<bool> launchApp(String packageName, {String? activityName}) async {
    try {
      final result = await channel.invokeMethod<bool>('launchApp', {
        'packageName': packageName,
        'activityName': activityName,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launch Apple CarPlay / Android Auto (TLink5 / ZLink).
  Future<bool> launchTlink() => launchApp(pkgTlink5, activityName: actTlink5);

  /// Whether the DVR session is currently active.
  bool isDvrActive = false;

  /// Launch native TS18 AM/FM Radio tuner.
  Future<bool> launchRadio() => launchApp(pkgRadio, activityName: actRadio);

  /// Launch DSP / Equalizer.
  Future<bool> launchDsp() => launchApp(pkgDsp, activityName: actDsp);

  /// Launch USB Dashcam / DVR app.
  Future<bool> launchDvr() async {
    final success = await launchApp(pkgDvr, activityName: actDvr);
    if (success) {
      isDvrActive = true;
    }
    return success;
  }

  /// Launch TS18 Bluetooth Phone & Audio UI.
  Future<bool> launchBluetooth() => launchApp(pkgBluetooth, activityName: actBluetooth);

  /// Launch Cooling Fan controller app.
  Future<bool> launchFan() => launchApp(pkgFan, activityName: actFan);

  /// Launch TS18 Factory & Vehicle Settings.
  Future<bool> launchSettings() => launchApp(pkgCarSettings, activityName: actCarSettings);

  /// Starts the DVR background recording service.
  Future<bool> startDvrRecording() async {
    try {
      final result = await channel.invokeMethod<bool>('startDvrService');
      if (result == true) {
        isDvrActive = true;
      }
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if the DVR background recording service is currently running.
  Future<bool> isDvrRecording() async {
    if (isDvrActive) return true;
    try {
      final result = await channel.invokeMethod<bool>('isDvrRunning');
      if (result == true) {
        isDvrActive = true;
      }
      return result ?? isDvrActive;
    } catch (_) {
      return isDvrActive;
    }
  }

  /// Queries all standard launchable applications installed on the headunit.
  Future<List<DiscoveredAppInfo>> getInstalledApps() async {
    try {
      final result = await channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((item) => DiscoveredAppInfo.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Sets the Topway TS18 native hardware PIP window for a target application.
  Future<bool> setPipWindow({
    required String packageName,
    String? activityName,
    int x = 740,
    int y = 68,
    int width = 510,
    int height = 564,
  }) async {
    try {
      final result = await channel.invokeMethod<bool>('setPipWindow', {
        'packageName': packageName,
        'activityName': activityName,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Releases the Topway TS18 hardware PIP window.
  Future<bool> releasePipWindow() async {
    try {
      final result = await channel.invokeMethod<bool>('releasePipWindow');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
