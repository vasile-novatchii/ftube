package io.github.infvyr.ftube

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /** The trash call waiting for the system dialog, with the paths it moves. */
    private var pendingTrash: Pair<MethodChannel.Result, List<String>>? = null

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
        // See FileSystemService.trash in lib/data/services/.
        MethodChannel(messenger, "io.github.infvyr.ftube/trash")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "trash" -> trash(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Moves files to the bin with one MediaStore trash request, so the user
     * confirms the whole batch once. Files get a MediaStore URI by scanning.
     */
    private fun trash(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths")
        if (paths.isNullOrEmpty()) {
            result.error("bad_args", "paths is required", null)
            return
        }
        if (pendingTrash != null) {
            result.error("busy", "another trash request is open", null)
            return
        }
        val uris = arrayOfNulls<Uri>(paths.size)
        var left = paths.size
        MediaScannerConnection.scanFile(applicationContext, paths.toTypedArray(), null) { path, uri ->
            runOnUiThread {
                uris[paths.indexOf(path)] = uri
                if (--left == 0) requestTrash(paths, uris.toList(), result)
            }
        }
    }

    private fun requestTrash(paths: List<String>, uris: List<Uri?>, result: MethodChannel.Result) {
        val found = paths.indices.filter { uris[it] != null }
        val missing = paths.size - found.size
        val error = if (missing > 0) "$missing file(s) not in the media store" else null
        if (found.isEmpty()) {
            result.success(mapOf("moved" to emptyList<String>(), "error" to error))
            return
        }
        val request = MediaStore.createTrashRequest(contentResolver, found.map { uris[it]!! }, true)
        pendingTrash = result to found.map { paths[it] }
        try {
            @Suppress("DEPRECATION")
            startIntentSenderForResult(request.intentSender, TRASH_REQUEST, null, 0, 0, 0)
        } catch (e: Exception) {
            pendingTrash = null
            result.error("trash_failed", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != TRASH_REQUEST) return
        val (result, paths) = pendingTrash ?: return
        pendingTrash = null
        val moved = if (resultCode == RESULT_OK) paths else emptyList()
        result.success(mapOf("moved" to moved, "error" to null))
    }

    private companion object {
        const val TRASH_REQUEST = 7301
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
