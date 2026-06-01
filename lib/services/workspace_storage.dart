import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/workspace.dart';

class WorkspaceStorage {
  List<Workspace> _workspaces = [];
  int _activeIndex = 0;

  List<Workspace> get workspaces => _workspaces;
  Workspace get activeWorkspace =>
      _workspaces.isNotEmpty ? _workspaces[_activeIndex] : Workspace(name: 'Home');
  int get activeIndex => _activeIndex;

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/workspaces.json');
  }

  Future<void> load() async {
    final f = await _file;
    if (!await f.exists()) {
      _workspaces = [Workspace(name: 'Home')];
      return;
    }
    try {
      final raw = await f.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _workspaces = (data['workspaces'] as List<dynamic>)
          .map((w) => Workspace.fromJson(w as Map<String, dynamic>))
          .toList();
      _activeIndex = data['activeIndex'] as int? ?? 0;
      if (_activeIndex >= _workspaces.length) _activeIndex = 0;
    } catch (_) {
      _workspaces = [Workspace(name: 'Home')];
    }
  }

  Future<void> save() async {
    final f = await _file;
    final data = {
      'activeIndex': _activeIndex,
      'workspaces': _workspaces.map((w) => w.toJson()).toList(),
    };
    await f.writeAsString(jsonEncode(data));
  }

  Future<void> switchWorkspace(int index) async {
    if (index < 0 || index >= _workspaces.length) return;
    _activeIndex = index;
    await save();
  }

  Future<void> addWorkspace(String name) async {
    _workspaces.add(Workspace(name: name));
    await save();
  }

  Future<void> removeWorkspace(int index) async {
    if (_workspaces.length <= 1) return;
    _workspaces.removeAt(index);
    if (_activeIndex >= _workspaces.length) {
      _activeIndex = _workspaces.length - 1;
    }
    await save();
  }

  Future<void> renameWorkspace(int index, String name) async {
    if (index < 0 || index >= _workspaces.length) return;
    _workspaces[index].name = name;
    await save();
  }
}
