import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../agent/agent_provider.dart';
import '../main.dart' show RadialLauncher;

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  _ModelDownloadScreenState createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = 'Select a model to download';

  final _models = {
    'TinyLlama (Fast, ~700MB)': 'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
    'Phi-2 (Smarter, ~1.7GB)': 'https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf',
  };

  @override
  void initState() {
    super.initState();
    _checkExistingModel();
  }

  Future<void> _checkExistingModel() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList();
    if (files.isNotEmpty) {
      _startApp(files.first.path);
    }
  }

  Future<void> _downloadModel(String name, String url) async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'Starting download...';
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final filename = url.split('/').last;
      final path = '\${dir.path}/\$filename';

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      final total = response.contentLength ?? 0;
      
      int downloaded = 0;
      final file = File(path);
      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (total > 0) {
          setState(() {
            _progress = downloaded / total;
            _statusMessage = 'Downloading \$name: \${(_progress * 100).toStringAsFixed(1)}%';
          });
        }
      }).asFuture();

      await sink.close();
      _startApp(path);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download failed: \$e';
      });
    }
  }

  void _startApp(String modelPath) {
    context.read<AgentProvider>().init(modelPath);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RadialLauncher()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download, size: 64, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isDownloading) ...[
                LinearProgressIndicator(value: _progress, color: Colors.purpleAccent),
              ] else ...[
                for (final entry in _models.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: () => _downloadModel(entry.key, entry.value),
                      child: Text(entry.key),
                    ),
                  ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
