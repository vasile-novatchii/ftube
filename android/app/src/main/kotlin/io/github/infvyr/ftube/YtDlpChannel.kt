package io.github.infvyr.ftube

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Runs yt-dlp through youtubedl-android (docs/spec-v0.3.md D-33).
 * See YtDlpBridge in lib/data/services/android/.
 */
class YtDlpChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)
    private val main = Handler(Looper.getMainLooper())
    private val pool = Executors.newCachedThreadPool()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "version" -> background(result) { init(); YoutubeDL.version(context) }
                "update" -> background(result) {
                    init()
                    YoutubeDL.updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
                    YoutubeDL.version(context)
                }
                "run" -> run(call, result)
                "cancel" -> {
                    val id = call.argument<String>("id")
                    result.success(id != null && YoutubeDL.destroyProcessById(id))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val args = call.argument<List<String>>("args")
        if (id == null || args.isNullOrEmpty()) {
            result.error("bad_args", "id and args are required", null)
            return
        }
        background(result) {
            init()
            // The URL is the last argument, after "--".
            val request = YoutubeDLRequest(args.last()).addCommands(args.dropLast(1))
            try {
                val r = YoutubeDL.execute(request, id) { _, _, line ->
                    main.post { channel.invokeMethod("line", mapOf("id" to id, "line" to line)) }
                }
                mapOf("exitCode" to r.exitCode, "stderr" to r.err, "cancelled" to false)
            } catch (e: YoutubeDL.CanceledException) {
                mapOf("exitCode" to -1, "stderr" to "", "cancelled" to true)
            } catch (e: YoutubeDLException) {
                // The library throws on a non-zero exit with stderr as the message.
                mapOf("exitCode" to 1, "stderr" to (e.message ?: ""), "cancelled" to false)
            }
        }
    }

    private fun init() = YoutubeDL.init(context)

    /** Runs [body] on a worker thread and answers on the main thread. */
    private fun background(result: MethodChannel.Result, body: () -> Any?) {
        pool.execute {
            try {
                val value = body()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("ytdlp_failed", e.message ?: e.toString(), null) }
            }
        }
    }

    private companion object {
        const val NAME = "io.github.infvyr.ftube/ytdlp"
    }
}
