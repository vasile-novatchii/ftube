package io.github.infvyr.ftube

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Environment
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // See StoragePermissionService in lib/data/services/android/.
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
                            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // See AndroidFileLauncher in lib/data/services/android/.
        MethodChannel(messenger, "io.github.infvyr.ftube/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open", "share" -> launch(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens or shares a file through a content URI from [FileProvider]. */
    private fun launch(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("bad_args", "path is required", null)
            return
        }
        val file = File(path)
        if (!file.isFile) {
            result.error("not_found", path, null)
            return
        }
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.files", file)
        } catch (e: IllegalArgumentException) {
            result.error("not_shareable", e.message, null)
            return
        }
        val mime = contentResolver.getType(uri) ?: "*/*"
        val intent = if (call.method == "open") {
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            val send = Intent(Intent.ACTION_SEND)
                .setType(mime)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            send.clipData = ClipData.newRawUri(file.name, uri)
            Intent.createChooser(send, null)
        }
        try {
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_app", e.message, null)
        }
    }
}
