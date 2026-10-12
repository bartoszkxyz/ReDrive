import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';

class ObdBackgroundProxy {
  static final ObdBackgroundProxy _instance = ObdBackgroundProxy._internal();
  factory ObdBackgroundProxy() => _instance;
  ObdBackgroundProxy._internal();

  final _telemetryController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get telemetry => _telemetryController.stream;

  void init() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterBackgroundService().on('telemetry_update').listen((event) {
      if (event != null) {
        _telemetryController.add(event.cast<String, dynamic>());
      }
    });
  }

  void connect(String macAddress) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterBackgroundService().invoke('connect', {'mac': macAddress});
  }

  void disconnect() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterBackgroundService().invoke('disconnect');
  }

  void startTrip() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterBackgroundService().invoke('start_trip');
  }

  void stopTrip() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterBackgroundService().invoke('stop_trip');
  }
}
