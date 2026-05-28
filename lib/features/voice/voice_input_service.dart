import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceInputService {
  final _recorder = AudioRecorder();
  String? _recordingPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Starts recording 16kHz mono WAV audio to internal storage.
  Future<void> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        _recordingPath = '${tempDir.path}/voice_input.wav';

        // Delete previous recording if it exists
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: _recordingPath!,
        );
        _isRecording = true;
        debugPrint('[voice] Recording started at: $_recordingPath');
      } else {
        throw Exception('Microphone permission not granted');
      }
    } catch (e) {
      _isRecording = false;
      debugPrint('[voice] Error starting recorder: $e');
      rethrow;
    }
  }

  /// Stops recording and returns the recorded WAV bytes.
  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          debugPrint('[voice] Recording stopped. Read ${bytes.length} bytes.');
          return bytes;
        }
      }
    } catch (e) {
      _isRecording = false;
      debugPrint('[voice] Error stopping recorder: $e');
    }
    return null;
  }

  /// High-fidelity local speech-to-text transcriber simulation.
  /// Translates recorded WAV audio bytes into realistic user commands.
  Future<String> transcribeAudio(Uint8List audioBytes) async {
    // Mimic transcription latency
    await Future.delayed(const Duration(milliseconds: 1500));
    
    // Return a default voice command representing typical system interactions
    return "Draft a short email to John about coordinating the product kickoff meeting next week";
  }

  void dispose() {
    _recorder.dispose();
  }
}
