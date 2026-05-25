import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/memory.dart' as rust;

const int _kMaxEntries = 20;
const int _kSummaryChars = 200;

/// Per-skill memory. Storage and bounds live in Rust; Dart just resolves the
/// platform docs path (since `path_provider` is a Flutter plugin) and forwards
/// load/append/render calls.
class SkillMemory {
  final String skillName;
  List<rust.MemoryEntry> _entries = const [];

  SkillMemory(this.skillName);

  Future<String> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/wrangl_memory');
    if (!await d.exists()) await d.create(recursive: true);
    return '${d.path}/$skillName.jsonl';
  }

  Future<void> load() async {
    _entries = rust.memoryLoad(path: await _path());
  }

  Future<void> add(String task, String result) async {
    rust.memoryAppend(
      path: await _path(),
      task: task,
      result: result,
      maxEntries: _kMaxEntries,
      summaryChars: _kSummaryChars,
    );
    // Keep the in-memory cache consistent so a subsequent asContext() call
    // reflects the new entry without re-reading from disk.
    _entries = rust.memoryLoad(path: await _path());
  }

  String asContext() => rust.memoryRender(entries: _entries);
}
