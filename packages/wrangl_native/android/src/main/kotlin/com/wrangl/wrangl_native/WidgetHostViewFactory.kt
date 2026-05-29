package com.wrangl.wrangl_native

import android.content.Context
import android.view.View
import android.widget.TextView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class WidgetHostViewFactory(
    private val widgetHostManager: WidgetHostManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as Map<*, *>
        val appWidgetId = (params["appWidgetId"] as Number).toInt()
        return WidgetHostPlatformView(context, widgetHostManager, appWidgetId)
    }
}

class WidgetHostPlatformView(
    context: Context,
    widgetHostManager: WidgetHostManager,
    appWidgetId: Int,
) : PlatformView {

    private val view: View = widgetHostManager.createWidgetHostView(context, appWidgetId)
        ?: TextView(context).apply {
            text = "Widget unavailable"
            setTextColor(0xFF666666.toInt())
            textSize = 14f
        }

    override fun getView(): View = view
    override fun dispose() { }
}
