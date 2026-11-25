
package com.eleven11.eleven11

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.database.Cursor
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.eleven11/audio_picker"
    private val requestCode = 11111
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        turnScreenOnAndKeyguard()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        turnScreenOnAndKeyguard()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        turnScreenOnAndKeyguard()
    }

    private fun turnScreenOnAndKeyguard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "pickAudio" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "Audio picker is already open.", null)
                        return@setMethodCallHandler
                    }

                    pendingResult = result

                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "audio/*"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }

                    try {
                        startActivityForResult(intent, requestCode)
                    } catch (e: Exception) {
                        pendingResult = null
                        result.error("PICKER_ERROR", e.message, null)
                    }
                }

                "saveToDownloads" -> {
                    val name = call.argument<String>("name")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    if (name == null || bytes == null) {
                        result.error("BAD_ARGS", "Missing file name or data.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(saveToDownloads(name, bytes, mime))
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /** Saves a file into the public Downloads folder; returns a readable location. */
    private fun saveToDownloads(name: String, bytes: ByteArray, mime: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                put(android.provider.MediaStore.Downloads.MIME_TYPE, mime)
                put(android.provider.MediaStore.Downloads.RELATIVE_PATH, "Download")
            }
            val uri = contentResolver.insert(
                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw Exception("Could not create file in Downloads.")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("Could not write file.")
            return "Downloads/$name"
        }
        val dir = getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
            ?: throw Exception("Storage unavailable.")
        val file = java.io.File(dir, name)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != this.requestCode) return

        val result = pendingResult ?: return
        pendingResult = null

        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri: Uri = data.data!!

        try {
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (se: SecurityException) {
                // Handle provider specific permission grant
            }

            var fileName = "Selected audio"

            val cursor: Cursor? = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )

            cursor?.use {
                if (it.moveToFirst()) {
                    val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        fileName = it.getString(index) ?: fileName
                    }
                }
            }

            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "name" to fileName
                )
            )
        } catch (e: Exception) {
            result.error("AUDIO_PERMISSION_ERROR", e.message, null)
        }
    }
}
