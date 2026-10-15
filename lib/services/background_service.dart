import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:redrive/services/logging/log_service.dart';

Future<void> initializeBackgroundService() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }
  final service = FlutterBackgroundService();

  // Android notifications
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'redrive_foreground', // id
    'Foreground Service', // title
    description: 'Keeps ReDrive trip data collecting in the background.', // description
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'redrive_foreground',
      initialNotificationTitle: 'ReDrive Telemetry',
      initialNotificationContent: 'Waiting for OBD connection...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await LogService.init();
  LogService.i('BackgroundService started from system wake/boot', tag: 'Service');

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('updateNotification').listen((event) {
    if (event != null && service is AndroidServiceInstance) {
      final title = event['title'] as String? ?? 'ReDrive Active';
      final content = event['content'] as String? ?? 'Collecting telemetry...';
      service.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    }
  });
}

/// Utility function for the primary isolate to update the ongoing notification.
void updateServiceNotification({
  required String title,
  required String content,
}) {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  FlutterBackgroundService().invoke('updateNotification', {
    'title': title,
    'content': content,
  });
}
