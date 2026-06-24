# PROGRESS.md

Development log and key discoveries for beacon_detector.

## Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Dependencies & Permissions | Done |
| Phase 2 | Foreground BLE Scanner + iBeacon Detection | Done |
| Phase 3 | Background Foreground Service + Notifications | Pending |
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
