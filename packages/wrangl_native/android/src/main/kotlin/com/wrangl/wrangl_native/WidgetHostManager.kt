package com.wrangl.wrangl_native

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import android.util.TypedValue
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class WidgetHostManager(private val appContext: Context) {

    companion object {
        private const val REQUEST_WIDGET_CONFIG = 2002
        private const val REQUEST_BIND_WIDGET = 2003
        private const val PREFS_FILE = "widget_host.json"
    }

    private val mgr: AppWidgetManager = AppWidgetManager.getInstance(appContext)
    private val host: AppWidgetHost = AppWidgetHost(appContext, appContext.packageName.hashCode() and 0x7fffffff)

    private var mainActivity: Activity? = null
    private var pendingConfig: PendingWidget? = null
    private var pendingBind: PendingBind? = null

    private data class PendingWidget(
        val appWidgetId: Int,
        val info: AppWidgetProviderInfo,
        val result: MethodChannel.Result,
    )

    private data class PendingBind(
        val appWidgetId: Int,
        val info: AppWidgetProviderInfo,
        val result: MethodChannel.Result,
    )

    // ── Lifecycle ───────────────────────────────────────────────────────────────

    fun setActivity(activity: Activity?) {
        mainActivity = activity
    }

    fun onStart() {
        try { host.startListening() } catch (_: Exception) { }
    }

    fun onStop() {
        try { host.stopListening() } catch (_: Exception) { }
    }

    // ── Public API ──────────────────────────────────────────────────────────────

    fun listWidgetProviders(result: MethodChannel.Result) {
        try {
            val providers = mgr.getInstalledProviders()
                .filter { it.provider != null }
                .map { info ->
                    val label = try {
                        info.loadLabel(appContext.packageManager) ?: info.provider.className
                    } catch (_: Exception) {
                        info.provider.className
                    }
                    mapOf(
                        "providerPackage" to info.provider.packageName,
                        "providerClass" to info.provider.className,
                        "providerLabel" to label,
                        "minWidthDp" to info.minWidth,
                        "minHeightDp" to info.minHeight,
                    )
                }
            result.success(providers)
        } catch (e: Exception) {
            result.error("WIDGET_LIST_FAILED", e.message, null)
        }
    }

    fun bindWidget(
        providerPackage: String,
        providerClass: String,
        result: MethodChannel.Result,
    ) {
        val act = mainActivity
        if (act == null) {
            result.error("NO_ACTIVITY", "No main activity available", null)
            return
        }

        val info = mgr.getInstalledProviders().find {
            it.provider?.packageName == providerPackage && it.provider?.className == providerClass
        }
        if (info == null || info.provider == null) {
            result.error("WIDGET_NOT_FOUND", "Widget provider not found", null)
            return
        }

        val appWidgetId: Int
        try {
            appWidgetId = host.allocateAppWidgetId()
        } catch (e: Exception) {
            result.error("ALLOCATE_FAILED", e.message, null)
            return
        }

        val bound = mgr.bindAppWidgetIdIfAllowed(appWidgetId, info.provider)
        if (!bound) {
            // Fallback: ask user to confirm binding via system intent
            pendingBind = PendingBind(appWidgetId, info, result)
            val bindIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, info.provider)
            }
            try {
                act.startActivityForResult(bindIntent, REQUEST_BIND_WIDGET)
            } catch (e: Exception) {
                pendingBind = null
                host.deleteAppWidgetId(appWidgetId)
                result.error("BIND_FAILED", "Failed to launch bind intent: ${e.message}", null)
            }
            return
        }

        val updatedInfo = mgr.getAppWidgetInfo(appWidgetId)
        if (updatedInfo == null) {
            result.error("WIDGET_BIND_FAILED", "Widget info not found after binding", null)
            return
        }

        if (updatedInfo.configure != null) {
            pendingConfig = PendingWidget(appWidgetId, updatedInfo, result)
            val configIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_CONFIGURE)
                .setComponent(updatedInfo.configure)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            try {
                act.startActivityForResult(configIntent, REQUEST_WIDGET_CONFIG)
            } catch (e: Exception) {
                pendingConfig = null
                proceedAfterBinding(appWidgetId, updatedInfo, result)
            }
        } else {
            proceedAfterBinding(appWidgetId, updatedInfo, result)
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_BIND_WIDGET) {
            val bind = pendingBind ?: return true
            pendingBind = null

            if (resultCode == Activity.RESULT_OK) {
                val info = mgr.getAppWidgetInfo(bind.appWidgetId)
                if (info == null) {
                    bind.result.error("WIDGET_BIND_FAILED", "Widget info not found after binding", null)
                    return true
                }

                if (info.configure != null) {
                    pendingConfig = PendingWidget(
                        bind.appWidgetId, info, bind.result
                    )
                    val configIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_CONFIGURE)
                        .setComponent(info.configure)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, bind.appWidgetId)
                    try {
                        (mainActivity ?: return true)
                            .startActivityForResult(configIntent, REQUEST_WIDGET_CONFIG)
                    } catch (e: Exception) {
                        pendingConfig = null
                        proceedAfterBinding(bind.appWidgetId, info, bind.result)
                    }
                } else {
                    proceedAfterBinding(bind.appWidgetId, info, bind.result)
                }
            } else {
                host.deleteAppWidgetId(bind.appWidgetId)
                bind.result.success(null)
            }
            return true
        }

        if (requestCode == REQUEST_WIDGET_CONFIG) {
            val config = pendingConfig ?: return true
            pendingConfig = null

            if (resultCode != Activity.RESULT_OK) {
                config.result.success(null)
                return true
            }

            val info = mgr.getAppWidgetInfo(config.appWidgetId)
            if (info == null) {
                config.result.error("WIDGET_CONFIG_FAILED", "Widget info lost after configuration", null)
                return true
            }
            proceedAfterBinding(config.appWidgetId, info, config.result)
            return true
        }
        return false
    }

    fun createWidgetHostView(context: Context, appWidgetId: Int): View? {
        val info = mgr.getAppWidgetInfo(appWidgetId) ?: return null
        return try {
            val hostView = host.createView(context, appWidgetId, info)
            try {
                val rv = RemoteViews(info.provider.packageName, info.initialLayout)
                hostView.updateAppWidget(rv)
            } catch (_: Exception) { }
            val wrapper = RoundedFrameLayout(context, 16f)
            wrapper.addView(hostView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))
            wrapper
        } catch (_: Exception) {
            null
        }
    }

    private fun proceedAfterBinding(
        appWidgetId: Int,
        info: AppWidgetProviderInfo,
        result: MethodChannel.Result,
    ) {
        val label = try {
            info.loadLabel(appContext.packageManager) ?: info.provider.className
        } catch (_: Exception) {
            info.provider.className
        }
        val entry = mapOf(
            "appWidgetId" to appWidgetId,
            "providerPackage" to info.provider.packageName,
            "providerLabel" to label,
            "minWidthDp" to info.minWidth,
            "minHeightDp" to info.minHeight,
        )
        saveWidgetEntry(entry)
        result.success(entry)
    }

    fun refreshWidgets(result: MethodChannel.Result) {
        try {
            val entries = loadWidgetEntries().mapNotNull { entry ->
                val id = entry.optInt("appWidgetId", -1)
                if (id < 0) return@mapNotNull null

                val info = mgr.getAppWidgetInfo(id) ?: return@mapNotNull null

                mapOf(
                    "appWidgetId" to id,
                    "providerPackage" to (info.provider?.packageName ?: ""),
                    "providerLabel" to (try {
                        info.loadLabel(appContext.packageManager) ?: info.provider?.className ?: ""
                    } catch (_: Exception) {
                        info.provider?.className ?: ""
                    }),
                    "minWidthDp" to info.minWidth,
                    "minHeightDp" to info.minHeight,
                )
            }
            saveWidgetEntries(entries)
            result.success(entries)
        } catch (e: Exception) {
            result.error("WIDGET_REFRESH_FAILED", e.message, null)
        }
    }

    fun removeWidget(appWidgetId: Int, result: MethodChannel.Result) {
        try {
            host.deleteAppWidgetId(appWidgetId)
            val entries = loadWidgetEntries()
                .filter { it.optInt("appWidgetId", -1) != appWidgetId }
                .map { jsonToMap(it) }
            saveWidgetEntries(entries)
            result.success(true)
        } catch (e: Exception) {
            result.error("WIDGET_REMOVE_FAILED", e.message, null)
        }
    }

    fun setWidgetOrder(widgetIds: List<Int>, result: MethodChannel.Result) {
        try {
            val entries = loadWidgetEntries()
            val idToEntry = entries.associateBy { it.optInt("appWidgetId", -1) }
            val reordered = widgetIds.mapNotNull { idToEntry[it] }
            saveWidgetEntries(reordered.map { jsonToMap(it) })
            result.success(true)
        } catch (e: Exception) {
            result.error("WIDGET_REORDER_FAILED", e.message, null)
        }
    }

    // ── Persistence ─────────────────────────────────────────────────────────────

    private fun widgetFile(): File = File(appContext.filesDir, PREFS_FILE)

    private fun loadWidgetEntries(): List<JSONObject> {
        return try {
            val file = widgetFile()
            if (!file.exists()) return emptyList()
            val text = file.readText()
            val arr = JSONArray(text)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun jsonToMap(obj: JSONObject): Map<String, Any?> {
        val m = mutableMapOf<String, Any?>()
        for (key in obj.keys()) {
            val v = obj.opt(key)
            if (v != null && v != JSONObject.NULL) {
                m[key] = v
            }
        }
        return m
    }

    private fun saveWidgetEntries(entries: List<Map<String, Any?>>) {
        try {
            val arr = JSONArray()
            for (e in entries) {
                val obj = JSONObject()
                for ((k, v) in e) {
                    when (v) {
                        is Int -> obj.put(k, v)
                        is String -> obj.put(k, v)
                        is Boolean -> obj.put(k, v)
                        is ByteArray -> {}
                        else -> obj.put(k, v)
                    }
                }
                arr.put(obj)
            }
            widgetFile().writeText(arr.toString(2))
        } catch (_: Exception) { }
    }

    private fun saveWidgetEntry(entry: Map<String, Any?>) {
        val entries = loadWidgetEntries().map { jsonToMap(it) }.toMutableList()
        val id = entry["appWidgetId"] as? Int ?: return
        entries.removeAll { it["appWidgetId"] == id }
        entries.add(entry)
        saveWidgetEntries(entries)
    }
}

private class RoundedFrameLayout(
    context: Context,
    private val radiusDp: Float,
) : FrameLayout(context) {
    private val path = Path()
    private val rect = RectF()
    private val radiusPx = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, radiusDp,
        context.resources.displayMetrics
    )

    override fun dispatchDraw(canvas: Canvas) {
        rect.set(0f, 0f, width.toFloat(), height.toFloat())
        path.reset()
        path.addRoundRect(rect, radiusPx, radiusPx, Path.Direction.CW)
        canvas.save()
        canvas.clipPath(path)
        super.dispatchDraw(canvas)
        canvas.restore()
    }
}
