package io.github.infvyr.ftube

import android.media.MediaScannerConnection
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // See StoragePermissionService in lib/data/services/android/.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.infvyr.ftube/storage")
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
                            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
