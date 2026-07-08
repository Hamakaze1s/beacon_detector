import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/beacon_data.dart';

class BeaconScanner {
  // Standard iBeacon prefix: 0x02 (subtype), 0x15 (remaining length = 21)
  static const ibeaconPrefix = [0x02, 0x15];
  static const targetUuid = 'e2c56db5-dffb-48d2-b060-d0f5a71096e0';
  // The current M5Stack emitter advertises the same UUID bytes in reverse
  // order. Keep matching it here so detector-side notification testing can
  // continue while the emitter firmware is investigated.
  static const targetAdvertisedUuid = 'e09610a7-f5d0-60b0-d248-fbdfb56dc5e2';
  static const targetMajor = 1;
  static const targetMinor = 1;

  final _beaconsController = StreamController<List<BeaconData>>.broadcast();
  final _isScanningController = StreamController<bool>.broadcast();

  Stream<List<BeaconData>> get beacons => _beaconsController.stream;
  Stream<bool> get isScanningStream => _isScanningController.stream;

  final Map<String, BeaconData> _detectedBeacons = {};
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  static bool isTargetBeacon(BeaconData beacon) {
    final uuid = beacon.uuid.toLowerCase();
    return (uuid == targetUuid || uuid == targetAdvertisedUuid) &&
        beacon.major == targetMajor &&
        beacon.minor == targetMinor;
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw Exception('Bluetooth not supported on this device');
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw Exception('Bluetooth is turned off');
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen(_onScanResults);
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      continuousDivisor: 1,
      androidScanMode: AndroidScanMode.lowLatency,
      androidUsesFineLocation: true,
    );

    _isScanning = true;
    _isScanningController.add(true);

    debugPrint('[BeaconScanner] Scan started');
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;

    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    _isScanningController.add(false);

    debugPrint('[BeaconScanner] Scan stopped');
  }

  void _onScanResults(List<ScanResult> results) {
    debugPrint('[BeaconScanner] Got ${results.length} scan result(s)');

    for (final result in results) {
      _processScanResult(result);
    }
    _beaconsController.add(List.unmodifiable(_detectedBeacons.values));
  }

  void _processScanResult(ScanResult result) {
    final ad = result.advertisementData;
    final name = ad.advName.isNotEmpty ? ad.advName : '(no name)';

    debugPrint(
      '[BeaconScanner] Device: $name'
      ' | RSSI: ${result.rssi}'
      ' | RemoteId: ${result.device.remoteId.str}'
      ' | Manufacturer keys: '
      '${ad.manufacturerData.keys.map((k) => k.toRadixString(16)).toList()}',
    );

    // Scan ALL manufacturer data entries for iBeacon pattern
    for (final entry in ad.manufacturerData.entries) {
      final data = entry.value;
      debugPrint(
        '[BeaconScanner]   -> Manufacturer ${entry.key.toRadixString(16)}'
        ' data (${data.length} bytes): '
        '${data.take(23).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      if (data.length < 23) {
        debugPrint('[BeaconScanner]   -> Too short for iBeacon (< 23 bytes)');
        continue;
      }

      if (data[0] != ibeaconPrefix[0] || data[1] != ibeaconPrefix[1]) {
        debugPrint(
          '[BeaconScanner]   -> Not iBeacon: prefix=${data[0].toRadixString(16)}'
          ' ${data[1].toRadixString(16)}',
        );
        continue;
      }

      final uuid = _formatUuid(data.sublist(2, 18));
      final major = (data[18] << 8) | data[19];
      final minor = (data[20] << 8) | data[21];
      final measuredPower = data[22] >= 128 ? data[22] - 256 : data[22];

      debugPrint(
        '[BeaconScanner]   -> iBeacon detected! UUID=$uuid '
        'Major=$major Minor=$minor RSSI=${result.rssi}',
      );

      final key = '${result.device.remoteId.str}_${uuid}_${major}_$minor';
      final previous = _detectedBeacons[key];
      final now = DateTime.now();

      if (previous == null) {
        _detectedBeacons[key] = BeaconData(
          deviceId: result.device.remoteId.str,
          deviceName: name,
          uuid: uuid,
          major: major,
          minor: minor,
          rssi: result.rssi,
          measuredPower: measuredPower,
          lastSeen: now,
        );
      } else {
        _detectedBeacons[key] = previous.copyWith(
          deviceName: name,
          rssi: (previous.rssi - result.rssi).abs() > 1
              ? result.rssi
              : previous.rssi,
          measuredPower: measuredPower,
          lastSeen: now,
        );
      }
    }
  }

  void clear() {
    _detectedBeacons.clear();
    _beaconsController.add(List.unmodifiable(_detectedBeacons.values));
  }

  void dispose() {
    _scanSubscription?.cancel();
    _beaconsController.close();
    _isScanningController.close();
  }
}

String _formatUuid(List<int> bytes) {
  return '${_toHex(bytes.sublist(0, 4))}-'
      '${_toHex(bytes.sublist(4, 6))}-'
      '${_toHex(bytes.sublist(6, 8))}-'
      '${_toHex(bytes.sublist(8, 10))}-'
      '${_toHex(bytes.sublist(10, 16))}';
}

String _toHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
