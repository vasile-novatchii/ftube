package io.github.infvyr.ftube

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Pause all and Cancel all from the download notifications
 * (docs/spec-v0.4.md D-70). A broadcast works whether or not
 * [DownloadService] still runs; the paused notification has none.
 */
class DownloadActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val downloads = (context.applicationContext as FtubeApplication).downloads
        when (intent.action) {
            ACTION_PAUSE_ALL -> downloads.pauseAll()
            ACTION_CANCEL_ALL -> downloads.cancelAll()
        }
    }

    companion object {
        const val ACTION_PAUSE_ALL = "io.github.infvyr.ftube.PAUSE_ALL"
        const val ACTION_CANCEL_ALL = "io.github.infvyr.ftube.CANCEL_ALL"
    }
}
