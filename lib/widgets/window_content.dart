import 'package:flutter/material.dart';
import '../models/window_data.dart';

class WindowContent extends StatelessWidget {
  final WindowData data;

  const WindowContent({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    switch (data.type) {
      case WindowContentType.flutterScreen:
        return data.flutterChild ?? _placeholder('Flutter Screen');
      case WindowContentType.androidApp:
        return _androidAppPreview();
      case WindowContentType.appWidget:
        return _appWidgetView();
    }
  }

  Widget _placeholder(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apps, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _androidAppPreview() {
    if (data.screenId == null) return _placeholder('No app running');
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_android, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              data.packageName ?? 'Android App',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'VirtualDisplay: ${data.screenId}',
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appWidgetView() {
    // Uses AndroidView with the widget host factory
    // Will be properly implemented when appWidgetId is available
    return _placeholder('App Widget #${data.appWidgetId}');
  }
}

class AndroidAppWindow extends StatefulWidget {
  final String screenId;

  const AndroidAppWindow({super.key, required this.screenId});

  @override
  State<AndroidAppWindow> createState() => _AndroidAppWindowState();
}

class _AndroidAppWindowState extends State<AndroidAppWindow> {
  @override
  Widget build(BuildContext context) {
    // Placeholder for frame streaming from VirtualDisplay
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_android, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Screen: ${widget.screenId}',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class AppWidgetWindow extends StatelessWidget {
  final int widgetId;

  const AppWidgetWindow({super.key, required this.widgetId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'App Widget #$widgetId',
        style: const TextStyle(color: Colors.white54),
      ),
    );
  }
}
