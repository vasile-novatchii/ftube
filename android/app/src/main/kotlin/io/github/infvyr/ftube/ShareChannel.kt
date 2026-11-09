package io.github.infvyr.ftube

import android.content.Context
import android.widget.Toast
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Hands shared text to Dart and closes the popup
 * (docs/spec-v0.4-share.md D-52). Registered once in [FtubeApplication];
 * [ShareActivity] sets [activity] while it is open.
 *
 * Text is pushed with `show` and also kept until Dart takes it with
 * `pending`, so a share that starts the process isn't lost before Dart has
 * set its handler.
 */
class ShareChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)

    /** A share Dart has not received yet. */
    private var pending: Shared? = null

    var activity: ShareActivity? = null

    private class Shared(val text: String?)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> {
                    val shared = pending
                    pending = null
                    result.success(shared?.let { mapOf("text" to it.text) })
                }
                "close" -> {
                    call.argument<String>("toast")?.let {
                        Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
                    }
                    activity?.finish()
                    result.success(null)
                }
                "openApp" -> {
                    // The launcher intent brings the existing Ftube task
                    // forward instead of starting a second one.
                    context.packageManager.getLaunchIntentForPackage(context.packageName)
                        ?.let { (activity ?: context).startActivity(it) }
                    activity?.finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Opens the popup for [text], or replaces the link it shows. */
    fun show(text: String?) {
        val shared = Shared(text)
        pending = shared
        channel.invokeMethod(
            "show",
            mapOf("text" to text),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pending === shared) pending = null
                }

                // Dart isn't listening yet: it reads `pending` on start.
                override fun error(code: String, message: String?, details: Any?) {}

                override fun notImplemented() {}
            },
        )
    }

    /** The popup's activity is gone, so Dart shows the app again. */
    fun dismissed() {
        pending = null
        channel.invokeMethod("dismissed", null)
    }

    companion object {
        const val NAME = "io.github.infvyr.ftube/share"
    }
}
