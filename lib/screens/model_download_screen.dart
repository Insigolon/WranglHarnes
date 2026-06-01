import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../agent/model_config.dart';
import '../main.dart' show RadialLauncher;

class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback? onModelReady;
  const ModelDownloadScreen({super.key, this.onModelReady});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

enum _DlStatus { initializing, downloading, loading, optimizing, ready, error }

class _ModelDownloadScreenState extends State<ModelDownloadScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveCtrl;
  bool _isDownloading = false;
  double _progress = 0.0;
  _DlStatus _status = _DlStatus.initializing;
  String _speedText = '';
  String _etaText = '';
  int _totalBytes = 0;
  final Stopwatch _speedWatch = Stopwatch();
  int _lastSampleBytes = 0;

  static const _modelUrl = ModelConfig.url;

  static const _statusLabels = {
    _DlStatus.initializing: 'INITIALIZING',
    _DlStatus.downloading: 'DOWNLOADING',
    _DlStatus.loading: 'LOADING',
    _DlStatus.optimizing: 'OPTIMIZING',
    _DlStatus.ready: 'READY',
    _DlStatus.error: 'ERROR',
  };

  @override
  void initState() {
    super.initState();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _checkExistingModel();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  Future<String> _modelPath() => ModelConfig.path();

  Future<void> _checkExistingModel() async {
    final path = await _modelPath();
    final file = File(path);

    if (await file.exists() && await file.length() > ModelConfig.minSize) {
      setState(() => _status = _DlStatus.ready);
      widget.onModelReady?.call();
      await Future.delayed(const Duration(milliseconds: 600));
      await _startApp();
      return;
    }

    setState(() => _status = _DlStatus.downloading);
    await _downloadModel();
  }

  Future<void> _downloadModel() async {
    final path = await _modelPath();
    final partialPath = '$path.part';
    int resumed = 0;
    File? partialFile;

    if (File(partialPath).existsSync()) {
      partialFile = File(partialPath);
      resumed = await partialFile.length();
    }

    final client = http.Client();
    StreamSubscription<List<int>>? sub;
    final completer = Completer<void>();

    setState(() {
      _isDownloading = true;
      _progress = resumed > 0 ? 0.0 : 0.0;
      _status = resumed > 0 ? _DlStatus.loading : _DlStatus.downloading;
      _speedText = '';
      _etaText = '';
    });

    void updateSpeed(int totalDownloaded) {
      final elapsed = _speedWatch.elapsedMilliseconds;
      if (elapsed < 800) return;
      final bytesSinceLastSample = totalDownloaded - _lastSampleBytes;
      final speedBps = bytesSinceLastSample / (elapsed / 1000);
      _speedWatch.reset();
      _lastSampleBytes = totalDownloaded;
      _speedText = _fmtSpeed(speedBps);
      if (_totalBytes > 0 && speedBps > 0) {
        final remaining = _totalBytes - totalDownloaded;
        final secs = remaining / speedBps;
        _etaText = secs < 60
            ? '~${secs.round()}s'
            : '~${(secs / 60).round()}m ${(secs % 60).round()}s';
      }
    }

    try {
      final request = http.Request('GET', Uri.parse(_modelUrl));
      if (resumed > 0) {
        request.headers['Range'] = 'bytes=$resumed-';
      }
      final response = await client.send(request);

      if (response.statusCode == 416) {
        // Range not satisfiable — file is complete, rename and move on.
        await partialFile!.rename(path);
        setState(() => _status = _DlStatus.optimizing);
        await Future.delayed(const Duration(milliseconds: 800));
        await _startApp();
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException(
          'Download failed (HTTP ${response.statusCode})',
        );
      }

      _totalBytes =
          (response.contentLength ?? 0) + resumed;
      int downloadedSoFar = resumed;
      final sink = File(partialPath).openWrite(mode: FileMode.writeOnlyAppend);
      _speedWatch.start();
      _lastSampleBytes = resumed;

      sub = response.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloadedSoFar += chunk.length;
          setState(() {
            if (_totalBytes > 0) {
              _progress = downloadedSoFar / _totalBytes;
            }
            _status = _DlStatus.loading;
          });
          updateSpeed(downloadedSoFar);
        },
        onDone: () {
          sink.close();
          completer.complete();
        },
        onError: (e) {
          sink.close();
          completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;

      if (_totalBytes > 0 && downloadedSoFar < _totalBytes) {
        throw HttpException(
          'Incomplete download '
          '(${_fmt(downloadedSoFar)} of ${_fmt(_totalBytes)})',
        );
      }

      final dest = File(path);
      if (dest.existsSync()) await dest.delete();
      await File(partialPath).rename(path);

      setState(() => _status = _DlStatus.optimizing);
      await Future.delayed(const Duration(milliseconds: 800));
      await _startApp();
    } catch (e) {
      debugPrint('[download] error: $e');
      if (File(partialPath).existsSync()) {
        final partialLen = await File(partialPath).length();
        debugPrint('[download] partial saved: ${_fmt(partialLen)}');
      }
      if (mounted) {
        setState(() {
          _status = _DlStatus.error;
          _isDownloading = false;
        });
      }
    } finally {
      await sub?.cancel();
      client.close();
    }
  }

  Future<void> _startApp() async {
    if (widget.onModelReady != null) {
      widget.onModelReady!();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RadialLauncher()),
      );
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

  String _fmtSpeed(double bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bps >= 1024) {
      return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${bps.round()} B/s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            /// TOP CONTENT
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '[ Gemma4-e2b]',
                  style: TextStyle(
                    color: Color(0xFFFFB3A7),
                    fontSize: 26,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 12),

                /// 🔥 FULL WIDTH WAVE (FIXED)
                SizedBox(
                  width: double.infinity,
                  height: 160,
                  child: AnimatedBuilder(
                    animation: _waveCtrl,
                    builder: (_, _) =>
                        CustomPaint(painter: _WavePainter(_waveCtrl.value)),
                  ),
                ),
              ],
            ),

            /// 🔥 BOTTOM PANEL (ANCHORED)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFFFFB3A7), thickness: 1),

                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HARNESS'),
                          Text('RESTORE'),
                          Text('ACTIVE'),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WRANGL_V0'),
                          Text('INSTALL'),
                          Text('RESTART REQUIRED'),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      AnimatedOpacity(
                        opacity: _status == _DlStatus.error ? 1.0 : 0.6,
                        duration: const Duration(milliseconds: 800),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _status == _DlStatus.error
                                ? const Color(0xFFFF2200)
                                : const Color(0xFFFFB3A7),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _statusLabels[_status]!,
                        style: TextStyle(
                          color: _status == _DlStatus.error
                              ? const Color(0xFFFF2200)
                              : const Color(0xFFFFB3A7),
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (_isDownloading && _progress > 0) ...[
                    Text(
                      '${(_progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFFFFB3A7),
                        fontSize: 28,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (_speedText.isNotEmpty)
                          Text(
                            _speedText,
                            style: TextStyle(
                              color: const Color(0xFFFFB3A7).withValues(alpha: 0.6),
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                        if (_speedText.isNotEmpty && _etaText.isNotEmpty)
                          const SizedBox(width: 16),
                        if (_etaText.isNotEmpty)
                          Text(
                            _etaText,
                            style: TextStyle(
                              color: const Color(0xFFFFB3A7).withValues(alpha: 0.6),
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🔥 WAVE PAINTER (DENSE + CORRECT)
class _WavePainter extends CustomPainter {
  final double t;
  _WavePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 48; // 🔥 denser = better
    const rows = 10;

    final cellW = size.width / cols;
    final cellH = size.height / rows;

    final paint = Paint()..color = const Color(0xFFFFB3A7);

    for (int x = 0; x < cols; x++) {
      final wave = sin(x * 0.25 + t * 2 * pi) + 0.4 * sin(x * 0.6 + t * 3);

      final height = ((wave + 1.4) / 2.4 * rows).floor();

      for (int y = 0; y < rows; y++) {
        final px = x * cellW + 2;
        final py = y * cellH + 2;

        if (rows - y <= height) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(px, py, cellW - 4, cellH - 4),
              const Radius.circular(4),
            ),
            paint,
          );
        } else {
          canvas.drawCircle(
            Offset(px + cellW / 2, py + cellH / 2),
            1.2,
            paint..color = const Color(0x55FFB3A7),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
