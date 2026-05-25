package com.wrangl.wrangl_native

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder

import androidx.core.app.NotificationCompat

import java.io.ByteArrayOutputStream

/**
 * Holds a live MediaProjection and grabs single downscaled JPEG frames on
 * demand. Runs as a `mediaProjection` foreground service so the projection
 * survives while the user is in other apps. Exposed to plugin instances on any
 * engine through the [instance] singleton.
 */
class ScreenCaptureService : Service() {

    companion object {
        @Volatile
        var instance: ScreenCaptureService? = null
            private set

        /** True when a usable projection is live. */
        val isRunning: Boolean
            get() = instance?.projection != null

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, ScreenCaptureService::class.java))
        }

        private const val CH_ID = "wrangl_capture"
        private const val NOTIF_ID = 8731
        private const val MAX_EDGE = 768f
    }

    private var projection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var width = 0
    private var height = 0
    private var dpi = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        instance = this

        @Suppress("DEPRECATION")
        val data: Intent? = intent?.getParcelableExtra("data")
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        if (data != null && resultCode == Activity.RESULT_OK) {
            setupProjection(resultCode, data)
        }
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        createChannel()
        val notif: Notification = NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("Wrangl can see your screen")
            .setContentText("Used only when you ask the bubble about your screen")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun setupProjection(resultCode: Int, data: Intent) {
        val metrics = resources.displayMetrics
        width = metrics.widthPixels
        height = metrics.heightPixels
        dpi = metrics.densityDpi

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = mpm.getMediaProjection(resultCode, data)

        thread = HandlerThread("wrangl-capture").also { it.start() }
        handler = Handler(thread!!.looper)

        projection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                teardown()
            }
        }, handler)

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        virtualDisplay = projection?.createVirtualDisplay(
            "wrangl-screen",
            width,
            height,
            dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null,
            handler,
        )
    }

    /** Grab the latest frame as a downscaled JPEG; callback receives null on failure. */
    fun capture(callback: (ByteArray?) -> Unit) {
        val reader = imageReader
        val h = handler
        if (reader == null || h == null || projection == null) {
            callback(null)
            return
        }
        h.post {
            var bytes: ByteArray? = null
            try {
                var image = reader.acquireLatestImage()
                var tries = 0
                while (image == null && tries < 10) {
                    Thread.sleep(40)
                    image = reader.acquireLatestImage()
                    tries++
                }
                if (image != null) {
                    bytes = imageToJpeg(image)
                    image.close()
                }
            } catch (_: Exception) {
                bytes = null
            }
            callback(bytes)
        }
    }

    private fun imageToJpeg(image: Image): ByteArray {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width

        val raw = Bitmap.createBitmap(
            width + rowPadding / pixelStride,
            height,
            Bitmap.Config.ARGB_8888,
        )
        raw.copyPixelsFromBuffer(buffer)
        val cropped = Bitmap.createBitmap(raw, 0, 0, width, height)

        val scale = (MAX_EDGE / maxOf(width, height)).coerceAtMost(1f)
        val out = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                cropped,
                (width * scale).toInt(),
                (height * scale).toInt(),
                true,
            )
        } else {
            cropped
        }

        val baos = ByteArrayOutputStream()
        out.compress(Bitmap.CompressFormat.JPEG, 80, baos)
        return baos.toByteArray()
    }

    private fun teardown() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        projection?.stop()
        projection = null
        thread?.quitSafely()
        thread = null
        handler = null
    }

    override fun onDestroy() {
        teardown()
        instance = null
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CH_ID,
                "Wrangl screen capture",
                NotificationManager.IMPORTANCE_LOW,
            )
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }
}
