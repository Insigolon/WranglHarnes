package com.wrangl.wrangl_native

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.provider.Telephony
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
        private const val REQUEST_PICK_FILE = 1003

        // Intent actions for system settings panels.
        private val SETTINGS_ACTIONS = mapOf(
            "wifi" to Settings.ACTION_WIFI_SETTINGS,
            "bluetooth" to Settings.ACTION_BLUETOOTH_SETTINGS,
            "mobile_data" to Settings.ACTION_DATA_ROAMING_SETTINGS,
            "airplane_mode" to Settings.ACTION_AIRPLANE_MODE_SETTINGS,
            "display" to Settings.ACTION_DISPLAY_SETTINGS,
            "sound" to Settings.ACTION_SOUND_SETTINGS,
            "notification" to Settings.ACTION_APP_NOTIFICATION_SETTINGS,
            "battery" to Settings.ACTION_BATTERY_SAVER_SETTINGS,
            "storage" to Settings.ACTION_INTERNAL_STORAGE_SETTINGS,
            "location" to Settings.ACTION_LOCATION_SOURCE_SETTINGS,
            "security" to Settings.ACTION_SECURITY_SETTINGS,
            "apps" to Settings.ACTION_APPLICATION_SETTINGS,
            "language_input" to Settings.ACTION_INPUT_METHOD_SETTINGS,
            "accessibility" to Settings.ACTION_ACCESSIBILITY_SETTINGS,
            "about_phone" to Settings.ACTION_DEVICE_INFO_SETTINGS,
            "date_time" to Settings.ACTION_DATE_SETTINGS,
            "developer_options" to Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS,
            "hotspot" to Settings.ACTION_WIFI_SETTINGS,
            "vpn" to Settings.ACTION_VPN_SETTINGS,
            "wallpaper" to Settings.ACTION_DISPLAY_SETTINGS,
        )

        // All currently-subscribed EventChannel sinks across every Flutter
        // engine in this process.
        private val liveSinks = mutableSetOf<EventChannel.EventSink>()
        private val mainHandler = Handler(Looper.getMainLooper())

        // Process-wide MediaProjection (valid until the service is destroyed).
        private var mediaProjection: MediaProjection? = null
        private var consentPendingResult: MethodChannel.Result? = null
        private var pickFilePendingResult: MethodChannel.Result? = null

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
    private lateinit var widgetHost: WidgetHostManager

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

        widgetHost = WidgetHostManager(appContext)

        binding.platformViewRegistry.registerViewFactory(
            "com.wrangl/widget_host",
            WidgetHostViewFactory(widgetHost),
        )
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
        widgetHost.setActivity(binding.activity)
        widgetHost.onStart()
        binding.addActivityResultListener { requestCode, resultCode, data ->
            when (requestCode) {
                REQUEST_MEDIA_PROJECTION -> {
                    onMediaProjectionResult(resultCode, data)
                    true
                }
                REQUEST_PICK_FILE -> {
                    onPickFileResult(resultCode, data)
                    true
                }
                else -> widgetHost.handleActivityResult(requestCode, resultCode, data)
            }
        }
    }

    override fun onDetachedFromActivity() {
        widgetHost.onStop()
        widgetHost.setActivity(null)
        mainActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        mainActivity = binding.activity
        widgetHost.setActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        widgetHost.setActivity(null)
        mainActivity = null
    }

    // ── Method dispatch ────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> getInstalledApps(result)
            "launchApp" -> launchApp(call.argument<String>("packageName"), result)
            "captureScreen" -> captureScreen(result)
            "pickFile" -> pickFile(result)
            "scanFiles" -> scanFiles(
                call.argument<String>("query"),
                call.argument<String>("mimeType"),
                result,
            )
            "openSetting" -> openSetting(
                call.argument<String>("key"),
                result,
            )
            "readSms" -> readSms(
                (call.argument<Int>("limit") ?: 20).coerceIn(1, 100),
                result,
            )
            "listWidgetProviders" -> widgetHost.listWidgetProviders(result)
            "bindWidget" -> widgetHost.bindWidget(
                call.argument<String>("providerPackage") ?: "",
                call.argument<String>("providerClass") ?: "",
                result,
            )
            "refreshWidgets" -> widgetHost.refreshWidgets(result)
            "removeWidget" -> widgetHost.removeWidget(
                call.argument<Int>("appWidgetId") ?: -1,
                result,
            )
            "setWidgetOrder" -> widgetHost.setWidgetOrder(
                (call.argument<List<Int>>("widgetIds") ?: emptyList()),
                result,
            )
            "openHomeSettings" -> openHomeSettings(result)
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
                val drawable = it.activityInfo.loadIcon(pm)
                val iconBytes = try {
                    val bitmap = Bitmap.createBitmap(
                        drawable.intrinsicWidth.coerceAtLeast(1),
                        drawable.intrinsicHeight.coerceAtLeast(1),
                        Bitmap.Config.ARGB_8888,
                    )
                    val cv = Canvas(bitmap)
                    drawable.setBounds(0, 0, cv.width, cv.height)
                    drawable.draw(cv)
                    ByteArrayOutputStream().use { stream ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 96, stream)
                        stream.toByteArray()
                    }
                } catch (_: Exception) {
                    null
                }
                mapOf(
                    "packageName" to it.activityInfo.packageName,
                    "label" to it.loadLabel(pm).toString(),
                    "icon" to iconBytes,
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { (it["label"] as? String)?.lowercase() }
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

    private fun pickFile(result: MethodChannel.Result) {
        val act = mainActivity
        if (act == null) {
            result.error("NO_ACTIVITY", "No activity to show file picker", null)
            return
        }
        pickFilePendingResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "*/*"
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        act.startActivityForResult(Intent.createChooser(intent, "Select File"), REQUEST_PICK_FILE)
    }

    private fun onPickFileResult(resultCode: Int, data: Intent?) {
        val result = pickFilePendingResult
        pickFilePendingResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null || data.data == null) {
            result.error("CANCELLED", "File picking cancelled", null)
            return
        }
        val uri = data.data!!
        try {
            val inputStream = appContext.contentResolver.openInputStream(uri)
            val bytes = inputStream?.readBytes()
            if (bytes != null) {
                var name = "file"
                val cursor = appContext.contentResolver.query(uri, null, null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            name = it.getString(nameIndex)
                        }
                    }
                }
                result.success(mapOf(
                    "name" to name,
                    "bytes" to bytes
                ))
            } else {
                result.error("READ_FAILED", "Could not read file data", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ── MediaStore file search ──────────────────────────────────────────────────

    private fun scanFiles(query: String?, mimeType: String?, result: MethodChannel.Result) {
        try {
            // Runtime permission check (Android 13+ granular media permissions).
            val permission = if (Build.VERSION.SDK_INT >= 33) {
                when (mimeType?.trim()?.lowercase()) {
                    "image" -> android.Manifest.permission.READ_MEDIA_IMAGES
                    "video" -> android.Manifest.permission.READ_MEDIA_VIDEO
                    "audio" -> android.Manifest.permission.READ_MEDIA_AUDIO
                    else -> null // document or unspecified — check all below
                }
            } else {
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            }
            val granted = if (permission != null) {
                appContext.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
            } else {
                // No single permission covers the mimeType; check any of the three.
                (Build.VERSION.SDK_INT < 33) ||
                    (appContext.checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED) ||
                    (appContext.checkSelfPermission(android.Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED) ||
                    (appContext.checkSelfPermission(android.Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED)
            }
            if (!granted) {
                val hint = if (Build.VERSION.SDK_INT >= 33)
                    "Grant the READ_MEDIA_IMAGES / READ_MEDIA_VIDEO / READ_MEDIA_AUDIO runtime permission in Settings > Apps > Wrangl"
                else
                    "Grant the READ_EXTERNAL_STORAGE runtime permission in Settings > Apps > Wrangl"
                result.error("PERMISSION_DENIED", "MediaStore read permission not granted. $hint", null)
                return
            }

            val uri = MediaStore.Files.getContentUri("external")
            val projections = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.DATA,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.MIME_TYPE,
            )

            val sel = StringBuilder()
            val selArgs = mutableListOf<String>()

            if (!query.isNullOrBlank()) {
                sel.append("${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?")
                selArgs.add("%${query.trim()}%")
            }

            if (!mimeType.isNullOrBlank()) {
                if (sel.isNotEmpty()) sel.append(" AND ")
                when (mimeType.trim().lowercase()) {
                    "image" -> {
                        sel.append("${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ?")
                        selArgs.add("image/%")
                    }
                    "video" -> {
                        sel.append("${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ?")
                        selArgs.add("video/%")
                    }
                    "audio" -> {
                        sel.append("${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ?")
                        selArgs.add("audio/%")
                    }
                    "document" -> {
                        sel.append("(${MediaStore.Files.FileColumns.MIME_TYPE} IN (?, ?, ?, ?))")
                        selArgs.addAll(listOf("text/plain", "text/csv", "text/markdown", "application/pdf"))
                    }
                    else -> {
                        sel.append("${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ?")
                        selArgs.add("${mimeType.trim()}/%")
                    }
                }
            }

            val cursor = appContext.contentResolver.query(
                uri,
                projections,
                sel.toString().ifEmpty { null },
                selArgs.toTypedArray().ifEmpty { null },
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC",
            )

            val files = mutableListOf<Map<String, Any>>()
            cursor?.use { c ->
                val nameIdx = c.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val dataIdx = c.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                val sizeIdx = c.getColumnIndex(MediaStore.Files.FileColumns.SIZE)
                val mimeIdx = c.getColumnIndex(MediaStore.Files.FileColumns.MIME_TYPE)

                var count = 0
                while (c.moveToNext() && count < 50) {
                    val name = if (nameIdx >= 0) c.getString(nameIdx) ?: "unknown" else "unknown"
                    val path = if (dataIdx >= 0) c.getString(dataIdx) ?: "" else ""
                    val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L
                    val mime = if (mimeIdx >= 0) c.getString(mimeIdx) ?: "" else ""
                    files.add(
                        mapOf(
                            "name" to name,
                            "path" to path,
                            "size" to size,
                            "mimeType" to mime,
                        ),
                    )
                    count++
                }
            }

            result.success(files)
        } catch (e: Exception) {
            result.error("SCAN_FAILED", e.message, null)
        }
    }

    // ── Settings deep-links ─────────────────────────────────────────────────────

    private fun openSetting(key: String?, result: MethodChannel.Result) {
        if (key == null) {
            result.error("INVALID", "key required", null)
            return
        }
        val action = SETTINGS_ACTIONS[key.trim().lowercase()]
            ?: Settings.ACTION_SETTINGS
        try {
            val intent = Intent(action).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            appContext.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    private fun openHomeSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_HOME_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            appContext.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    // ── SMS reading (requires READ_SMS) ─────────────────────────────────────────

    private fun readSms(limit: Int, result: MethodChannel.Result) {
        try {
            val uri = Telephony.Sms.Inbox.CONTENT_URI
            val projections = arrayOf(
                Telephony.Sms.Inbox._ID,
                Telephony.Sms.Inbox.ADDRESS,
                Telephony.Sms.Inbox.BODY,
                Telephony.Sms.Inbox.DATE_SENT,
                Telephony.Sms.Inbox.THREAD_ID,
            )
            val cursor = appContext.contentResolver.query(
                uri,
                projections,
                null,
                null,
                "${Telephony.Sms.Inbox.DATE} DESC",
            )

            val messages = mutableListOf<Map<String, Any>>()
            cursor?.use { c ->
                val addrIdx = c.getColumnIndex(Telephony.Sms.Inbox.ADDRESS)
                val bodyIdx = c.getColumnIndex(Telephony.Sms.Inbox.BODY)
                val dateIdx = c.getColumnIndex(Telephony.Sms.Inbox.DATE_SENT)

                var count = 0
                while (c.moveToNext() && count < limit) {
                    val sender = if (addrIdx >= 0) c.getString(addrIdx) ?: "unknown" else "unknown"
                    val body = if (bodyIdx >= 0) c.getString(bodyIdx) ?: "" else ""
                    val date = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                    messages.add(
                        mapOf(
                            "sender" to sender,
                            "body" to body,
                            "timestamp" to date,
                        ),
                    )
                    count++
                }
            }

            result.success(messages)
        } catch (e: SecurityException) {
            // READ_SMS not granted (common on API 34+ when not default SMS app).
            result.error(
                "PERMISSION_DENIED",
                "Wrangl is not the default SMS app. To enable, go to Settings > Apps > Default apps > SMS app",
                null,
            )
        } catch (e: Exception) {
            result.error("SMS_READ_FAILED", e.message, null)
        }
    }
}
