import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum BlePermissionState { granted, denied, permanentlyDenied }

class PermissionResult {
  final BlePermissionState ble;
  final PermissionStatus notification;

  const PermissionResult({required this.ble, required this.notification});

  bool get isGranted =>
      ble == BlePermissionState.granted && notification.isGranted;
}

class PermissionHelper {
  /// Request BLE and notification permissions.
  /// Tries BLUETOOTH_SCAN first (Android 12+), falls back to ACCESS_FINE_LOCATION.
  static Future<PermissionResult> requestBleAndNotificationPermissions() async {
    final ble = await _requestBlePermission();
    final notification = await _requestNotificationPermission();
    return PermissionResult(ble: ble, notification: notification);
  }

  static Future<BlePermissionState> _requestBlePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return BlePermissionState.granted;
    }

    if (Platform.isAndroid) {
      final scanResult = await _requestPermission(Permission.bluetoothScan);
      if (scanResult != BlePermissionState.granted) return scanResult;

      final locationResult = await _requestPermission(
        Permission.locationWhenInUse,
      );
      return locationResult;
    }

    if (Platform.isIOS) {
      // "Always" (not "When In Use") is required for CoreLocation region
      // monitoring to keep detecting the beacon while backgrounded/killed.
      return _requestPermission(Permission.locationAlways);
    }

    return BlePermissionState.granted;
  }

  static Future<BlePermissionState> _requestPermission(
    Permission permission,
  ) async {
    try {
      if (await permission.isGranted) return BlePermissionState.granted;
      final status = await permission.request();
      if (status.isGranted) return BlePermissionState.granted;
      if (status.isPermanentlyDenied) {
        return BlePermissionState.permanentlyDenied;
      }
      return BlePermissionState.denied;
    } catch (_) {
      // Permission not supported on this platform/version
      return BlePermissionState.denied;
    }
  }

  static Future<PermissionStatus> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      try {
        return await Permission.notification.request();
      } catch (_) {
        return PermissionStatus.denied;
      }
    }
    return PermissionStatus.granted;
  }

  static Future<bool> hasBlePermission() async {
    if (Platform.isAndroid) {
      final hasBluetoothScan = await Permission.bluetoothScan.isGranted;
      final hasFineLocation = await Permission.locationWhenInUse.isGranted;
      return hasBluetoothScan && hasFineLocation;
    }
    if (Platform.isIOS) {
      return await Permission.locationAlways.isGranted;
    }
    return true;
  }
}
