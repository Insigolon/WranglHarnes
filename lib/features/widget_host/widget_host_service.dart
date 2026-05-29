import 'package:flutter/foundation.dart';
import 'widget_host.dart';

class WidgetHostService extends ValueNotifier<List<WidgetHostEntry>> {
  WidgetHostService() : super(const []);

  Future<List<WidgetHostProvider>> getProviders() =>
      WidgetHost.listProviders();

  Future<void> load() async {
    final widgets = await WidgetHost.refreshWidgets();
    value = widgets;
  }

  Future<void> addWidget(String providerPackage, String providerClass) async {
    final entry = await WidgetHost.bindWidget(providerPackage, providerClass);
    if (entry == null) return;
    value = [...value, entry];
  }

  Future<void> remove(int appWidgetId) async {
    await WidgetHost.removeWidget(appWidgetId);
    value = value.where((w) => w.appWidgetId != appWidgetId).toList();
  }

  Future<void> move(int from, int to) async {
    if (from == to) return;
    final widgets = [...value];
    final item = widgets.removeAt(from);
    widgets.insert(to, item);
    await WidgetHost.reorderWidgets(widgets.map((w) => w.appWidgetId).toList());
    value = widgets;
  }
}
