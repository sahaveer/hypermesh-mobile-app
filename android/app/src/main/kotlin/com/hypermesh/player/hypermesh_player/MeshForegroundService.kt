package com.hypermesh.player.hypermesh_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class MeshForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "hypermesh_background_mesh"
        const val NOTIFICATION_ID = 9021
        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_FILES_COUNT = "EXTRA_FILES_COUNT"
        const val EXTRA_PEERS_COUNT = "EXTRA_PEERS_COUNT"

        var isRunning: Boolean = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        when (action) {
            ACTION_STOP -> {
                stopForegroundService()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val files = intent?.getIntExtra(EXTRA_FILES_COUNT, 0) ?: 0
                val peers = intent?.getIntExtra(EXTRA_PEERS_COUNT, 0) ?: 0
                val notification = buildNotification(files, peers)
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, notification)
                return START_STICKY
            }
            ACTION_START -> {
                val files = intent?.getIntExtra(EXTRA_FILES_COUNT, 0) ?: 0
                val peers = intent?.getIntExtra(EXTRA_PEERS_COUNT, 0) ?: 0
                val notification = buildNotification(files, peers)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }

                isRunning = true
                return START_STICKY
            }
        }

        return START_STICKY
    }

    private fun buildNotification(filesCount: Int, peersCount: Int): Notification {
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val stopIntent = Intent(this, MeshForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val filesText = if (filesCount == 1) "1 file" else "$filesCount files"
        val peersText = if (peersCount == 1) "1 crew member" else "$peersCount crew members"
        val statusText = "Sharing $filesText with $peersText"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Hypermesh Active")
            .setContentText(statusText)
            .setSubText("Offline Wi-Fi Node")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Sharing", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hypermesh Mesh Sharing",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the local Wi-Fi media server active when phone screen is locked."
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "hypermesh:wakelock_background_server"
            ).apply {
                setReferenceCounted(false)
                acquire(12 * 60 * 60 * 1000L) // 12 hours max safety timeout
            }

            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val wifiLockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifiManager.createWifiLock(wifiLockMode, "hypermesh:wifilock_server").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {}
    }

    private fun releaseLocks() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null

            wifiLock?.let {
                if (it.isHeld) it.release()
            }
            wifiLock = null
        } catch (_: Exception) {}
    }

    private fun stopForegroundService() {
        isRunning = false
        releaseLocks()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        releaseLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
