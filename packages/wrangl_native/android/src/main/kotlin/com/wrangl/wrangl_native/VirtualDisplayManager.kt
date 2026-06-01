package com.wrangl.wrangl_native

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager

/**
 * Manages VirtualDisplays for embedding Android app windows in the infinite canvas.
 *
 * Each canvas window gets its own VirtualDisplay. The target app is launched on that
 * display's ID, and its rendered frames are captured via ImageReader and pushed to
 * the Flutter side as byte buffers.
 *
 * Touch injection uses root shell commands (`su -c "input tap x y"`) because
 * InputManager.injectInputEvent requires system-level INJECT_EVENTS permission.
 *
 * Requires:
 *   - root access on the device
 *   - MediaProjection granted by the user
 */
class VirtualDisplayManager(
    private val context: Context,
    private val mediaProjection: MediaProjection
) {
    companion object {
        private const val TAG = "VirtualDisplayManager"
        private const val MAX_DISPLAYS = 8
    }

    data class AppDisplay(
        val displayId: Int,
        val virtualDisplay: VirtualDisplay,
        var imageReader: ImageReader,
        val packageName: String,
        var width: Int,
        var height: Int
    )

    private val displays = mutableMapOf<String, AppDisplay>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var frameCallback: ((String, ByteArray) -> Unit)? = null
    private val lastTouch = mutableMapOf<String, Pair<Int, Int>>()

    fun onFrameAvailable(callback: (String, ByteArray) -> Unit) {
        frameCallback = callback
    }

    fun createDisplay(
        windowId: String,
        packageName: String,
        width: Int,
        height: Int
    ): Int {
        if (displays.size >= MAX_DISPLAYS) {
            throw IllegalStateException("Max displays reached ($MAX_DISPLAYS)")
        }

        val metrics = DisplayMetrics()
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm.defaultDisplay.getRealMetrics(metrics)

        val displayWidth = width.coerceIn(200, metrics.widthPixels)
        val displayHeight = height.coerceIn(200, metrics.heightPixels)

        val imageReader = ImageReader.newInstance(
            displayWidth,
            displayHeight,
            PixelFormat.RGBA_8888,
            3
        )

        imageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val planes = image.planes
                if (planes.isNotEmpty()) {
                    val buffer = planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    frameCallback?.invoke(windowId, bytes)
                }
            } finally {
                image.close()
            }
        }, mainHandler)

        val display = mediaProjection.createVirtualDisplay(
            "wrangl_canvas_$windowId",
            displayWidth,
            displayHeight,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,
            imageReader.surface,
            null,
            null
        )

        val appDisplay = AppDisplay(
            displayId = display.display.displayId,
            virtualDisplay = display,
            imageReader = imageReader,
            packageName = packageName,
            width = displayWidth,
            height = displayHeight
        )

        displays[windowId] = appDisplay

        // Launch the app on the virtual display
        launchOnDisplay(packageName, display.display.displayId)

        return display.display.displayId
    }

    private fun launchOnDisplay(packageName: String, displayId: Int) {
        try {
            val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
                // Use ActivityOptions to target the virtual display
                try {
                    val activityOptionsClass = Class.forName("android.app.ActivityOptions")
                    val makeBasic = activityOptionsClass.getMethod("makeBasic")
                    val options = makeBasic.invoke(null)
                    val setLaunchDisplayId = activityOptionsClass.getMethod(
                        "setLaunchDisplayId", Int::class.java
                    )
                    setLaunchDisplayId.invoke(options, displayId)
                    val toBundle = activityOptionsClass.getMethod("toBundle")
                    val bundle = toBundle.invoke(options) as android.os.Bundle
                    context.startActivity(intent, bundle)
                } catch (e: Exception) {
                    // Fallback: launch without display targeting
                    context.startActivity(intent)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun resizeDisplay(windowId: String, width: Int, height: Int) {
        val display = displays[windowId] ?: return
        display.virtualDisplay.resize(width, height, context.resources.displayMetrics.densityDpi)
        display.imageReader.setOnImageAvailableListener(null, null)
        val newReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 3)
        newReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val planes = image.planes
                if (planes.isNotEmpty()) {
                    val buffer = planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    frameCallback?.invoke(windowId, bytes)
                }
            } finally {
                image.close()
            }
        }, mainHandler)
        display.virtualDisplay.setSurface(newReader.surface)
        display.imageReader.close()
        display.imageReader = newReader
    }

    fun injectTouch(windowId: String, x: Int, y: Int, action: Int) {
        val display = displays[windowId] ?: return
        try {
            val displayId = display.displayId
            when (action) {
                0 -> {
                    lastTouch[windowId] = Pair(x, y)
                }
                1 -> {
                    val prev = lastTouch[windowId]
                    if (prev != null && (prev.first != x || prev.second != y)) {
                        val cmd = "su -c \"input -d $displayId touchscreen swipe ${prev.first} ${prev.second} $x $y 50\""
                        Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                    } else {
                        val cmd = "su -c \"input -d $displayId touchscreen tap $x $y\""
                        Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                    }
                    lastTouch.remove(windowId)
                }
                2 -> {
                    val prev = lastTouch[windowId]
                    if (prev != null && (prev.first != x || prev.second != y)) {
                        val cmd = "su -c \"input -d $displayId touchscreen swipe ${prev.first} ${prev.second} $x $y 0\""
                        Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                    }
                    lastTouch[windowId] = Pair(x, y)
                }
                else -> {
                    val cmd = "su -c \"input -d $displayId touchscreen tap $x $y\""
                    Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun closeDisplay(windowId: String) {
        val display = displays.remove(windowId) ?: return
        try {
            display.imageReader.close()
            display.virtualDisplay.release()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun releaseAll() {
        for (key in displays.keys.toList()) {
            closeDisplay(key)
        }
    }

    fun getDisplayIds(): List<String> = displays.keys.toList()
}
