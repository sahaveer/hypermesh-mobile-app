package com.hypermesh.player.hypermesh_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.hypermesh.player/background_service"
    private val DEVICE_CHANNEL = "com.hypermesh.player/device_controls"
    private val SHARE_CHANNEL = "com.hypermesh.player/share_intent"
    private val DOWNLOAD_CHANNEL_ID = "hypermesh_downloads"
    private val DOWNLOAD_ALERT_CHANNEL_ID = "hypermesh_download_alerts"

    private var pendingSharedText: String? = null
    private var shareChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractSharedText(intent)?.let { pendingSharedText = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractSharedText(intent)?.let { shared ->
            pendingSharedText = shared
            shareChannel?.invokeMethod("onSharedText", shared)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        return if (!text.isNullOrEmpty()) text else null
    }

    private fun ensureDownloadNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val progressChannel = NotificationChannel(
                DOWNLOAD_CHANNEL_ID,
                "Downloads Progress",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active media download progress."
                setShowBadge(false)
            }
            val alertChannel = NotificationChannel(
                DOWNLOAD_ALERT_CHANNEL_ID,
                "Download Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifies when a download finishes or fails."
            }
            manager.createNotificationChannel(progressChannel)
            manager.createNotificationChannel(alertChannel)
        }
    }

    private fun buildAppLaunchPendingIntent(): PendingIntent? {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        return PendingIntent.getActivity(
            this,
            2,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedText" -> {
                        val text = pendingSharedText
                        pendingSharedText = null
                        result.success(text)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setScreenBrightness" -> {
                    val brightness = call.argument<Double>("brightness")?.toFloat() ?: -1.0f
                    try {
                        val lp = window.attributes
                        lp.screenBrightness = if (brightness < 0f) {
                            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        } else {
                            brightness.coerceIn(0.01f, 1.0f)
                        }
                        window.attributes = lp
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BRIGHTNESS_ERROR", e.message, null)
                    }
                }
                "resetScreenBrightness" -> {
                    try {
                        val lp = window.attributes
                        lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        window.attributes = lp
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BRIGHTNESS_ERROR", e.message, null)
                    }
                }
                "getScreenBrightness" -> {
                    try {
                        val lp = window.attributes
                        if (lp.screenBrightness >= 0f) {
                            result.success(lp.screenBrightness.toDouble())
                        } else {
                            val sysBrightness = android.provider.Settings.System.getInt(
                                contentResolver,
                                android.provider.Settings.System.SCREEN_BRIGHTNESS
                            )
                            result.success(sysBrightness / 255.0)
                        }
                    } catch (e: Exception) {
                        result.success(0.5)
                    }
                }
                "setDeviceVolume" -> {
                    val volume = call.argument<Double>("volume") ?: 0.5
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        if (audioManager != null) {
                            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val target = (volume * max).toInt().coerceIn(0, max)
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", e.message, null)
                    }
                }
                "getDeviceVolume" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        if (audioManager != null) {
                            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                            result.success(if (max > 0) current.toDouble() / max.toDouble() else 0.5)
                        } else {
                            result.success(0.5)
                        }
                    } catch (e: Exception) {
                        result.success(0.5)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val filesCount = call.argument<Int>("filesCount") ?: 0
                    val peersCount = call.argument<Int>("peersCount") ?: 0
                    val intent = Intent(this, MeshForegroundService::class.java).apply {
                        action = MeshForegroundService.ACTION_START
                        putExtra(MeshForegroundService.EXTRA_FILES_COUNT, filesCount)
                        putExtra(MeshForegroundService.EXTRA_PEERS_COUNT, peersCount)
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "updateService" -> {
                    val filesCount = call.argument<Int>("filesCount") ?: 0
                    val peersCount = call.argument<Int>("peersCount") ?: 0
                    val intent = Intent(this, MeshForegroundService::class.java).apply {
                        action = MeshForegroundService.ACTION_UPDATE
                        putExtra(MeshForegroundService.EXTRA_FILES_COUNT, filesCount)
                        putExtra(MeshForegroundService.EXTRA_PEERS_COUNT, peersCount)
                    }
                    startService(intent)
                    result.success(true)
                }
                "stopService" -> {
                    val intent = Intent(this, MeshForegroundService::class.java).apply {
                        action = MeshForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(MeshForegroundService.isRunning)
                }
                "getAppSourceApkPath" -> {
                    try {
                        val apkPath = applicationInfo.sourceDir
                        result.success(apkPath)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "showDownloadProgress" -> {
                    val id = call.argument<String>("id") ?: "dl"
                    val title = call.argument<String>("title") ?: "Downloading..."
                    val progress = (call.argument<Int>("progress") ?: 0).coerceIn(0, 100)
                    val detail = call.argument<String>("detail") ?: "$progress%"
                    try {
                        ensureDownloadNotificationChannels()
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val notif = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
                            .setContentTitle(title)
                            .setContentText(detail)
                            .setSmallIcon(R.drawable.ic_stat_hypermesh)
                            .setOngoing(true)
                            .setOnlyAlertOnce(true)
                            .setProgress(100, progress, progress == 0)
                            .setContentIntent(buildAppLaunchPendingIntent())
                            .setPriority(NotificationCompat.PRIORITY_LOW)
                            .build()
                        manager.notify(id.hashCode(), notif)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "showDownloadComplete" -> {
                    val id = call.argument<String>("id") ?: "dl"
                    val title = call.argument<String>("title") ?: "Download"
                    val success = call.argument<Boolean>("success") ?: true
                    val message = call.argument<String>("message") ?: if (success) "Completed" else "Failed"
                    try {
                        ensureDownloadNotificationChannels()
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val notif = NotificationCompat.Builder(this, DOWNLOAD_ALERT_CHANNEL_ID)
                            .setContentTitle(if (success) "Downloaded: $title" else "Failed: $title")
                            .setContentText(message)
                            .setSmallIcon(R.drawable.ic_stat_hypermesh)
                            .setAutoCancel(true)
                            .setContentIntent(buildAppLaunchPendingIntent())
                            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                            .build()
                        manager.notify(id.hashCode(), notif)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = File(filePath)
                            if (file.exists()) {
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    file
                                )
                                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                }
                                startActivity(installIntent)
                                result.success(true)
                            } else {
                                result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                            }
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARG", "filePath is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
