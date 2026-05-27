package com.wrangl.wrangl_native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

import java.io.ByteArrayOutputStream

/**
 * Wrangl's native bridge. Registers on every Flutter engine in the app —
 * launcher and overlay isolate — so both can call the app-launching methods,
 * and so the overlay isolate can subscribe to the assist event stream.
 *
 * Channels:
 *   - MethodChannel `wrangl/native` — request/response (list apps, launch app,
 *     captureScreen).
 *   - EventChannel `wrangl/assist_events` — push from
 *     [WranglVoiceSession] when the user fires the assist gesture.
 *
 * Screen capture via MediaProjection: the first call triggers a system consent
 * dialog. Once granted, subsequent captures return the JPEG bytes without any
 * further user interaction.
 */
class WranglNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    companion object {
        private const val CAPTURE_QUALITY = 80
        private const val CAPTURE_MAX_EDGE = 768
        private const val REQUEST_MEDIA_PROJECTION = 1002

        // All currently-subscribed EventChannel sinks across every Flutter
        // engine in this process.
        private val liveSinks = mutableSetOf<EventChannel.EventSink>()
        private val mainHandler = Handler(Looper.getMainLooper())

        // Process-wide MediaProjection (valid until the service is destroyed).
        private var mediaProjection: MediaProjection? = null
        private var consentPendingResult: MethodChannel.Result? = null

        // Activity from the launcher engine (the only one that can show the
        // consent dialog). Shared via companion so the overlay isolate's plugin
        // instance can use it too.
        private var mainActivity: Activity? = null

        /**
         * Push an assist payload to every subscribed Flutter sink.
         */
        @JvmStatic
        fun broadcastAssist(payload: Map<String, Any?>): Boolean {
            val snapshot = synchronized(liveSinks) { liveSinks.toList() }
            if (snapshot.isEmpty()) return false
            mainHandler.post {
                for (sink in snapshot) {
                    try {
                        sink.success(payload)
                    } catch (_: Exception) { }
                }
            }
            return true
        }

        /** Clean up the stored projection when the user revokes it. */
        @JvmStatic
        fun invalidateProjection() {
            mediaProjection?.stop()
            mediaProjection = null
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var appContext: Context
    private var eventSink: EventChannel.EventSink? = null

    // ── FlutterPlugin ──────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        channel = MethodChannel(binding.binaryMessenger, "wrangl/native")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "wrangl/assist_events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                if (events != null) {
                    synchronized(liveSinks) { liveSinks.add(events) }
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink?.let { sink ->
                    synchronized(liveSinks) { liveSinks.remove(sink) }
                }
                eventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink?.let { sink ->
            synchronized(liveSinks) { liveSinks.remove(sink) }
        }
        eventSink = null
    }

    // ── ActivityAware ──────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        mainActivity = binding.activity
        binding.addActivityResultListener { requestCode, resultCode, data ->
            if (requestCode == REQUEST_MEDIA_PROJECTION) {
                onMediaProjectionResult(resultCode, data)
                true
            } else {
                false
            }
        }
    }

    override fun onDetachedFromActivity() {
        mainActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        mainActivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        mainActivity = null
    }

    // ── Method dispatch ────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> getInstalledApps(result)
            "launchApp" -> launchApp(call.argument<String>("packageName"), result)
            "captureScreen" -> captureScreen(result)
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

    // ── Screen capture (MediaProjection) ───────────────────────────────────────

    private fun captureScreen(result: MethodChannel.Result) {
        if (mediaProjection == null) {
            val mgr = appContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                    as MediaProjectionManager
            consentPendingResult = result
            val act = mainActivity
            if (act == null) {
                result.error("NO_ACTIVITY", "No activity to show consent dialog", null)
                return
            }
            act.startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
            return
        }
        doCapture(result)
    }

    private fun onMediaProjectionResult(resultCode: Int, data: Intent?) {
        val result = consentPendingResult
        consentPendingResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.error("DENIED", "Screen capture permission denied", null)
            return
        }
        val mgr = appContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        mediaProjection = mgr.getMediaProjection(resultCode, data)
        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                mediaProjection = null
            }
        }, mainHandler)
        doCapture(result)
    }

    private fun doCapture(result: MethodChannel.Result) {
        val proj = mediaProjection
        if (proj == null) {
            result.error("NO_PROJECTION", "MediaProjection not available", null)
            return
        }

        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(dm)
        val width = dm.widthPixels
        val height = dm.heightPixels
        val dpi = dm.densityDpi

        // Scale down if needed.
        val longest = maxOf(width, height).toFloat()
        val scale = (CAPTURE_MAX_EDGE / longest).coerceAtMost(1f)
        val vw = (width * scale).toInt()
        val vh = (height * scale).toInt()

        val imageReader = ImageReader.newInstance(vw, vh, PixelFormat.RGBA_8888, 2)
        val display = proj.createVirtualDisplay(
            "capture",
            vw, vh, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader.surface, null, null,
        )

        val bgHandler = HandlerThread("capture-bg").apply { start() }
        val latch = java.util.concurrent.CountDownLatch(1)
        var captured: ByteArray? = null

        imageReader.setOnImageAvailableListener({ reader ->
            val img = reader.acquireLatestImage()
            if (img != null) {
                captured = imageToJpeg(img)
                img.close()
            }
            latch.countDown()
        }, Handler(bgHandler.looper))

        // Wait up to 2 seconds for a frame.
        try {
            latch.await(2000, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) { }

        display.release()
        imageReader.close()
        bgHandler.quitSafely()

        if (captured != null) {
            result.success(captured)
        } else {
            result.error("CAPTURE_FAILED", "No frame captured", null)
        }
    }

    private fun imageToJpeg(image: android.media.Image): ByteArray {
        val planes = image.planes
        val buffer = planes[0].buffer
        val pixelStride = planes[0].pixelStride
        val rowStride = planes[0].rowStride
        val w = image.width
        val h = image.height

        val pixels = IntArray(w * h)
        val row = IntArray(w)
        for (y in 0 until h) {
            buffer.position(y * rowStride)
            val line = ByteArray(w * 4)
            buffer[line]
            for (x in 0 until w) {
                val idx = x * 4
                val r = line[idx].toInt() and 0xFF
                val g = line[idx + 1].toInt() and 0xFF
                val b = line[idx + 2].toInt() and 0xFF
                val a = line[idx + 3].toInt() and 0xFF
                row[x] = (a shl 24) or (r shl 16) or (g shl 8) or b
            }
            System.arraycopy(row, 0, pixels, y * w, w)
        }

        val bmp = Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, CAPTURE_QUALITY, out)
        bmp.recycle()
        return out.toByteArray()
    }
}
