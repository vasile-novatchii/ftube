package io.github.infvyr.ftube

import android.app.Application
import android.media.MediaScannerConnection
import android.os.Environment
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the one Flutter engine, so the Dart download queue outlives the
 * activity (docs/spec-v0.4.md D-41). Channels that don't need an activity
 * are registered here once; activity-bound ones stay in [MainActivity].
 */
class FtubeApplication : Application() {
    lateinit var downloads: DownloadsChannel
        private set

    override fun onCreate() {
        super.onCreate()
        // Plugins are registered by the engine itself (automaticallyRegisterPlugins).
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        val messenger = engine.dartExecutor.binaryMessenger
        YtDlpChannel(this, messenger)
        storageChannel(messenger)
        downloads = DownloadsChannel(this, messenger)
    }

    /** See StoragePermissionService in lib/data/services/android/. */
    private fun storageChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, "io.github.infvyr.ftube/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadsDir" -> {
                        @Suppress("DEPRECATION")
                        val dir = Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS,
                        )
                        result.success(dir.absolutePath)
                    }
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path is required", null)
                        } else {
                            MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        const val ENGINE_ID = "ftube"
    }
}
