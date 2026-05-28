import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'voice_input_service.dart';

class VoiceOverlayWidget extends StatefulWidget {
  final VoidCallback onCancel;
  final Function(String transcribedText) onTranscribed;

  const VoiceOverlayWidget({
    super.key,
    required this.onCancel,
    required this.onTranscribed,
  });

  @override
  State<VoiceOverlayWidget> createState() => _VoiceOverlayWidgetState();
}

class _VoiceOverlayWidgetState extends State<VoiceOverlayWidget> with TickerProviderStateMixin {
  final _voiceService = VoiceInputService();
  bool _isListening = false;
  bool _isTranscribing = false;
  String _statusText = "Listening...";
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    
    _startRecording();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      _isListening = true;
      _isTranscribing = false;
      _statusText = "Listening...";
    });
    HapticFeedback.mediumImpact();
    try {
      await _voiceService.startRecording();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = "Microphone error. Try again.";
          _isListening = false;
        });
      }
    }
  }

  Future<void> _finishRecording() async {
    if (!_isListening) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isListening = false;
      _isTranscribing = true;
      _statusText = "Analyzing speech...";
    });

    final audioBytes = await _voiceService.stopRecording();
    if (audioBytes != null) {
      final text = await _voiceService.transcribeAudio(audioBytes);
      if (mounted) {
        widget.onTranscribed(text);
      }
    } else {
      if (mounted) {
        setState(() {
          _statusText = "No audio captured.";
          _isTranscribing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.90),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsating visual waves
            Stack(
              alignment: Alignment.center,
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.6).animate(
                    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutCirc),
                  ),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF2200).withValues(alpha: 0.15),
                    ),
                  ),
                ),
                ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.3).animate(
                    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF2200).withValues(alpha: 0.25),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _isListening ? _finishRecording : null,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF2200),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFF2200),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _isTranscribing ? Icons.hourglass_empty : Icons.mic,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Text(
              _statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isListening ? "Tap red hub to stop recording" : "Processing intent...",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 64),
            // Cancel button
            if (!_isTranscribing)
              OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onCancel();
                },
                icon: const Icon(Icons.close, size: 16),
                label: const Text(
                  "CANCEL",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.6),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
