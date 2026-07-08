import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/beacon_data.dart';

class NotificationService {
  static const _channelId = 'beacon_detection';
  static const _channelName = 'Beacon detection';
  static const _notificationId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('ic_stat_beacon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: settings);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifications shown when the target iBeacon is detected.',
        importance: Importance.high,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    _initialized = true;
    debugPrint('[NotificationService] Initialized');
  }

  Future<void> showBeaconDetectedNotification(BeaconData beacon) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription:
          'Notifications shown when the target iBeacon is detected.',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Beacon detected',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: _notificationId,
      title: 'Beacon detected',
      body: 'M5 beacon is nearby (RSSI: ${beacon.rssi} dBm)',
      notificationDetails: details,
      payload: '${beacon.uuid}/${beacon.major}/${beacon.minor}',
    );

    debugPrint(
      '[NotificationService] Beacon notification shown: '
      '${beacon.uuid} ${beacon.major}.${beacon.minor} RSSI=${beacon.rssi}',
    );
  }
}
