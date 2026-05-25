import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Bounded, per-skill memory persisted as JSON in the app documents dir.
/// Stores summaries only (last 200 chars of each result) and caps at 20
/// entries so it can never grow unbounded.
class SkillMemory {
  final String skillName;
  final List<Map<String, String>> _entries = [];

  SkillMemory(this.skillName);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/wrangl_memory');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$skillName.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is List) {
        _entries
          ..clear()
          ..addAll(data.map((e) => (e as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))));
      }
    } catch (_) {
      // Corrupt/unreadable memory is non-fatal — start empty.
    }
  }

  Future<void> add(String task, String result) async {
    final summary =
        result.length > 200 ? result.substring(result.length - 200) : result;
    _entries.add({'task': task, 'result': summary});
    if (_entries.length > 20) {
      _entries.removeRange(0, _entries.length - 20);
    }
    try {
      await (await _file()).writeAsString(jsonEncode(_entries));
    } catch (_) {}
  }

  /// Render recent entries for injection into the system prompt.
  String asContext() {
    if (_entries.isEmpty) return '';
    return _entries
        .map((e) => '- ${e['task']} → ${e['result']}')
        .join('\n');
  }
}
