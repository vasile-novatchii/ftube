package io.github.infvyr.ftube

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * The share target: a see-through window over the sharing app, drawn by
 * the same cached engine as [MainActivity], so a download queued here joins
 * the app's queue (docs/spec-v0.4-share.md D-49). Dart shows the popup
 * while a share session is open, see [ShareChannel].
 */
class ShareActivity : FlutterActivity() {
    private val share get() = (application as FtubeApplication).share

    override fun getCachedEngineId() = FtubeApplication.ENGINE_ID

    override fun shouldDestroyEngineWithHost() = false

    override fun getBackgroundMode() = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        share.activity = this
        deliver(intent)
    }

    /** A second share while the popup is open replaces its link. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliver(intent)
    }

    /** [MainActivity] took the engine back, so the popup can't draw anymore. */
    override fun detachFromFlutterEngine() {
        super.detachFromFlutterEngine()
        finish()
    }

    override fun onDestroy() {
        if (share.activity === this) {
            share.activity = null
            share.dismissed()
        }
        super.onDestroy()
    }

    private fun deliver(intent: Intent) {
        if (intent.action == Intent.ACTION_SEND) {
            share.show(intent.getStringExtra(Intent.EXTRA_TEXT))
        }
    }
}
