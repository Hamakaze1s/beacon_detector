# AGENTS.md

## 0. Purpose & Scope

This file provides project-level guidance for AI coding agents working on the **beacon_detector** project. It applies to all files under this repository root. For current development status and discovered issues, see [PROGRESS.md](PROGRESS.md).

When real-time user instructions conflict with this file, the user's instructions take precedence.

## 1. Project Overview

- **Type:** Flutter (Dart) mobile app
- **Platforms:** Android (primary first target), iOS (secondary)
- **Flutter SDK:** ^3.12.2 (as of pubspec.yaml)
- **Entry point:** `lib/main.dart`
- **Role:** Phone-side iBeacon detector + push notification client. Validates background BLE scanning and notification workflows before merging into the parent M5Beacon project.

## 2. Reference Emitter

The beacon being detected is emitted by the sibling project at `../beacon_emitter/`.

- **Emitter hardware:** M5Stack CoreS3 (ESP32-S3)
- **UUID:** `e2c56db5-dffb-48d2-b060-d0f5a71096e0`
- **Major:** `1`, **Minor:** `1`
- **Measured RSSI at 1m:** `-58` dBm

The emitter can be started/stopped via its Button A; use it as the test fixture when validating detector changes.

## 3. Architectural Constraints

### 3.1 Future Migration to M5Beacon

This project is a **stepping stone**. The beacon scanning and notification logic will eventually be migrated into the parent [M5Beacon](https://github.com/user/M5Beacon) project.

Therefore:

- **Keep the scanner service self-contained** so it can be extracted as a reusable module.
- **Avoid proprietary or closed-source plugins** — prefer MIT/Apache-2.0 licensed packages.
- **Document platform-specific workarounds** (e.g., Android foreground service requirements, iOS CoreBluetooth background mode limits) in code comments so the M5Beacon team is aware of them.
- **Match the M5Beacon coding conventions** where possible (comment language, naming style). Use **English** for comments in this standalone validation phase.

### 3.2 Minimum Android Version

`minSdk` is set to `flutter.minSdkVersion` in `android/app/build.gradle.kts`. This resolves to API 21+ by Flutter default. However, **Android 10+ (API 29)** is the realistic minimum for BLE scanning because background location/BT permissions differ significantly below that. When adding runtime permission logic, target API 29+ paths.

## 4. Key Risky Areas (Permission & Background)

These are the most likely failure points. Changes touching these areas MUST be tested on a physical device (not just the emulator).

### 4.1 Android Permissions

| Permission | Purpose | Required From |
|------------|---------|---------------|
| `BLUETOOTH_SCAN` | Discover BLE devices | Android 12+ (API 31+) |
| `BLUETOOTH_CONNECT` | (Not needed for passive scan, but required by some plugins) | Android 12+ |
| `ACCESS_FINE_LOCATION` | Required for BLE scanning on Android < 12 | All versions |
| `POST_NOTIFICATIONS` | Show push notifications | Android 13+ (API 33+) |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` or `FOREGROUND_SERVICE_DATA_SYNC` | Keep BLE scan alive in background | Android 9+ |

**Critical rule:** On Android 13+, when `BLUETOOTH_SCAN` is declared with `android:usesPermissionFlags="neverForLocation"`, location permission is NOT required — in theory. **In practice:** on Pixel 7 (Android 14), this flag causes non-connectable BLE advertisements (including iBeacon) to be silently filtered out. See [PROGRESS.md §D1](PROGRESS.md) for details. Current working configuration uses both `BLUETOOTH_SCAN` and `ACCESS_FINE_LOCATION` without `neverForLocation`.

### 4.2 iOS Background BLE

- `CoreBluetooth` background mode must be declared in `Info.plist` (`bluetooth-central`).
- iOS throttles BLE scan results in the background; iBeacon ranging may not fire in real time when the app is suspended.
- State preservation + restoration (`CBCentralManagerDelegate`) is the recommended approach but has limitations.

### 4.3 Foreground Service (Android)

The scanner **must** run as a `ForegroundService` to continue scanning when the app is backgrounded. This requires:

1. A persistent notification (e.g., "Scanning for beacons...").
2. The notification channel must be created before starting the service.
3. On Android 14+, the foreground service type must be explicitly declared (`dataSync` or `location`).

## 5. Dependency Guidelines

### 5.1 Recommended Packages

| Package | Purpose | License |
|---------|---------|---------|
| `flutter_blue_plus` | Cross-platform BLE scanning (most actively maintained) | MIT |
| `flutter_local_notifications` | Local push notifications | BSD-3-Clause |
| `permission_handler` | Unified runtime permission requests | MIT |

### 5.2 When Adding a New Package

- Check the license is permissive (MIT/Apache-2.0/BSD preferred).
- Verify it supports both Android and iOS.
- Run `flutter pub add <package>` — do NOT manually edit pubspec.yaml dependency lines.
- Mention the new dependency in the change log.

## 6. Development Environment & Commands

| Action | Command |
|--------|---------|
| Install dependencies | `flutter pub get` |
| Run on connected device | `flutter run` |
| Run on Android emulator | `flutter run -d android` |
| Run analyzer | `flutter analyze` |
| Run tests | `flutter test` |
| Clean build cache | `flutter clean` |

## 7. Code Style & Conventions

### 7.1 General Rules

- **No unrelated refactoring** — only modify code directly relevant to the task.
- **Comment language:** English.
- **Log messages:** English (debug console output).
- Use `dart format` style (80-char preferred, but not enforced at the cost of readability).

### 7.2 Naming

- **Classes/Enums/Types:** `PascalCase`
- **Variables/Functions:** `camelCase`
- **File names:** `snake_case.dart`
- **Constants:** `camelCase` (Dart convention; avoid SCREAMING_SNAKE_CASE unless it's a well-known constant like a UUID string)

### 7.3 Project Structure

```
beacon_detector/
├── lib/
│   ├── main.dart
│   ├── screens/
│   ├── services/
│   ├── models/
│   └── utils/
├── android/
├── ios/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
├── AGENTS.md
├── PROGRESS.md
└── .gitignore
```

Do NOT create top-level folders outside this scheme without user approval.

## 8. Pre-Commit Verification

Before completing any task, run:

1. `flutter analyze` — must pass with no errors.
2. `flutter test` — all existing tests must pass.
3. If permissions were changed: verify on a **physical Android device** and note the API level tested.
4. If BLE logic was changed: confirm detection works with the `beacon_emitter` running.

If any check is skipped, explicitly state which and why.

## 9. Change Log Format

Upon completing a task, provide:

- **What was changed** (files and lines)
- **Why it was changed** (rationale)
- **Verification performed** (commands and results)
- **Skipped checks** (and reasons)

## 10. Prohibited

- Do not delete key functionality without explicit user request.
- Do not upgrade the Flutter SDK or minSdk version without discussion.
- Do not introduce large-scale formatting changes unrelated to the task.
- Do not fabricate test results; mark unverified items clearly.
- Do not add packages that are GPL-licensed or otherwise incompatible with the parent M5Beacon project's future licensing.
