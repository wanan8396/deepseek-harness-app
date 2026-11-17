package app.dsh.files

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import app.dsh.runtime.PhoneStorage.OUTPUT_SUBDIR
import java.io.File
import java.io.IOException
import kotlin.concurrent.thread

/** Saves diagnostic exports to Downloads via MethodChannel `dsh/files`. */
class FilesPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methods: MethodChannel
    private lateinit var context: Context
    private var activity: ActivityPluginBinding? = null
    private var pendingSave: (() -> Unit)? = null
    private var pendingDenied: (() -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        onDetachedFromActivity()
        methods.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        finishPermission(granted = false)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveToDownloads" -> save(call, result)
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Save to Downloads

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        val file = File(call.argument<String>("path") ?: "")
        if (!file.isFile) return result.error("missing", "no such file", null)
        val name = safeName(call.argument<String>("name") ?: file.name)
        val mime = mimeOf(call.argument<String>("mime"), name)
        saveOrAsk(file, name, mime, result, asked = false)
    }

    /**
     * Saves on a worker thread. Android 8–9 need the storage permission for the
     * public Downloads directory, so it is asked for first; on 10+ it is asked
     * for only if MediaStore turns this (targetSdk 28) app away. Asked once per save.
     */
    private fun saveOrAsk(file: File, name: String, mime: String, result: MethodChannel.Result, asked: Boolean) {
        val retry = { saveOrAsk(file, name, mime, result, asked = true) }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && !canWriteShared()) {
            return if (asked) result.error("permission", "storage permission denied", null) else ask(result, retry)
        }
        thread(name = "dsh-files", isDaemon = true) {
            val outcome = runCatching { saveNow(file, name, mime) }
            main.post {
                val error = outcome.exceptionOrNull()
                val refused = error is SecurityException || (error is FilesError && error.code == "permission")
                when {
                    error == null -> result.success(outcome.getOrNull())
                    refused && !asked && activity != null -> ask(result, retry)
                    else -> fail(result, error)
                }
            }
        }
    }

    private fun ask(result: MethodChannel.Result, then: () -> Unit) {
        if (pendingSave != null) return result.error("permission", "storage permission request already pending", null)
        val host = activity?.activity ?: return result.error("permission", "no activity to ask for permission", null)
        val denied = { result.error("permission", "storage permission denied", null) }
        pendingSave = then
        pendingDenied = denied
        try {
            host.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST)
        } catch (error: Exception) {
            // A synchronous callback may already have consumed this request.
            if (pendingDenied === denied) {
                pendingSave = null
                pendingDenied = null
                result.error("permission", error.message, null)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != STORAGE_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        finishPermission(granted)
        return true
    }

    private fun finishPermission(granted: Boolean) {
        val next = if (granted) pendingSave else pendingDenied
        pendingSave = null
        pendingDenied = null
        next?.invoke()
    }

    private fun saveNow(file: File, name: String, mime: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                return saveToMediaStore(file, name, mime)
            } catch (e: SecurityException) {
                if (!canWriteShared()) throw FilesError("permission", e.message)
            } catch (e: IOException) {
                if (!canWriteShared()) throw e
            }
        }
        if (!canWriteShared()) throw FilesError("permission", "storage permission denied")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = File(downloads, OUTPUT_SUBDIR).apply { mkdirs() }
        val target = file.inputStream().use { LegacyDownloads.copy(it, dir, name) }
        MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(mime), null)
        return "${Environment.DIRECTORY_DOWNLOADS}/$OUTPUT_SUBDIR/${target.name}"
    }

    private fun saveToMediaStore(file: File, name: String, mime: String): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$OUTPUT_SUBDIR")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore refused the file")
        try {
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: throw IOException("cannot write $uri")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // MediaStore renames on collision ("report (1).pdf"): report the name it kept.
        val shown = resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: name
        return "${Environment.DIRECTORY_DOWNLOADS}/$OUTPUT_SUBDIR/$shown"
    }

    private fun canWriteShared(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) return true
        val granted = context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        if (!granted) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Environment.isExternalStorageLegacy()
    }

    private fun fail(result: MethodChannel.Result, e: Throwable) = when (e) {
        is FilesError -> result.error(e.code, e.message, null)
        is SecurityException -> result.error("permission", e.message, null)
        else -> result.error("failed", e.message ?: e.javaClass.simpleName, null)
    }

    private class FilesError(val code: String, message: String?) : Exception(message)

    companion object {
        const val CHANNEL = "dsh/files"
        private const val STORAGE_REQUEST = 0x5d6

        /** [given] unless it is missing or generic, else the platform's guess from [name]'s extension. */
        fun mimeOf(given: String?, name: String): String {
            if (!given.isNullOrBlank() && given != "application/octet-stream") return given
            val ext = name.substringAfterLast('.', "").lowercase()
            return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        }

        /** A file name without path separators or control characters. */
        fun safeName(name: String): String {
            val cleaned = name.substringAfterLast('/').replace(Regex("[\\u0000-\\u001f\\\\:*?\"<>|]"), "_").trim()
            return cleaned.ifEmpty { "file" }
        }

    }
}
