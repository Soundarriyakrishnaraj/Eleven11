
package com.eleven11.eleven11

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.database.Cursor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.eleven11/audio_picker"
    private val requestCode = 11111
    private var pendingResult: MethodChannel.Result? = null

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

                else -> result.notImplemented()
            }
        }
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
