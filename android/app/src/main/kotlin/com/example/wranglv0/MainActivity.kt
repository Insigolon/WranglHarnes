package com.example.wranglv0

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host Activity for wrangl v0.
 *
 * Channels:
 *   - `wrangl/overlay_permission` — check/request SYSTEM_ALERT_WINDOW
 */
class MainActivity : FlutterActivity() {

    private companion object {
        private const val PERM_CHANNEL = "wrangl/overlay_permission"
    }

    // ── Permission request ───────────────────────────────────────────────────

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, PERM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "check" -> result.success(overlayGranted())
                "request" -> {
                    if (overlayGranted()) {
                        result.success(true)
                    } else {
                        pendingResult = result
                        openOverlaySettings()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onResume() {
        super.onResume()
        pendingResult?.let {
            it.success(overlayGranted())
            pendingResult = null
        }
    }

    // ── Overlay permission helpers ─────────────────────────────────────────

    private fun overlayGranted(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            Settings.canDrawOverlays(this)
        else
            true

    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivityForResult(intent, 1001)
        }
    }
}
