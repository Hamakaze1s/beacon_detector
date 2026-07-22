# PROGRESS.md

Development log and key discoveries for beacon_detector.

## Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Dependencies & Permissions | Done |
| Phase 2 | Foreground BLE Scanner + iBeacon Detection | Done |
| Phase 3 | Background Foreground Service + Notifications | In Progress |
| Phase 4 | iOS Adaptation | In Progress |

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

### D6: iOS CoreBluetooth hides iBeacon manufacturer data - CoreLocation required

- **Date:** 2026-07-22
- **Finding:** Apple's CoreBluetooth deliberately masks the iBeacon-formatted manufacturer data (Apple company ID `0x004C`, subtype `0x02 0x15`) from third-party apps. The raw-advertisement scanning in `BeaconScanner` (via `flutter_blue_plus`) that works on Android cannot read UUID/major/minor on iOS - it detects nothing, foreground or background, no matter the permissions granted.
- **Impact:** iOS requires a fundamentally different detection mechanism from Android; there is no cross-platform BLE-scanning code path.
- **Resolution:** `BeaconScanner` now branches on `Platform.isIOS`. Android keeps the existing `flutter_blue_plus` raw scan unchanged. iOS uses the `dchs_flutter_beacon` package (Apache-2.0, actively maintained) as a thin wrapper around `CLLocationManager`/`CLBeaconRegion` ranging. Both paths feed the same `BeaconData` model and `isTargetBeacon()` matching.
- **Side benefit:** CoreLocation region monitoring is designed by Apple to wake the app in the background/killed state on its own, unlike Android which needs a manual foreground service (D5). iOS's "Start Background Scan" story may end up simpler than Android's once implemented.
- **Required iOS permission change:** "Always" location authorization (not "When In Use") plus the `location` `UIBackgroundModes` entry are required for background detection; `Info.plist` and `permission_helper.dart` were updated accordingly.

### D7: Codemagic iOS automatic signing needs an Admin-role API key + a supplied private key

- **Date:** 2026-07-22
- **Finding:** On a brand-new Apple Developer account with zero existing certificates, the declarative `ios_signing` block in `codemagic.yaml` only *fetches* existing certificates/profiles - it does not create them. Switching to an explicit `app-store-connect fetch-signing-files --create` script step is required to generate a new Apple Distribution certificate + App Store provisioning profile.
- **Further finding:** Creating certificates via the App Store Connect API requires the API key to have the **Admin** role - the "App Manager" role Codemagic's own docs recommend for general use is not sufficient and fails with "No matching profiles found for bundle identifier ... and distribution type app_store".
- **Further finding:** Even with an Admin-role key, `--create` still fails ("Cannot save Signing Certificates without certificate private key") unless a `CERTIFICATE_PRIVATE_KEY` secret env var (a PEM RSA private key) is supplied - Codemagic needs it to build the CSR itself.
- **Resolution:** Generate an RSA private key, store it as a secure Codemagic env var `CERTIFICATE_PRIVATE_KEY` in the `appstore_credentials` group, and use an Admin-role App Store Connect API key integration. See `codemagic.yaml`'s `ios-testflight` workflow.

### D8: TestFlight Internal Testing group rejects explicit build assignment when automatic distribution is on

- **Date:** 2026-07-22
- **Finding:** A newly created Internal Testing group defaults to "Automatically distribute builds" enabled. With that setting on, Codemagic's `publishing.app_store_connect.beta_groups` explicitly assigning the upload to that group fails: "Failed to add a build to '...' beta group. Builds cannot be assigned to this internal group. - Cannot add internal group to a build."
- **Resolution:** Drop `beta_groups` from `codemagic.yaml` entirely and rely on the group's own automatic distribution instead of an explicit API assignment. Keep `submit_to_testflight: true`.

### D9: App Store Connect rejects re-uploading the same (version, build number)

- **Date:** 2026-07-22
- **Finding:** Uploading a build fails with "The provided entity includes an attribute with a value that has already been used" if `pubspec.yaml`'s `version: X.Y.Z+N` build number `N` was already used for a prior successful upload of this bundle ID.
- **Resolution:** Bump the number after `+` in `pubspec.yaml` before every new TestFlight upload.

### D10: Kotlin incremental compiler crashes on Windows when project and pub cache are on different drives

- **Date:** 2026-07-22
- **Finding:** Once a plugin ships real Kotlin sources for Android (`dchs_flutter_beacon`, added for D6), `flutter build apk` fails during `compileDebugKotlin` on this Windows dev machine: `RelocatableFileToPathConverter`/`relativeTo()` can't compute a relative path between `D:\Projects\beacon_detector` (project) and `C:\Users\...\Pub\Cache\...` (pub cache) since they're on different drive letters.
- **Impact:** Local-machine-only; Codemagic's macOS runner has no drive-letter concept and is unaffected.
- **Resolution:** Set `kotlin.incremental=false` in `android/gradle.properties`.

### D11: `dchs_flutter_beacon`'s `initializeAndCheckScanning` always reports failure on iOS

- **Date:** 2026-07-22
- **Finding:** On the success path (Location Services on, Bluetooth on, "Always" location authorized), the native iOS side resolves the method call with `nil` instead of an explicit `true`/`1`. The plugin's own Dart-side `_parseBoolResult` treats anything that isn't a `bool` or `int` as `false`, so `initializeAndCheckScanning` returns `false` unconditionally on the success path too - not just on real failures.
- **Symptom:** Tapping "Start Scan" on iOS always threw "Beacon ranging not available (check Location Services, Bluetooth, and Always-location permission)" even after granting Always location permission.
- **Resolution:** `BeaconScanner._startIosRanging()` awaits `initializeAndCheckScanning` only for its side effect (it drives the permission/init flow) and no longer gates startup on its return value.

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
