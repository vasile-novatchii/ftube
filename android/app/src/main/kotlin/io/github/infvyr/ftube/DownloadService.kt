package io.github.infvyr.ftube

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.ServiceCompat

/**
 * Keeps the process, and with it the cached engine and the Dart queue,
 * alive while downloads run (docs/spec-v0.4.md D-40, D-42, D-43). It runs
 * no download logic itself; [DownloadsChannel] starts, updates and stops it.
 */
class DownloadService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var foreground = false

    private val app get() = application as FtubeApplication

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL_ALL) {
            app.downloads.cancelAll()
            if (!foreground) stopSelf()
            return START_NOT_STICKY
        }
        val notification = app.downloads.progressNotification()
        if (notification == null || stopRequested) {
            // Stopped before the start went through. startForeground must
            // still be called once, or Android ends the app.
            if (notification != null) startInForeground(notification)
            finish()
            return START_NOT_STICKY
        }
        instance = this
        startInForeground(notification)
        acquireLocks()
        return START_NOT_STICKY
    }

    /** Android 15+: the daily `dataSync` limit is used up (R-22). */
    override fun onTimeout(startId: Int, fgsType: Int) {
        app.downloads.onServiceTimedOut()
        finish()
    }

    override fun onDestroy() {
        releaseLocks()
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun startInForeground(notification: android.app.Notification) {
        ServiceCompat.startForeground(
            this,
            DownloadsChannel.PROGRESS_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
        foreground = true
    }

    private fun finish() {
        // A later update must start a new service, not update this one.
        if (instance === this) instance = null
        releaseLocks()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        foreground = false
        stopSelf()
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ftube:downloads")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            wifiLock = getSystemService(WifiManager::class.java)
                .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ftube:downloads")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
    }

    private fun releaseLocks() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        wifiLock?.takeIf { it.isHeld }?.release()
        wifiLock = null
    }

    companion object {
        const val ACTION_CANCEL_ALL = "io.github.infvyr.ftube.CANCEL_ALL"

        /** The running service, if any. Same process as the engine. */
        var instance: DownloadService? = null
            private set

        /** A stop that arrived before the service had started. */
        private var stopRequested = false

        /** Called before asking Android to start the service. */
        fun starting() {
            stopRequested = false
        }

        /** Stops the service, or makes a pending start stop right away. */
        fun stop() {
            val service = instance
            if (service == null) {
                stopRequested = true
            } else {
                service.finish()
            }
        }
    }
}
