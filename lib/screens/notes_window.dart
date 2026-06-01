import 'package:flutter/material.dart';
import '../features/notes/note_store.dart';

class NotesWindowContent extends StatefulWidget {
  const NotesWindowContent({super.key});

  @override
  State<NotesWindowContent> createState() => _NotesWindowContentState();
}

class _NotesWindowContentState extends State<NotesWindowContent> {
  final NoteStore _store = NoteStore();
  List<Map<String, dynamic>> _notes = [];
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await _store.search('');
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty &&
        _contentCtrl.text.trim().isEmpty) return;
    await _store.save(_titleCtrl.text.trim(), _contentCtrl.text.trim());
    _titleCtrl.clear();
    _contentCtrl.clear();
    setState(() => _isEditing = false);
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          if (_isEditing)
            _buildEditor()
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.note_outlined,
                      color: Color(0xFFF0EFEB), size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Notes',
                    style: TextStyle(
                      color: Color(0xFFF0EFEB),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _isEditing = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5C35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '+ New',
                        style: TextStyle(
                          color: Color(0xFFF0EFEB),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: Color(0xFF444444), height: 1),
          Expanded(
            child: _notes.isEmpty
                ? const Center(
                    child: Text(
                      'No notes yet',
                      style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _notes.length,
                    itemBuilder: (_, i) {
                      final note = _notes[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              note['title'] as String? ?? '',
                              style: const TextStyle(
                                color: Color(0xFFF0EFEB),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (note['title'] != null &&
                                (note['title'] as String).isNotEmpty)
                              const SizedBox(height: 4),
                            Text(
                              note['content'] as String? ?? '',
                              style: const TextStyle(
                                color: Color(0xFFBBBBBB),
                                fontSize: 12,
                              ),
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Color(0xFFF0EFEB), fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Title',
              hintStyle: TextStyle(color: Color(0xFF666666)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TextField(
              controller: _contentCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Write something...',
                hintStyle: TextStyle(color: Color(0xFF666666)),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => _isEditing = false);
                  _titleCtrl.clear();
                  _contentCtrl.clear();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF444444),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFF0EFEB), fontSize: 12),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _save,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5C35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(color: Color(0xFFF0EFEB), fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
