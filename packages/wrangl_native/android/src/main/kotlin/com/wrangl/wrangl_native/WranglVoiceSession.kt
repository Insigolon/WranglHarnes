package com.wrangl.wrangl_native

import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.view.View
import android.widget.Toast

import java.io.ByteArrayOutputStream

/**
 * The per-invocation assist session. Lifecycle for one assist gesture:
 *
 *   1. System calls [onCreateContentView] — we return an empty view because
 *      the bubble overlay owns the chat UI, not us.
 *   2. System fires [onHandleAssist] (the foreground app's [AssistStructure])
 *      and [onHandleScreenshot] (a [Bitmap] of the screen) — either order,
 *      and either may be skipped depending on user privacy settings.
 *   3. Once both have arrived (or after [maybeForwardAndFinish] is called the
 *      second time), we encode the screenshot, walk the structure for visible
 *      text, push both into the overlay isolate over the wrangl/assist_events
 *      [io.flutter.plugin.common.EventChannel] (see [WranglNativePlugin]),
 *      hide ourselves, and finish.
 *
 * If the overlay isolate isn't currently listening — e.g. the bubble hasn't
 * been booted since install — we Toast a one-liner and bail so the user
 * doesn't think the gesture is broken.
 */
class WranglVoiceSession(context: Context) : VoiceInteractionSession(context) {

    private companion object {
        const val MAX_EDGE = 768
        const val JPEG_QUALITY = 80
        const val MAX_STRUCTURE_TEXT_CHARS = 4000
    }

    private var pendingScreenshot: ByteArray? = null
    private var pendingHint: String? = null
    private var screenshotDelivered = false
    private var assistDelivered = false
    private var forwarded = false

    /** Empty view — the bubble overlay is the real UI. */
    override fun onCreateContentView(): View = View(context)

    override fun onHandleScreenshot(screenshot: Bitmap?) {
        super.onHandleScreenshot(screenshot)
        pendingScreenshot = screenshot?.let(::encodeJpeg)
        screenshotDelivered = true
        maybeForwardAndFinish()
    }

    @Suppress("DEPRECATION") // pre-API-30 signature, but still fires on all versions
    override fun onHandleAssist(
        data: Bundle?,
        structure: AssistStructure?,
        content: AssistContent?,
    ) {
        super.onHandleAssist(data, structure, content)
        pendingHint = structure?.let(::extractText)
        assistDelivered = true
        maybeForwardAndFinish()
    }

    private fun maybeForwardAndFinish() {
        // Wait until we've heard from both callbacks (or got the chance to —
        // either firing twice is fine, we only forward once).
        if (forwarded) return
        if (!screenshotDelivered || !assistDelivered) return
        forwarded = true

        val payload = mapOf(
            "image" to pendingScreenshot,
            "hint" to pendingHint,
        )
        val delivered = WranglNativePlugin.broadcastAssist(payload)
        if (!delivered) {
            Toast.makeText(
                context,
                "Open Wrangl once to enable screen capture",
                Toast.LENGTH_SHORT,
            ).show()
        }
        hide()
        // Don't call finish() here — the system will tear us down once hide()
        // settles, and calling finish() inside a callback can drop pending
        // sibling callbacks on some OEMs.
    }

    // ── encoding / extraction ──────────────────────────────────────────────────

    private fun encodeJpeg(src: Bitmap): ByteArray {
        val longest = maxOf(src.width, src.height).toFloat()
        val scale = (MAX_EDGE / longest).coerceAtMost(1f)
        val scaled = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                src,
                (src.width * scale).toInt(),
                (src.height * scale).toInt(),
                true,
            )
        } else {
            src
        }
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
        return out.toByteArray()
    }

    /** Depth-first walk of the structure pulling every non-blank text node. */
    private fun extractText(structure: AssistStructure): String {
        val buf = StringBuilder()
        for (i in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(i).rootViewNode, buf)
            if (buf.length >= MAX_STRUCTURE_TEXT_CHARS) break
        }
        return buf.toString().take(MAX_STRUCTURE_TEXT_CHARS)
    }

    private fun walk(node: AssistStructure.ViewNode, buf: StringBuilder) {
        if (buf.length >= MAX_STRUCTURE_TEXT_CHARS) return
        node.text?.toString()?.takeIf { it.isNotBlank() }?.let {
            buf.append(it).append('\n')
        }
        for (i in 0 until node.childCount) {
            walk(node.getChildAt(i), buf)
            if (buf.length >= MAX_STRUCTURE_TEXT_CHARS) return
        }
    }
}
