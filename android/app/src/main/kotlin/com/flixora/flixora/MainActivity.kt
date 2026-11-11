package com.flixora.flixora

import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pictureInPictureChannel = "com.flixora.flixora/pip"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow landscape fullscreen content to use the display cutout area
        // instead of leaving a black strip beside the camera punch-hole.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val layoutParams = window.attributes
            layoutParams.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = layoutParams
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pictureInPictureChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "enterPictureInPicture") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                result.error(
                    "PIP_UNSUPPORTED",
                    "Picture-in-picture requires Android 8.0 or later.",
                    null
                )
                return@setMethodCallHandler
            }

            try {
                val width = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
                val height = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
                val aspectRatio = Rational(width, height)
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(aspectRatio)
                    .build()
                result.success(enterPictureInPictureMode(params))
            } catch (error: Exception) {
                result.error(
                    "PIP_FAILED",
                    error.message ?: "Could not enter picture-in-picture mode.",
                    null
                )
            }
        }
    }
}
