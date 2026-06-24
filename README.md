# Beacon Detector

A Flutter mobile app (Android/iOS) that passively scans for iBeacon advertisements and triggers local push notifications when a known beacon enters range. Built to validate background BLE scanning and notification workflows.

## Purpose

This is the **phone-side companion** to the [beacon_emitter](../beacon_emitter/) firmware project (M5Stack CoreS3 iBeacon). Together, they form an end-to-end test harness for:

1. **Permissions** — Bluetooth, location, and notification permissions on Android 12+/iOS
2. **Background BLE scanning** — detecting iBeacons while the app is in the background or killed
3. **Local push notifications** — alerting the user when a beacon comes into range

Once the critical path (permissions + background detection + notifications) is validated on both platforms, the iBeacon scanning logic will be integrated into the parent [M5Beacon](https://github.com/user/M5Beacon) workflow.

## Target Platforms

| Platform | Min Version | Notes |
|----------|-------------|-------|
| Android  | API 29 (Android 10) | BLE permissions are strictest here; 12+ requires runtime BLUETOOTH_SCAN |
| iOS      | 16+          | Background BLE is heavily restricted by CoreBluetooth |

## Architecture

```
lib/
├── main.dart               # App entry, MaterialApp, home screen
├── screens/
│   └── home_screen.dart    # UI: scan status, beacon list, permissions status
├── services/
│   ├── beacon_scanner.dart # BLE scanning + iBeacon parsing (platform-channel or plugin)
│   └── notification_service.dart # Local push notifications
├── models/
│   └── beacon_data.dart    # Parsed iBeacon packet model
└── utils/
    └── permission_helper.dart # Unified permission request for Android + iOS
```

## Beacon Configuration (matching emitter)

| Parameter | Value |
|-----------|-------|
| UUID      | `e2c56db5-dffb-48d2-b060-d0f5a71096e0` |
| Major     | 1 |
| Minor     | 1 |

## Planned Feature Milestones

### M1 — Permissions & Foreground Scan (Android-first)
- Declare required permissions in `AndroidManifest.xml`
- Request runtime permissions (Bluetooth + location + notifications)
- Scan for iBeacons in foreground using `flutter_blue_plus`
- Match against known beacon UUID and display in UI

### M2 — Background Detection & Notifications
- Keep BLE scanning alive with an Android Foreground Service
- Trigger `flutter_local_notifications` when beacon enters/exits range
- iOS background BLE config (CoreBluetooth state preservation)

### M3 — Integration Prep
- Extract scanner into a reusable service module
- Validate behaviour matches M5Beacon's expected workflow
- Document platform-specific limitations

## Quick Start

```bash
flutter pub get
flutter run
```

## License

MIT
