import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
  String _statusMessage = 'Checking for Gemma 4 model...';

  static const _modelFilename = 'gemma-4-E2B-it.litertlm';
  static const _modelDisplayName = 'Gemma 4 2B (~2.6 GB)';
  static const _modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  @override
  void initState() {
    super.initState();
    _checkExistingModel();
  }

  Future<String> _modelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_modelFilename';
  }

  Future<void> _checkExistingModel() async {
    final path = await _modelPath();
    final file = File(path);
    if (await file.exists() && await file.length() > 100 * 1024 * 1024) {
      await _startApp(path);
      return;
    }
    if (mounted) {
      setState(() => _statusMessage = 'Model not found. Starting download...');
      await _downloadModel();
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'Starting download...';
    });

    final path = await _modelPath();
    final partialPath = '$path.part';

    try {
      if (File(partialPath).existsSync()) {
        await File(partialPath).delete();
      }

      final request = http.Request('GET', Uri.parse(_modelUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw HttpException('Download failed (status ${response.statusCode})');
      }

      final total = response.contentLength ?? 0;
      int downloaded = 0;
      final sink = File(partialPath).openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (total > 0) {
          setState(() {
            _progress = downloaded / total;
            _statusMessage =
                'Downloading: ${(_progress * 100).toStringAsFixed(1)}%'
                ' (${_fmt(downloaded)} / ${_fmt(total)})';
          });
        }
      }).asFuture();

      await sink.close();

      if (total > 0 && downloaded < total) {
        throw HttpException(
            'Incomplete download (${_fmt(downloaded)} of ${_fmt(total)})');
      }

      final dest = File(path);
      if (dest.existsSync()) await dest.delete();
      await File(partialPath).rename(path);

      await _startApp(path);
    } catch (e) {
      debugPrint('[download] Error: $e');
      if (File(partialPath).existsSync()) {
        try { await File(partialPath).delete(); } catch (_) {}
      }
      if (mounted) {
        setState(() => _statusMessage = 'Download failed: $e\n\nTap to retry.');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _startApp(String modelPath) async {
    final provider = context.read<AgentProvider>();
    try {
      setState(() => _statusMessage = 'Loading model...');

      // Register the downloaded file with flutter_gemma and initialise the provider
      await provider.init(modelPath);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RadialLauncher()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to start: $e')));
      setState(() => _statusMessage = 'Model load failed.\n$e');
    }
  }

  String _fmt(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '$bytes B';
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
                LinearProgressIndicator(
                  value: _progress,
                  color: Colors.purpleAccent,
                ),
              ] else ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _downloadModel,
                  child: const Text(_modelDisplayName),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
