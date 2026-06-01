import 'window_data.dart';

class Workspace {
  String name;
  List<WindowData> windows;

  Workspace({required this.name, List<WindowData>? windows})
      : windows = windows ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'windows': windows.map((w) => w.toJson()).toList(),
      };

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
        name: json['name'] as String? ?? '',
        windows: (json['windows'] as List<dynamic>?)
                ?.map(
                    (w) => WindowData.fromJson(w as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
