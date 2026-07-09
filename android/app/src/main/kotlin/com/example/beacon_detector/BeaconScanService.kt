package com.example.beacon_detector

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import java.util.Locale

class BeaconScanService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var scannerCallback: ScanCallback? = null
    private var targetInRange = false
    private var lastTargetSeenAt = 0L
    private var lastTargetHeartbeatAt = 0L
    private var lastNotificationAt = 0L

    private val exitCheck = Runnable {
        val now = System.currentTimeMillis()
        if (targetInRange && now - lastTargetSeenAt >= targetExitGraceMs) {
            targetInRange = false
            lastTargetHeartbeatAt = 0L
            Log.i(tag, "Target beacon left range")
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!hasRequiredPermissions()) {
            Log.w(tag, "Cannot start background scan: missing required permissions")
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForegroundService()
        startScan()
        isRunning = true
        return START_STICKY
    }

    override fun onDestroy() {
        stopScan()
        mainHandler.removeCallbacks(exitCheck)
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startAsForegroundService() {
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                foregroundNotificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(foregroundNotificationId, notification)
        }
    }

    private fun startScan() {
        if (scannerCallback != null) return

        val bluetoothManager = getSystemService(BluetoothManager::class.java)
        val scanner = bluetoothManager.adapter?.bluetoothLeScanner
        if (scanner == null) {
            Log.w(tag, "BLE scanner unavailable")
            stopSelf()
            return
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scannerCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                processScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                for (result in results) {
                    processScanResult(result)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(tag, "BLE scan failed: $errorCode")
            }
        }

        try {
            scanner.startScan(null, settings, scannerCallback)
            Log.i(tag, "Background BLE scan started")
        } catch (e: SecurityException) {
            Log.e(tag, "Missing BLE permission while starting scan", e)
            scannerCallback = null
            stopSelf()
        }
    }

    private fun stopScan() {
        val callback = scannerCallback ?: return
        val bluetoothManager = getSystemService(BluetoothManager::class.java)
        val scanner = bluetoothManager.adapter?.bluetoothLeScanner
        try {
            scanner?.stopScan(callback)
            Log.i(tag, "Background BLE scan stopped")
        } catch (e: SecurityException) {
            Log.w(tag, "Missing BLE permission while stopping scan", e)
        } finally {
            scannerCallback = null
        }
    }

    private fun processScanResult(result: ScanResult) {
        val manufacturerData = result.scanRecord?.manufacturerSpecificData ?: return
        for (i in 0 until manufacturerData.size()) {
            val data = manufacturerData.valueAt(i)
            val beacon = parseIBeacon(data) ?: continue

            if (isTargetBeacon(beacon)) {
                mainHandler.post {
                    handleTargetSeen(beacon, result.rssi)
                }
            }
        }
    }

    private fun parseIBeacon(data: ByteArray): ParsedBeacon? {
        if (data.size < 23) return null
        if ((data[0].toInt() and 0xff) != 0x02 || (data[1].toInt() and 0xff) != 0x15) {
            return null
        }

        val uuid = formatUuid(data, 2)
        val major = ((data[18].toInt() and 0xff) shl 8) or (data[19].toInt() and 0xff)
        val minor = ((data[20].toInt() and 0xff) shl 8) or (data[21].toInt() and 0xff)
        return ParsedBeacon(uuid, major, minor)
    }

    private fun formatUuid(data: ByteArray, offset: Int): String {
        val hex = StringBuilder(32)
        for (i in offset until offset + 16) {
            hex.append(String.format(Locale.US, "%02x", data[i]))
        }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-" +
            "${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}"
    }

    private fun isTargetBeacon(beacon: ParsedBeacon): Boolean {
        return (beacon.uuid == targetUuid || beacon.uuid == targetAdvertisedUuid) &&
            beacon.major == targetMajor &&
            beacon.minor == targetMinor
    }

    private fun handleTargetSeen(beacon: ParsedBeacon, rssi: Int) {
        val now = System.currentTimeMillis()
        val wasInRange = targetInRange
        val canNotify = !wasInRange && now - lastNotificationAt >= notificationCooldownMs

        targetInRange = true
        lastTargetSeenAt = now
        mainHandler.removeCallbacks(exitCheck)
        mainHandler.postDelayed(exitCheck, targetExitGraceMs)

        if (!wasInRange) {
            lastTargetHeartbeatAt = now
            Log.i(
                tag,
                "Target beacon entered range: ${beacon.uuid} " +
                    "${beacon.major}.${beacon.minor} RSSI=$rssi"
            )
        } else if (now - lastTargetHeartbeatAt >= targetHeartbeatLogIntervalMs) {
            lastTargetHeartbeatAt = now
            Log.i(
                tag,
                "Target beacon still visible: ${beacon.uuid} " +
                    "${beacon.major}.${beacon.minor} RSSI=$rssi"
            )
        }

        if (canNotify) {
            lastNotificationAt = now
            showBeaconDetectedNotification(beacon, rssi)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, scanStatusChannelId)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.ic_stat_beacon)
            .setContentTitle("Beacon scanning active")
            .setContentText("Scanning for nearby M5 beacons")
            .setContentIntent(appPendingIntent())
            .setOngoing(true)
            .build()
    }

    private fun showBeaconDetectedNotification(beacon: ParsedBeacon, rssi: Int) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, detectionChannelId)
        } else {
            Notification.Builder(this)
        }

        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_beacon)
            .setContentTitle("Beacon detected")
            .setContentText("M5 beacon is nearby (RSSI: $rssi dBm)")
            .setContentIntent(appPendingIntent())
            .setAutoCancel(true)
            .build()

        try {
            notificationManager.notify(detectionNotificationId, notification)
            Log.i(tag, "Beacon notification shown: ${beacon.uuid} ${beacon.major}.${beacon.minor} RSSI=$rssi")
        } catch (e: SecurityException) {
            Log.e(tag, "Missing notification permission while showing beacon notification", e)
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        notificationManager.createNotificationChannel(
            NotificationChannel(
                scanStatusChannelId,
                "Beacon scan status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent notification shown while background beacon scanning is active."
            }
        )

        notificationManager.createNotificationChannel(
            NotificationChannel(
                detectionChannelId,
                "Beacon detection",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications shown when the target iBeacon is detected."
            }
        )
    }

    private fun appPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    private fun hasRequiredPermissions(): Boolean {
        val hasLocation = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val hasScan = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
            PackageManager.PERMISSION_GRANTED
        val hasConnect = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        return hasLocation && hasScan && hasConnect
    }

    private val notificationManager: NotificationManager
        get() = getSystemService(NotificationManager::class.java)

    private data class ParsedBeacon(
        val uuid: String,
        val major: Int,
        val minor: Int
    )

    companion object {
        private const val tag = "BeaconScanService"
        private const val scanStatusChannelId = "beacon_scan_status"
        private const val detectionChannelId = "beacon_detection"
        private const val foregroundNotificationId = 2001
        private const val detectionNotificationId = 1001
        private const val targetUuid = "e2c56db5-dffb-48d2-b060-d0f5a71096e0"
        private const val targetAdvertisedUuid = "e09610a7-f5d0-60b0-d248-fbdfb56dc5e2"
        private const val targetMajor = 1
        private const val targetMinor = 1
        private const val targetExitGraceMs = 15_000L
        private const val targetHeartbeatLogIntervalMs = 60_000L
        private const val notificationCooldownMs = 30_000L

        @Volatile
        var isRunning: Boolean = false
            private set
    }
}
