package io.github.infvyr.ftube

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
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

    /** Texts for the timeout notification, from the last `update`. */
    private var timedOutText: String? = null

    /** Set after Android 15 stopped the service, until the next `stop`. */
    private var timedOut = false

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
                else -> result.notImplemented()
            }
        }
    }

    /** From the notification's Cancel all action. */
    fun cancelAll() = channel.invokeMethod("cancelAll", null)

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
        timedOutText = strings["timedOut"]
        val p = Progress(
            title = call.argument<String>("title") ?: "",
            text = call.argument<String>("text"),
            percent = call.argument<Int>("percent"),
            cancelAll = strings["cancelAll"] ?: "Cancel all",
        )
        progress = p
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
        timedOut = false
        DownloadService.stop()
        manager.cancel(PROGRESS_ID)
        val title = call.argument<String>("title") ?: return
        notify(RESULT_ID, title, call.argument<String>("text"), done = true)
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
            .addAction(0, p.cancelAll, cancelAllIntent())
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

    private fun cancelAllIntent(): PendingIntent {
        val intent = Intent(context, DownloadService::class.java).setAction(DownloadService.ACTION_CANCEL_ALL)
        return PendingIntent.getService(context, 1, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private data class Progress(val title: String, val text: String?, val percent: Int?, val cancelAll: String)

    companion object {
        const val PROGRESS_ID = 1
        const val RESULT_ID = 2
        private const val PROGRESS_CHANNEL = "downloads_progress"
        private const val RESULT_CHANNEL = "downloads_result"
        private const val NAME = "io.github.infvyr.ftube/downloads"
        private const val TAG = "DownloadsChannel"
    }
}
