package com.thirai.thirai_player

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var permResult: MethodChannel.Result? = null
    private val pool = Executors.newFixedThreadPool(3)

    companion object {
        const val REQ_VIDEO = 4101
        const val REQ_SUB = 4102
        const val REQ_PERM = 4103
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
                "requestPermission" -> requestVideoPermission(result)
                "queryVideos" -> pool.execute {
                    val list = try { queryVideos() } catch (e: Exception) { emptyList<Map<String, Any?>>() }
                    runOnUiThread { result.success(list) }
                }
                "thumbnail" -> {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    pool.execute {
                        val bytes = try { thumbnail(id) } catch (e: Exception) { null }
                        runOnUiThread { result.success(bytes) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- permission ----------
    private fun videoPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= 34 -> arrayOf(
            "android.permission.READ_MEDIA_VIDEO",
            "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
        )
        Build.VERSION.SDK_INT >= 33 -> arrayOf("android.permission.READ_MEDIA_VIDEO")
        else -> arrayOf("android.permission.READ_EXTERNAL_STORAGE")
    }

    private fun hasVideoPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return videoPermissions().any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }

    private fun requestVideoPermission(result: MethodChannel.Result) {
        if (hasVideoPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= 23) {
            permResult?.success(false)
            permResult = result
            requestPermissions(videoPermissions(), REQ_PERM)
        } else {
            result.success(true)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_PERM) {
            permResult?.success(hasVideoPermission())
            permResult = null
        }
    }

    // ---------- MediaStore ----------
    private fun videoCollection(): Uri =
        if (Build.VERSION.SDK_INT >= 29) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        else MediaStore.Video.Media.EXTERNAL_CONTENT_URI

    private fun queryVideos(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val collection = videoCollection()
        val proj = arrayOf(
            "_id",
            "_display_name",
            "bucket_display_name",
            "_size",
            "duration",
            "date_added",
            "width",
            "height"
        )
        contentResolver.query(collection, proj, null, null, "date_added DESC")?.use { c ->
            val iId = c.getColumnIndexOrThrow("_id")
            val iName = c.getColumnIndexOrThrow("_display_name")
            val iBucket = c.getColumnIndexOrThrow("bucket_display_name")
            val iSize = c.getColumnIndexOrThrow("_size")
            val iDur = c.getColumnIndexOrThrow("duration")
            val iDate = c.getColumnIndexOrThrow("date_added")
            val iW = c.getColumnIndexOrThrow("width")
            val iH = c.getColumnIndexOrThrow("height")
            while (c.moveToNext()) {
                val id = c.getLong(iId)
                out.add(
                    mapOf(
                        "id" to id,
                        "uri" to ContentUris.withAppendedId(collection, id).toString(),
                        "name" to (c.getString(iName) ?: "Video"),
                        "folder" to (c.getString(iBucket) ?: "Others"),
                        "size" to c.getLong(iSize),
                        "duration" to c.getLong(iDur),
                        "date" to c.getLong(iDate),
                        "width" to c.getInt(iW),
                        "height" to c.getInt(iH)
                    )
                )
            }
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun thumbnail(id: Long): ByteArray? {
        val bmp: Bitmap? = if (Build.VERSION.SDK_INT >= 29) {
            contentResolver.loadThumbnail(ContentUris.withAppendedId(videoCollection(), id), Size(320, 180), null)
        } else {
            MediaStore.Video.Thumbnails.getThumbnail(contentResolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null)
        }
        if (bmp == null) return null
        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 75, stream)
        return stream.toByteArray()
    }

    // ---------- file picker (no copying of big 4K files) ----------
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
