package com.example.redrive

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val STORAGE_CHANNEL = "com.example.redrive/storage"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveExportFile") {
                    val fileName = call.argument<String>("fileName")
                    val content = call.argument<String>("content")
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                    if (fileName.isNullOrBlank() || content == null) {
                        result.error("INVALID_ARGS", "fileName and content are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savedPath = saveToExternalStorage(fileName, content, mimeType)
                        result.success(savedPath)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to save export file $fileName", e)
                        result.error("SAVE_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun saveToExternalStorage(fileName: String, content: String, mimeType: String): String {
        val bytes = content.toByteArray(Charsets.UTF_8)

        // 1. Try direct write to /storage/emulated/0/ReDrive or /storage/emulated/0/Download/ReDrive
        val directCandidates = listOf(
            File("/storage/emulated/0/ReDrive"),
            File("/storage/emulated/0/Download/ReDrive"),
            File(Environment.getExternalStorageDirectory(), "ReDrive"),
            File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "ReDrive")
        )
        for (dir in directCandidates) {
            try {
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                if (dir.exists() && dir.canWrite()) {
                    val outFile = File(dir, fileName)
                    outFile.writeBytes(bytes)
                    return outFile.absolutePath
                }
            } catch (_: Exception) {
                // Fall through to MediaStore
            }
        }

        // 2. Android 10+ (API 29+): Use MediaStore.Downloads so no special storage permission is required
        // to write directly into /storage/emulated/0/Download/ReDrive/<fileName>
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/ReDrive")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                resolver.openOutputStream(uri)?.use { os ->
                    os.write(bytes)
                    os.flush()
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return "/storage/emulated/0/Download/ReDrive/$fileName"
            }
        }

        // 3. Final fallback on /storage/emulated/0/Android/data/<pkg>/files/ReDrive_Exports
        val extDir = getExternalFilesDir(null)
        if (extDir != null) {
            val exportDir = File(extDir, "ReDrive_Exports")
            if (!exportDir.exists()) exportDir.mkdirs()
            val outFile = File(exportDir, fileName)
            outFile.writeBytes(bytes)
            return outFile.absolutePath
        }

        throw IllegalStateException("Unable to access /storage/emulated/0/")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleSilentStart(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSilentStart(intent)
    }

    private fun handleSilentStart(intent: Intent?) {
        if (intent?.getBooleanExtra("silent_start", false) == true) {
            Log.i(TAG, "ReDrive started silently from ignition wake; moving task to back")
            moveTaskToBack(true)
            try {
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            } catch (_: Exception) {}
        }
    }
}
