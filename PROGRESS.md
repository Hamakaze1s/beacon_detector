# PROGRESS.md

Development log and key discoveries for beacon_detector.

## Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Dependencies & Permissions | Done |
| Phase 2 | Foreground BLE Scanner + iBeacon Detection | Done |
| Phase 3 | Background Foreground Service + Notifications | In Progress |
| Phase 4 | iOS Adaptation | Pending |

## Key Discoveries

### D1: `neverForLocation` breaks iBeacon detection on Pixel 7 (Android 14)

- **Date:** 2026-06-17
- **Finding:** Declaring `BLUETOOTH_SCAN` with `android:usesPermissionFlags="neverForLocation"` causes the Android BLE stack to **silently filter out non-connectable advertisements** (`ADV_NONCONN_IND`), which is the advertising type iBeacons use.
- **Symptom:** Other BLE devices (phones, smart lights) are detected; the iBeacon's MAC address never appears in scan results.
- **Verification:** nRF Connect (which requests `ACCESS_FINE_LOCATION`) detects the beacon; our app with `neverForLocation` does not. Removing `neverForLocation` and adding `ACCESS_FINE_LOCATION` resolves the issue.
- **Impact:** The strategy in AGENTS.md §4.1 (avoiding location permission via `neverForLocation`) is not viable on tested hardware.
- **Resolution:** Declare both `BLUETOOTH_SCAN` and `ACCESS_FINE_LOCATION` in the manifest; request both at runtime (matching nRF Connect behavior).

### D2: Permission `request()` triggered during `initState` is suppressed by Android

- **Date:** 2026-06-17
- **Finding:** Calling `Permission.bluetoothScan.request()` from within `initState()` (or any code path triggered during widget construction) causes Android to suppress the permission dialog and mark the permission as "do not ask again" (result code `IGNORED_DO_NOT_ASK_AGAIN` in `GrantPermissionsViewModel`).
- **Resolution:** Only `request()` permissions from user-triggered callbacks (button `onPressed`). Use `hasBlePermission()` (`status` query) during `initState` to check current state without prompting.

### D3: ESP32 BLE library `setManufacturerId(0x4C00)` produces wrong manufacturer key

- **Date:** 2026-06-17
- **Finding:** The beacon_emitter code uses `beacon.setManufacturerId(0x4C00)`. The ESP32 BLE library writes this as little-endian bytes `[0x00, 0x4C]`, which Android interprets as manufacturer ID `0x4C00` (19456), NOT the standard Apple ID `0x004C` (76).
- **Impact:** Hard-coding `0x004C` as the key in `manufacturerData[76]` would never match the M5Beacon. nRF Connect detects it because it shows all manufacturer data regardless of ID.
- **Resolution:** Detector iterates ALL manufacturer data entries and matches on iBeacon prefix (`02 15`) rather than hard-coding a manufacturer ID. Emitter should ideally use `setManufacturerId(0x004C)`.

### D4: Current M5Beacon advertises UUID bytes in reverse order

- **Date:** 2026-07-08
- **Finding:** Pixel 7 (Android 16 / API 36) scan logs show the M5Beacon payload UUID bytes as `e0 96 10 a7 f5 d0 60 b0 d2 48 fb df b5 6d c5 e2`, which parses to `e09610a7-f5d0-60b0-d248-fbdfb56dc5e2`.
- **Expected:** Project docs list `e2c56db5-dffb-48d2-b060-d0f5a71096e0`. The advertised bytes are the full byte-reversed form of that UUID.
- **Impact:** Target matching against only the documented UUID leaves the detected M5Beacon visible in the list, but `Target Beacon` remains `Not seen` and no notification is sent.
- **Resolution:** Detector temporarily accepts both the documented UUID and the currently advertised reversed UUID for target matching. The emitter firmware should be investigated so it advertises the canonical UUID byte order.

### D5: Android native foreground service prototype added

- **Date:** 2026-07-08
- **Scope:** Added an Android-only `ForegroundService` path for background BLE scanning, controlled from Flutter via a `MethodChannel`.
- **Design:** The native service owns its BLE scan, persistent scan-status notification, target iBeacon matching, enter/exit state, and detection notification. The existing Dart foreground scanner remains available for comparison.
- **Diagnostics:** Background scan logs are intentionally event-focused: target enter, low-frequency target-visible heartbeat, target exit, and notification shown. Per-advertisement logging is suppressed so lock-screen timing can be inspected from `logcat`.
- **Verification:** `flutter analyze`, `flutter test`, and `flutter build apk --debug` pass. Pixel 7 (Android 16 / API 36) confirms the foreground service remains active after switching to the launcher, keeps detecting the target beacon, and posts the detection notification. Lock-screen behavior is still pending.

## Tested Configurations

### Working (Pixel 7, Android 14)

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

```dart
// Permission request order
Permission.bluetoothScan.request();
Permission.locationWhenInUse.request();
Permission.notification.request();
```

### Not Working (Pixel 7, Android 14)

```xml
<!-- iBeacon advertisements are filtered out -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
```
