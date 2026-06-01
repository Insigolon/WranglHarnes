import 'package:flutter/material.dart';

class AgentWindowContent extends StatefulWidget {
  const AgentWindowContent({super.key});

  @override
  State<AgentWindowContent> createState() => _AgentWindowContentState();
}

class _AgentWindowContentState extends State<AgentWindowContent> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Icon(Icons.psychology_outlined,
                    color: Color(0xFFF0EFEB), size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Agent',
                  style: TextStyle(
                    color: Color(0xFFF0EFEB),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF444444), height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _statusCard('Gemma Model', 'Loaded', Icons.check_circle,
                    const Color(0xFF4CAF50)),
                const SizedBox(height: 8),
                _statusCard('Rust Bridge', 'Connected', Icons.check_circle,
                    const Color(0xFF4CAF50)),
                const SizedBox(height: 8),
                _statusCard('Tool Registry', '12 tools', Icons.build_outlined,
                    const Color(0xFF2196F3)),
                const SizedBox(height: 8),
                _statusCard('Sandbox', 'Ready', Icons.check_circle,
                    const Color(0xFF4CAF50)),
                const SizedBox(height: 16),
                const Text(
                  'Available Actions',
                  style: TextStyle(
                    color: Color(0xFFFF5C35),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _actionTile(Icons.web, 'Web Search'),
                _actionTile(Icons.file_copy_outlined, 'File Search'),
                _actionTile(Icons.document_scanner_outlined, 'OCR Capture'),
                _actionTile(Icons.summarize_outlined, 'Summarize'),
                _actionTile(Icons.email_outlined, 'Draft Message'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(
      String title, String status, IconData icon, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: statusColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style:
                  const TextStyle(color: Color(0xFFF0EFEB), fontSize: 13),
            ),
          ),
          Text(
            status,
            style: TextStyle(color: statusColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: const Color(0xFFF0EFEB), size: 18),
      title: Text(
        label,
        style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
      ),
      onTap: () {},
    );
  }
}
