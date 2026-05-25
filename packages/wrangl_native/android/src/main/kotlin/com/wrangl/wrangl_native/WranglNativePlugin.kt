package com.wrangl.wrangl_native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper

import androidx.core.content.ContextCompat

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Wrangl native bridge. Registered as a real plugin so its channel attaches to
 * every Flutter engine — the main launcher AND the overlay isolate.
 *
 * App-launch + capture work from any engine (they use the application context
 * and the running [ScreenCaptureService]); consent needs an Activity, so it is
 * only serviceable from the engine attached to the launcher.
 */
class WranglNativePlugin :
    FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {

    private companion object {
        const val REQ_SCREEN_CONSENT = 0x5C1
    }

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val main = Handler(Looper.getMainLooper())

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingConsent: MethodChannel.Result? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "wrangl/native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ── ActivityAware (only the launcher engine has an Activity) ───────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    // ── Method dispatch ────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> getInstalledApps(result)
            "launchApp" -> launchApp(call.argument<String>("packageName"), result)
            "requestScreenConsent" -> requestScreenConsent(result)
            "isScreenReady" -> result.success(ScreenCaptureService.isRunning)
            "captureScreen" -> captureScreen(result)
            "stopScreen" -> {
                ScreenCaptureService.stop(appContext)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun getInstalledApps(result: MethodChannel.Result) {
        val pm = appContext.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val apps = pm.queryIntentActivities(intent, 0)
            .filter { it.activityInfo.packageName != appContext.packageName }
            .map {
                mapOf(
                    "packageName" to it.activityInfo.packageName,
                    "label" to it.loadLabel(pm).toString(),
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
        result.success(apps)
    }

    private fun launchApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName == null) {
            result.error("INVALID", "packageName required", null)
            return
        }
        val launch = appContext.packageManager.getLaunchIntentForPackage(packageName)
        if (launch == null) {
            result.success(false)
            return
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(launch)
        result.success(true)
    }

    private fun requestScreenConsent(result: MethodChannel.Result) {
        if (ScreenCaptureService.isRunning) {
            result.success(true)
            return
        }
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Screen consent must be requested from the app", null)
            return
        }
        if (pendingConsent != null) {
            result.error("BUSY", "A consent request is already in progress", null)
            return
        }
        pendingConsent = result
        val mpm = act.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        act.startActivityForResult(mpm.createScreenCaptureIntent(), REQ_SCREEN_CONSENT)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_SCREEN_CONSENT) return false
        val pending = pendingConsent
        pendingConsent = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            val svc = Intent(appContext, ScreenCaptureService::class.java)
                .putExtra("resultCode", resultCode)
                .putExtra("data", data)
            ContextCompat.startForegroundService(appContext, svc)
            pending?.success(true)
        } else {
            pending?.success(false)
        }
        return true
    }

    private fun captureScreen(result: MethodChannel.Result) {
        val svc = ScreenCaptureService.instance
        if (svc == null) {
            result.success(null)
            return
        }
        svc.capture { bytes -> main.post { result.success(bytes) } }
    }
}
