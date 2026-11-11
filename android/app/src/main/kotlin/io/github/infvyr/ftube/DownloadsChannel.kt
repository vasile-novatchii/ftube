package io.github.infvyr.ftube

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Drives [DownloadService] from Dart (docs/spec-v0.4.md D-45). Dart sends
 * every text already translated, so this class only builds notifications.
 * See BackgroundDownloads in lib/data/services/android/.
 */
class DownloadsChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)
    private val manager = context.getSystemService(NotificationManager::class.java)

    /** The last `update` arguments, rebuilt into the ongoing notification. */
    private var progress: Progress? = null

    /** Translated texts from the last `update`. */
    private var strings: Map<String, String> = emptyMap()

    /** Texts for the timeout notification, from the last `update`. */
    private var timedOutText: String? = null

    /** Set after Android 15 stopped the service, until the next `stop`. */
    private var timedOut = false

    /** The `paused` notification, while every job left is paused (D-70). */
    private var paused: Paused? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    update(call)
                    result.success(null)
                }
                "stop" -> {
                    stop(call)
                    result.success(null)
                }
                "paused" -> {
                    paused(call)
                    result.success(null)
                }
                "updateAvailable" -> result.success(updateAvailable(call))
                else -> result.notImplemented()
            }
        }
    }

    /** From the notifications' Cancel all action. */
    fun cancelAll() {
        // After a process restart Dart has no paused jobs and won't answer.
        manager.cancel(PAUSED_ID)
        paused = null
        channel.invokeMethod("cancelAll", null)
    }

    /** From the progress notification's Pause all action. */
    fun pauseAll() = channel.invokeMethod("pauseAll", null)

    /**
     * From the paused notification's Resume all action. Returns false when
     * this process has no paused queue, so there is nothing to resume.
     */
    fun resumeAll(): Boolean {
        val p = paused ?: run {
            manager.cancel(PAUSED_ID)
            return false
        }
        paused = null
        manager.cancel(PAUSED_ID)
        progress = Progress(p.title, p.text, null, p.strings)
        channel.invokeMethod("resumeAll", null)
        return true
    }

    /** The first notification of a service started by Resume all. */
    fun resumingNotification() = buildProgress(
        paused?.let { Progress(it.title, it.text, null, it.strings) }
            ?: Progress("", null, null, emptyMap()),
    )

    /** The ongoing notification for the current progress, if any. */
    fun progressNotification() = progress?.let(::buildProgress)

    /** Called by [DownloadService.onTimeout]: the service is gone. */
    fun onServiceTimedOut() {
        timedOut = true
        val text = timedOutText ?: return
        notify(RESULT_ID, text, null, done = false)
    }

    private fun update(call: MethodCall) {
        val strings = call.argument<Map<String, String>>("strings") ?: emptyMap()
        createChannels(strings)
        this.strings = strings
        timedOutText = strings["timedOut"]
        val p = Progress(
            title = call.argument<String>("title") ?: "",
            text = call.argument<String>("text"),
            percent = call.argument<Int>("percent"),
            strings = strings,
        )
        progress = p
        if (paused != null) {
            paused = null
            manager.cancel(PAUSED_ID)
        }
        if (timedOut) return
        val service = DownloadService.instance
        if (service != null) {
            manager.notify(PROGRESS_ID, buildProgress(p))
            return
        }
        try {
            DownloadService.starting()
            ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java))
        } catch (e: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException: Ftube is in the
            // background. The next update from the foreground starts it.
            Log.w(TAG, "can't start the download service", e)
        }
    }

    private fun stop(call: MethodCall) {
        progress = null
        paused = null
        timedOut = false
        DownloadService.stop()
        manager.cancel(PROGRESS_ID)
        manager.cancel(PAUSED_ID)
        val title = call.argument<String>("title") ?: return
        notify(RESULT_ID, title, call.argument<String>("text"), done = true)
    }

    /**
     * Every job left is paused: stop the service and its locks, and leave
     * a notification the user can swipe away, with Resume all (D-70).
     */
    private fun paused(call: MethodCall) {
        val p = Paused(
            title = call.argument<String>("title") ?: "",
            text = call.argument<String>("text"),
            strings = strings,
        )
        paused = p
        progress = null
        timedOut = false
        DownloadService.stop()
        manager.cancel(PROGRESS_ID)
        val n = NotificationCompat.Builder(context, PROGRESS_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_pause)
            .setContentTitle(p.title)
            .setContentText(p.text)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openApp())
            .addAction(0, strings["resumeAll"] ?: "Resume all", resumeAllIntent())
            .addAction(0, strings["cancelAll"] ?: "Cancel all", broadcast(DownloadActionReceiver.ACTION_CANCEL_ALL, 1))
            .build()
        manager.notify(PAUSED_ID, n)
    }

    /**
     * Posts the "new version" notification; tapping it opens the release
     * page (docs/spec-v0.6.md D-93). Returns false when notifications are
     * off, so Dart can try again on a later launch.
     */
    private fun updateAvailable(call: MethodCall): Boolean {
        val url = call.argument<String>("url")?.let(Uri::parse)
        if (url == null || url.scheme != "https") return false
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        manager.createNotificationChannel(
            NotificationChannel(
                UPDATE_CHANNEL,
                call.argument<String>("channel") ?: "App updates",
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        val open = Intent(Intent.ACTION_VIEW, url)
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val text = call.argument<String>("text")
        val n = NotificationCompat.Builder(context, UPDATE_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(call.argument<String>("title") ?: "")
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(PendingIntent.getActivity(context, 4, open, PendingIntent.FLAG_IMMUTABLE))
            .build()
        manager.notify(UPDATE_ID, n)
        return true
    }

    private fun createChannels(strings: Map<String, String>) {
        manager.createNotificationChannel(
            NotificationChannel(
                PROGRESS_CHANNEL,
                strings["progressChannel"] ?: "Downloads in progress",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setSound(null, null) },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                RESULT_CHANNEL,
                strings["resultChannel"] ?: "Finished downloads",
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun buildProgress(p: Progress) =
        NotificationCompat.Builder(context, PROGRESS_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(p.title)
            .setContentText(p.text)
            .setProgress(100, p.percent ?: 0, p.percent == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openApp())
            .addAction(0, p.strings["pauseAll"] ?: "Pause all", broadcast(DownloadActionReceiver.ACTION_PAUSE_ALL, 2))
            .addAction(0, p.strings["cancelAll"] ?: "Cancel all", broadcast(DownloadActionReceiver.ACTION_CANCEL_ALL, 1))
            .build()

    private fun notify(id: Int, title: String, text: String?, done: Boolean) {
        val n = NotificationCompat.Builder(context, RESULT_CHANNEL)
            .setSmallIcon(
                if (done) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_sys_warning,
            )
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text ?: title))
            .setAutoCancel(true)
            .setContentIntent(openApp())
            .build()
        manager.notify(id, n)
    }

    private fun openApp(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun broadcast(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, DownloadActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun resumeAllIntent(): PendingIntent {
        val intent = Intent(context, DownloadService::class.java).setAction(DownloadService.ACTION_RESUME_ALL)
        return PendingIntent.getForegroundService(context, 3, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private data class Progress(
        val title: String,
        val text: String?,
        val percent: Int?,
        val strings: Map<String, String>,
    )

    private data class Paused(val title: String, val text: String?, val strings: Map<String, String>)

    companion object {
        const val PROGRESS_ID = 1
        const val RESULT_ID = 2
        const val PAUSED_ID = 3
        const val UPDATE_ID = 4
        private const val UPDATE_CHANNEL = "app_update"
        private const val PROGRESS_CHANNEL = "downloads_progress"
        private const val RESULT_CHANNEL = "downloads_result"
        private const val NAME = "io.github.infvyr.ftube/downloads"
        private const val TAG = "DownloadsChannel"
    }
}
