package com.thirai.thirai_player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null

    companion object {
        const val REQ_VIDEO = 4101
        const val REQ_SUB = 4102
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "thirai/native")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUri" -> {
                    val i = intent
                    val data = i?.data
                    if (i != null && data != null && i.action == Intent.ACTION_VIEW) {
                        i.action = Intent.ACTION_MAIN
                        result.success(mapOf("uri" to data.toString(), "name" to displayName(data)))
                    } else {
                        result.success(null)
                    }
                }
                "pickVideo" -> openPicker(
                    REQ_VIDEO,
                    arrayOf("video/*", "audio/*", "application/x-matroska", "application/vnd.rn-realmedia", "application/octet-stream"),
                    result
                )
                "pickSubtitle" -> openPicker(REQ_SUB, arrayOf("*/*"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun openPicker(req: Int, mimes: Array<String>, result: MethodChannel.Result) {
        pending?.success(null)
        pending = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (mimes.size == 1) mimes[0] else "*/*"
            if (mimes.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, mimes)
        }
        startActivityForResult(i, req)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_VIDEO && requestCode != REQ_SUB) return
        val res = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            res.success(null)
            return
        }
        if (requestCode == REQ_VIDEO) {
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) {}
            res.success(mapOf("uri" to uri.toString(), "name" to displayName(uri)))
        } else {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                res.success(mapOf("name" to displayName(uri), "bytes" to bytes))
            } catch (e: Exception) {
                res.error("READ", e.message, null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = intent.data
        if (intent.action == Intent.ACTION_VIEW && data != null) {
            channel?.invokeMethod("openUri", mapOf("uri" to data.toString(), "name" to displayName(data)))
        }
    }

    private fun displayName(uri: Uri): String {
        var name: String? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        } catch (_: Exception) {}
        return name ?: uri.lastPathSegment ?: "Video"
    }
}
