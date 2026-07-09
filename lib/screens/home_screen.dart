import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/beacon_data.dart';
import '../services/background_beacon_service.dart';
import '../services/beacon_scanner.dart';
import '../services/notification_service.dart';
import '../utils/permission_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _targetExitGrace = Duration(seconds: 15);
  static const _notificationCooldown = Duration(seconds: 30);

  final BeaconScanner _scanner = BeaconScanner();
  final BackgroundBeaconService _backgroundService = BackgroundBeaconService();
  final NotificationService _notifications = NotificationService();
  final List<BeaconData> _beacons = [];

  BlePermissionState _blePermission = BlePermissionState.denied;
  PermissionStatus _notificationPermission = PermissionStatus.denied;
  bool _isScanning = false;
  bool _isBackgroundScanning = false;
  bool _isBluetoothOn = true;
  bool _targetInRange = false;
  DateTime? _lastTargetSeen;
  DateTime? _lastNotificationAt;
  String? _errorMessage;

  StreamSubscription<List<BeaconData>>? _beaconSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _targetExitTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _notifications.initialize();
    } catch (e) {
      debugPrint('[HomeScreen] Notification initialization failed: $e');
    }

    await _checkPermissionStatus();
    await _refreshBackgroundScanState();

    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        _isBluetoothOn = state == BluetoothAdapterState.on;
      });
    });
  }

  Future<void> _refreshBackgroundScanState() async {
    try {
      final running = await _backgroundService.isRunning();
      if (!mounted) return;
      setState(() => _isBackgroundScanning = running);
    } catch (e) {
      debugPrint('[HomeScreen] Background service state check failed: $e');
    }
  }

  Future<void> _checkPermissionStatus() async {
    final hasBle = await PermissionHelper.hasBlePermission();
    final notificationStatus = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _blePermission = hasBle
          ? BlePermissionState.granted
          : BlePermissionState.denied;
      _notificationPermission = notificationStatus;
    });
  }

  Future<void> _requestPermissions() async {
    final result =
        await PermissionHelper.requestBleAndNotificationPermissions();
    if (!mounted) return;
    setState(() {
      _blePermission = result.ble;
      _notificationPermission = result.notification;
    });

    if (result.ble == BlePermissionState.permanentlyDenied) {
      _showPermanentlyDeniedDialog();
    }
  }

  void _showPermanentlyDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Bluetooth scanning permission was denied permanently. '
          'Please grant it manually in Settings → Apps → beacon_detector → Permissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await _scanner.stopScan();
      if (!mounted) return;

      _beaconSub?.cancel();
      _beaconSub = null;
      _scanningSub?.cancel();
      _scanningSub = null;
      _targetExitTimer?.cancel();
      _targetInRange = false;
      setState(() => _isScanning = false);
      return;
    }

    setState(() => _errorMessage = null);

    try {
      await _beaconSub?.cancel();
      _beaconSub = _scanner.beacons.listen((list) {
        if (!mounted) return;
        _handleBeaconUpdate(list);
      });

      await _scanningSub?.cancel();
      _scanningSub = _scanner.isScanningStream.listen((scanning) {
        if (!mounted) return;
        setState(() => _isScanning = scanning);
      });

      await _scanner.startScan();
    } catch (e) {
      await _beaconSub?.cancel();
      await _scanningSub?.cancel();
      _beaconSub = null;
      _scanningSub = null;
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _toggleBackgroundScan() async {
    setState(() => _errorMessage = null);

    try {
      if (_isBackgroundScanning) {
        await _backgroundService.stop();
        if (!mounted) return;
        setState(() => _isBackgroundScanning = false);
        return;
      }

      if (_isScanning) {
        await _scanner.stopScan();
        await _beaconSub?.cancel();
        await _scanningSub?.cancel();
        _beaconSub = null;
        _scanningSub = null;
        _targetExitTimer?.cancel();
        _targetInRange = false;
      }

      await _backgroundService.start();
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _isBackgroundScanning = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  void _handleBeaconUpdate(List<BeaconData> list) {
    final target = _latestTargetBeacon(list);

    setState(() {
      _beacons
        ..clear()
        ..addAll(list);
    });

    if (target != null) {
      _handleTargetSeen(target);
    }
  }

  BeaconData? _latestTargetBeacon(List<BeaconData> list) {
    BeaconData? latest;
    final now = DateTime.now();
    for (final beacon in list) {
      if (!BeaconScanner.isTargetBeacon(beacon)) continue;
      if (now.difference(beacon.lastSeen) > _targetExitGrace) continue;
      if (latest == null || beacon.lastSeen.isAfter(latest.lastSeen)) {
        latest = beacon;
      }
    }
    return latest;
  }

  void _handleTargetSeen(BeaconData beacon) {
    final now = DateTime.now();
    final canNotify =
        !_targetInRange &&
        (_lastNotificationAt == null ||
            now.difference(_lastNotificationAt!) >= _notificationCooldown);

    setState(() {
      _lastTargetSeen = beacon.lastSeen;
      _targetInRange = true;
      if (canNotify) {
        _lastNotificationAt = now;
      }
    });
    _scheduleTargetExitCheck();

    if (!canNotify) {
      return;
    }

    _notifications.showBeaconDetectedNotification(beacon).catchError((
      Object e,
    ) {
      debugPrint('[HomeScreen] Failed to show beacon notification: $e');
      if (!mounted) return;
      setState(() => _errorMessage = 'Notification failed: $e');
    });
  }

  void _scheduleTargetExitCheck() {
    _targetExitTimer?.cancel();
    _targetExitTimer = Timer(_targetExitGrace, () {
      final lastSeen = _lastTargetSeen;
      if (lastSeen == null || !mounted) return;

      final isStillFresh =
          DateTime.now().difference(lastSeen) < _targetExitGrace;
      if (isStillFresh) {
        _scheduleTargetExitCheck();
        return;
      }

      setState(() => _targetInRange = false);
      debugPrint('[HomeScreen] Target beacon left range');
    });
  }

  @override
  void dispose() {
    _scanner.dispose();
    _beaconSub?.cancel();
    _scanningSub?.cancel();
    _adapterSub?.cancel();
    _targetExitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beacon Detector')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildStatusCards(),
            const SizedBox(height: 12),
            _buildActionArea(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _buildBeaconList()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCards() {
    return Column(
      children: [
        _statusRow(
          icon: _blePermission == BlePermissionState.granted
              ? Icons.check_circle
              : _blePermission == BlePermissionState.permanentlyDenied
              ? Icons.error
              : Icons.warning,
          label: 'BLE Permission',
          value: _blePermission.name,
          color: _blePermission == BlePermissionState.granted
              ? Colors.green
              : Colors.orange,
        ),
        const SizedBox(height: 4),
        _statusRow(
          icon: _notificationPermission.isGranted
              ? Icons.notifications_active
              : Icons.notifications_off,
          label: 'Notifications',
          value: _notificationPermission.name,
          color: _notificationPermission.isGranted
              ? Colors.green
              : Colors.orange,
        ),
        const SizedBox(height: 4),
        _statusRow(
          icon: _isBluetoothOn
              ? Icons.bluetooth_connected
              : Icons.bluetooth_disabled,
          label: 'Bluetooth',
          value: _isBluetoothOn ? 'On' : 'Off',
          color: _isBluetoothOn ? Colors.blue : Colors.red,
        ),
        const SizedBox(height: 4),
        _statusRow(
          icon: _targetInRange ? Icons.place : Icons.place_outlined,
          label: 'Target Beacon',
          value: _targetStatusText(),
          color: _targetInRange ? Colors.green : Colors.grey,
        ),
        const SizedBox(height: 4),
        _statusRow(
          icon: _isScanning ? Icons.radar : Icons.radar,
          label: 'Scanning',
          value: _isScanning ? 'Active' : 'Idle',
          color: _isScanning ? Colors.green : Colors.grey,
        ),
        const SizedBox(height: 4),
        _statusRow(
          icon: _isBackgroundScanning ? Icons.sensors : Icons.sensors_off,
          label: 'Background Scan',
          value: _isBackgroundScanning ? 'Active' : 'Idle',
          color: _isBackgroundScanning ? Colors.green : Colors.grey,
        ),
      ],
    );
  }

  Widget _statusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        trailing: Text(value),
        dense: true,
      ),
    );
  }

  Widget _buildActionArea() {
    final needsPermissions =
        _blePermission != BlePermissionState.granted ||
        !_notificationPermission.isGranted;

    if (needsPermissions) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.security),
              label: const Text('Grant Permissions'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildForegroundActionRow(),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _toggleBackgroundScan,
            icon: Icon(_isBackgroundScanning ? Icons.stop : Icons.sensors),
            label: Text(
              _isBackgroundScanning
                  ? 'Stop Background Scan'
                  : 'Start Background Scan',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForegroundActionRow() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _toggleScan,
            icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
            label: Text(_isScanning ? 'Stop Scan' : 'Start Scan'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _scanner.clear(),
          icon: const Icon(Icons.clear_all),
          tooltip: 'Clear list',
        ),
      ],
    );
  }

  Widget _buildBeaconList() {
    if (_beacons.isEmpty) {
      return Center(
        child: Text(
          _isScanning
              ? 'Scanning... No beacons found yet.\nEnsure the emitter is nearby.'
              : 'Press "Start Scan" to discover iBeacons.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: _beacons.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final beacon = _beacons[index];
        return _beaconTile(beacon);
      },
    );
  }

  Widget _beaconTile(BeaconData beacon) {
    final distance = _estimateDistance(
      beacon.rssi,
      beacon.measuredPower ?? -58,
    );
    return ListTile(
      leading: CircleAvatar(child: Text('${beacon.major}.${beacon.minor}')),
      title: Text(
        beacon.deviceName ?? 'iBeacon',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'UUID: ${beacon.uuid.substring(0, 8)}...\n'
        'RSSI: ${beacon.rssi} dBm  |  ~${distance.toStringAsFixed(1)} m',
      ),
      trailing: Text(
        _formatTimeAgo(beacon.lastSeen),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// Rough distance estimate using the free-space path loss model.
  double _estimateDistance(int rssi, int measuredPower) {
    if (rssi == 0) return -1;
    final ratio = rssi / measuredPower;
    if (ratio < 1.0) {
      return ratio * ratio;
    }
    return (0.89976 * ratio * ratio * ratio) + 0.111;
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 5) return 'now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String _targetStatusText() {
    if (_targetInRange) return 'In range';
    if (_lastTargetSeen == null) return 'Not seen';
    return 'Last ${_formatTimeAgo(_lastTargetSeen!)}';
  }
}
