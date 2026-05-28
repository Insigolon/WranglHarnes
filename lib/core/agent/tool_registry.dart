import 'package:wrangl_native/wrangl_native.dart';

import '../../agent/harness/model.dart';
import '../../agent/harness/tool.dart';
import '../../features/file_search/file_index_service.dart';
import '../../features/messaging/draft_service.dart';
import '../../features/messaging/sms_reader_service.dart';
import '../../features/notes/note_store.dart';
import '../../features/settings_search/settings_search_service.dart';
import '../../features/ocr/ocr_engine.dart';
import '../../features/summarizer/document_loader.dart';
import '../../features/summarizer/summarize_service.dart';
import 'web_search.dart';

/// Global model completion reference, set by [setModelForTools] after the
/// model is loaded. Tools that need LLM access (OCR, summarizer, drafting)
/// use this to call back into Gemma.
ModelComplete? kModelComplete;

/// Call once after the model is loaded so model-dependent tools can use it.
void setModelForTools(ModelComplete model) {
  kModelComplete = model;
}

final Map<String, ToolSpec> kToolRegistry = {
  'list_apps': ToolSpec(
    name: 'list_apps',
    description: 'List installed apps as "label (package)". args: {}',
    stepLabel: 'Listing apps',
    run: (_) async {
      final apps = await WranglNative.getInstalledApps();
      return ToolResult.text(
        apps.map((a) => '${a['label']} (${a['packageName']})').join('; '),
      );
    },
  ),
  'open_app': ToolSpec(
    name: 'open_app',
    description: 'Open an app. args: {"package": "com.example.app"}',
    stepLabel: 'Opening app',
    run: (args) async {
      final pkg = args['package']?.toString() ?? '';
      if (pkg.isEmpty) return ToolResult.text('ERROR: missing "package"');
      final ok = await WranglNative.launchApp(pkg);
      return ToolResult.text(
        ok ? 'Opened $pkg' : 'ERROR: could not open $pkg',
      );
    },
  ),
  'web_search': ToolSpec(
    name: 'web_search',
    description:
        'Search the web for information. args: {"query": "search query here"}',
    stepLabel: 'Searching web',
    run: (args) async {
      final query = args['query']?.toString() ?? '';
      if (query.isEmpty) return ToolResult.text('ERROR: missing "query"');
      final results = await WebSearch.search(query);
      return ToolResult.text(results);
    },
  ),
  'capture_screen': ToolSpec(
    name: 'capture_screen',
    description: 'Capture the current screen contents. args: {}',
    stepLabel: 'Capturing screen',
    run: (_) async {
      final image = await WranglNative.captureScreen();
      return ToolResult.image(image);
    },
  ),
  // ── File Search ────────────────────────────────────────────────────────────
  'search_files': ToolSpec(
    name: 'search_files',
    description:
        'Search device files by name or type. args: {"query": "report", "type": "image|video|audio|document"}',
    stepLabel: 'Searching files',
    run: (args) async {
      final query = args['query']?.toString() ?? '';
      final type = args['type']?.toString();
      final svc = FileIndexService();
      List<Map<String, dynamic>> files;
      if (type != null && type.isNotEmpty && query.isEmpty) {
        files = await svc.searchByType(type);
      } else {
        files = await svc.search(query);
      }
      if (files.isEmpty) return ToolResult.text('No matching files found.');
      final lines = files.map((f) {
        final name = f['name'] ?? '?';
        final size = f['size'] ?? 0;
        final mime = f['mimeType'] ?? '';
        return '$name (${_formatSize(size as int)}) [$mime]';
      });
      return ToolResult.text(lines.join('\n'));
    },
  ),
  // ── OCR ────────────────────────────────────────────────────────────────────
  'ocr_extract': ToolSpec(
    name: 'ocr_extract',
    description: 'Capture screen and extract visible text via vision. args: {}',
    stepLabel: 'Reading screen',
    run: (_) async {
      final model = kModelComplete;
      if (model == null) {
        return ToolResult.text('ERROR: model not loaded');
      }
      final image = await WranglNative.captureScreen();
      final engine = OcrEngine(model);
      final text = await engine.extractText(image);
      return ToolResult.text(text);
    },
  ),
  // ── Document Summarization ─────────────────────────────────────────────────
  'summarize_file': ToolSpec(
    name: 'summarize_file',
    description:
        'Load and summarize a text file. args: {"path": "/path/to/file"}',
    stepLabel: 'Summarizing document',
    run: (args) async {
      final model = kModelComplete;
      if (model == null) {
        return ToolResult.text('ERROR: model not loaded');
      }
      final path = args['path']?.toString() ?? '';
      if (path.isEmpty) return ToolResult.text('ERROR: missing "path"');
      try {
        final loader = DocumentLoader();
        final text = await loader.loadText(path);
        final svc = SummarizeService(model);
        final summary = await svc.summarize(text);
        return ToolResult.text(summary);
      } catch (e) {
        return ToolResult.text('ERROR: $e');
      }
    },
  ),
  // ── Email/SMS Drafting ─────────────────────────────────────────────────────
  'draft_message': ToolSpec(
    name: 'draft_message',
    description:
        'Generate an email/message draft. args: {"context": "...", "tone": "professional|casual|formal"}',
    stepLabel: 'Drafting message',
    run: (args) async {
      final model = kModelComplete;
      if (model == null) {
        return ToolResult.text('ERROR: model not loaded');
      }
      final context = args['context']?.toString() ?? '';
      if (context.isEmpty) return ToolResult.text('ERROR: missing "context"');
      final tone = args['tone']?.toString() ?? 'professional';
      final svc = DraftService(model);
      final draft = await svc.generateDraft(context, tone);
      return ToolResult.text(draft);
    },
  ),
  // ── Settings Search ────────────────────────────────────────────────────────
  'open_setting': ToolSpec(
    name: 'open_setting',
    description:
        'Open a system settings page using natural language. args: {"query": "change wifi network"}',
    stepLabel: 'Opening settings',
    run: (args) async {
      final model = kModelComplete;
      if (model == null) return ToolResult.text('ERROR: model not loaded');
      final query = args['query']?.toString() ?? '';
      if (query.isEmpty) return ToolResult.text('ERROR: missing "query"');
      final svc = SettingsSearchService(model);
      final result = await svc.findAndLaunch(query);
      return ToolResult.text(result);
    },
  ),
  // ── SMS Reading ────────────────────────────────────────────────────────────
  'read_sms': ToolSpec(
    name: 'read_sms',
    description:
        'Read recent SMS messages. args: {"limit": 20}',
    stepLabel: 'Reading messages',
    run: (args) async {
      final limit = (args['limit'] as num?)?.toInt() ?? 20;
      try {
        final svc = SmsReaderService();
        final msgs = await svc.readRecent(limit: limit);
        if (msgs.isEmpty) return ToolResult.text('No SMS messages found.');
        final lines = msgs.map((m) {
          final sender = m['sender'] ?? '?';
          final body = m['body'] ?? '';
          return '$sender: $body';
        });
        return ToolResult.text(lines.join('\n'));
      } catch (e) {
        return ToolResult.text('ERROR: $e');
      }
    },
  ),
  // ── Note Taking ────────────────────────────────────────────────────────────
  'create_note': ToolSpec(
    name: 'create_note',
    description:
        'Save a note to local storage. args: {"title": "...", "content": "..."}',
    stepLabel: 'Saving note',
    run: (args) async {
      final title = args['title']?.toString() ?? '';
      final content = args['content']?.toString() ?? '';
      if (title.isEmpty) return ToolResult.text('ERROR: missing "title"');
      if (content.isEmpty) return ToolResult.text('ERROR: missing "content"');
      final store = NoteStore();
      await store.save(title, content);
      return ToolResult.text('Note "$title" saved.');
    },
  ),
  'search_notes': ToolSpec(
    name: 'search_notes',
    description: 'Search saved notes. args: {"query": "..."}',
    stepLabel: 'Searching notes',
    run: (args) async {
      final query = args['query']?.toString() ?? '';
      if (query.isEmpty) return ToolResult.text('ERROR: missing "query"');
      final store = NoteStore();
      final notes = await store.search(query);
      if (notes.isEmpty) return ToolResult.text('No matching notes found.');
      final lines = notes.map((n) {
        final title = n['title'] ?? '?';
        final content = n['content'] ?? '';
        final preview = content.length > 80
            ? '${content.substring(0, 80)}…'
            : content;
        return '$title: $preview';
      });
      return ToolResult.text(lines.join('\n'));
    },
  ),
};

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
