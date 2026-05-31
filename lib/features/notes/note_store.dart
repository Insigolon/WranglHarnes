import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class NoteStore {
  List<Map<String, dynamic>>? _cache;

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/notes.json');
  }

  Future<List<Map<String, dynamic>>> _loadAll() async {
    if (_cache != null) return _cache!;
    final f = await _file;
    if (!await f.exists()) {
      _cache = [];
      return _cache!;
    }
    final raw = await f.readAsString();
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _cache = list;
    return list;
  }

  Future<void> _persist(List<Map<String, dynamic>> notes) async {
    final f = await _file;
    await f.writeAsString(jsonEncode(notes));
    _cache = notes;
  }

  Future<void> save(String title, String content) async {
    final notes = await _loadAll();
    notes.add({
      'title': title,
      'content': content,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _persist(notes);
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final notes = await _loadAll();
    final q = query.toLowerCase();
    return notes.where((n) {
      final title = (n['title'] as String? ?? '').toLowerCase();
      final content = (n['content'] as String? ?? '').toLowerCase();
      return title.contains(q) || content.contains(q);
    }).toList();
  }

}
