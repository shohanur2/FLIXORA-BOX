package com.flixora.flixora

import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Rational
import android.view.WindowManager
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.flixora.flixora/pip"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    pipEnabled = call.argument<Boolean>("enabled") ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.flixora.flixora/media_store"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "publishVideo" -> {
                        val sourcePath = call.argument<String>("path")
                            ?: throw IllegalArgumentException("Missing video path")
                        val displayName = call.argument<String>("displayName")
                            ?: File(sourcePath).name
                        val source = File(sourcePath)
                        if (!source.exists()) throw IllegalArgumentException("Downloaded video is missing")
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            throw IllegalStateException("Public media storage requires Android 10 or newer")
                        }
                        val extension = source.extension.lowercase()
                        val mime = when (extension) {
                            "mkv" -> "video/x-matroska"
                            "webm" -> "video/webm"
                            "mov" -> "video/quicktime"
                            "avi" -> "video/x-msvideo"
                            "m4v" -> "video/x-m4v"
                            else -> "video/mp4"
                        }
                        val safeName = displayName.replace(Regex("[^A-Za-z0-9._ -]"), "_")
                            .let { if (it.endsWith(".$extension", true)) it else "$it.$extension" }
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                            put(MediaStore.MediaColumns.RELATIVE_PATH, "Movies/FLIXORA")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                        val uri = contentResolver.insert(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            values
                        ) ?: throw IllegalStateException("Could not create File Manager entry")
                        try {
                            val output = contentResolver.openOutputStream(uri)
                                ?: throw IllegalStateException("Could not open File Manager entry")
                            output.use { stream ->
                                source.inputStream().use { input -> input.copyTo(stream) }
                            }
                            val ready = ContentValues().apply {
                                put(MediaStore.MediaColumns.IS_PENDING, 0)
                            }
                            contentResolver.update(uri, ready, null, null)
                            result.success(uri.toString())
                        } catch (error: Exception) {
                            contentResolver.delete(uri, null, null)
                            throw error
                        }
                    }
                    "exists" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        val exists = contentResolver.query(
                            uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null
                        )?.use { it.moveToFirst() } ?: false
                        result.success(exists)
                    }
                    "delete" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        contentResolver.delete(uri, null, null)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("MEDIA_STORE_ERROR", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.flixora.flixora/download_background"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val serviceIntent = Intent(this, DownloadForegroundService::class.java)
                        .setAction(DownloadForegroundService.ACTION_START)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }
                "stop" -> {
                    stopService(Intent(this, DownloadForegroundService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val layoutParams = window.attributes
            layoutParams.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = layoutParams
        }
    }

    override fun onUserLeaveHint() {
        if (pipEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setAutoEnterEnabled(true)
                    }
                }
                .build()
            enterPictureInPictureMode(params)
        }
        super.onUserLeaveHint()
    }
}
