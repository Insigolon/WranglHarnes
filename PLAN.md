# Wrangl — LLM Integration Plan

## Current State (Done)

- [x] Skill system removed (assets/skills/, agent/skills/, agent/tools/)
- [x] `WranglHarness` simplified — no skills, direct tool dispatch
- [x] `AgentLoop` simplified — no control labels, no per-skill memory
- [x] Rust cleaned — `route_skill`/`SkillDesc` removed, keep `decide_next`/`evaluate`/`parse_output`
- [x] `lib/core/inference/gemma_engine.dart` — wrapper over GemmaModelClient
- [x] `lib/core/agent/tool_registry.dart` — global tools (list_apps, open_app, web_search, capture_screen)
- [x] Feature stubs created under `lib/features/`
- [x] FRB bindings regenerated
- [x] Tests passing (2/2)
- [x] `flutter analyze` clean

---

## Priority 1 — Voice Input (Primary OS Input)

**Goal:** Long-press hub → voice recording → Gemma ASR + intent → execute action

### Steps
1. Add `record` package to pubspec.yaml
2. Implement `lib/features/voice/voice_input_service.dart`:
   - Mic capture via `record` (16kHz mono WAV)
   - VAD auto-stop
   - `startRecording()` / `onRecordingComplete` stream
3. Wire into `_openOverlay()` in `main.dart`:
   - Long-press → voice prompt first (instead of/in addition to overlay)
4. Voice → Gemma multimodal → parse intent JSON → dispatch

### Files
- `lib/features/voice/voice_input_service.dart`
- `lib/features/voice/voice_overlay_widget.dart`
- `lib/main.dart` (_openOverlay → voice-first path)
- `lib/core/inference/gemma_engine.dart` (audio support in `generateMultimodal`)

---

## Priority 2 — Populate Feature Services

### File Search
- `lib/features/file_search/file_index_service.dart`: scan device files → SQLite index → NL query via Gemma
- Tool: `search_files(query, type?)` in kToolRegistry

### OCR
- `lib/features/ocr/camera_capture_service.dart`: live camera via `camera` package
- `lib/features/ocr/ocr_engine.dart`: image → Gemma vision → extracted text
- Tool: `ocr_capture()` in kToolRegistry

### Document Summarization
- `lib/features/summarizer/document_loader.dart`: PDF/DOCX/TXT → plain text
- `lib/features/summarizer/summarize_service.dart`: text → Gemma → bullet points
- Tool: `summarize_file(path)` in kToolRegistry

### Email/SMS Drafting
- `lib/features/messaging/draft_service.dart`: thread context + tone → Gemma draft
- Tool: `draft_message(context, tone)` in kToolRegistry

### Note Taking
- `lib/features/notes/note_capture_widget.dart`: voice/text → Gemma cleanup
- `lib/features/notes/note_store.dart`: SQLite persistence
- Tool: `create_note(text)` in kToolRegistry

---

## Priority 3 — Native Plugin Extensions

| Feature | Android Change Needed | Status |
|---|---|---|
| File search | MediaStore scan via MethodChannel | New method in `WranglNativePlugin.kt` |
| Settings deep-links | Settings.ACTION_* intent map | New method in `WranglNativePlugin.kt` |
| SMS reading | READ_SMS + Telephony API | New method in `WranglNativePlugin.kt` |
| Voice audio route | AudioManager focus + routing | Already partial via Assist API |

---

## Priority 4 — Settings Search

- `lib/features/settings_search/settings_search_service.dart`:
  1. Build JSON map of `{description -> Settings.ACTION_*}` in Kotlin
  2. Gemma matches query to setting key
  3. Launch via `android_intent_plus`
- Tool: `open_setting(query)` in kToolRegistry

---

## Priority 5 — Agentic Multi-Step UI

- `lib/core/agent/agent_ui_widget.dart`:
  - Animated step list (searching → reading → drafting)
  - Cancel button per step
  - Max 10 tool calls guardrail
- Hook into `_OverlayAgent` state in `bubble_overlay.dart`

---

## Dependencies to Add

```yaml
record: ^5.0.0          # Mic capture
camera: ^0.11.0          # Live camera
image_picker: ^1.0.0     # Gallery selection
sqflite: ^2.3.0          # Local DB
flutter_tts: ^4.0.0      # Text-to-speech
share_plus: ^7.0.0       # Share sheet
android_intent_plus: ^5.0.0  # Android intents
flutter_local_notifications: ^17.0.0  # Reminders
pdfx: ^2.0.0             # PDF extraction
```

## Build & Deploy

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
