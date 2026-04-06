import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService._internal();
  static final VoiceService instance = VoiceService._internal();

  final _speech = SpeechToText();
  final _tts = FlutterTts();

  bool _isInit = false;

  /// Initializes both Speech Recognition and Text-To-Speech systems.
  Future<bool> init() async {
    if (_isInit) return true;
    try {
      final speechInit = await _speech.initialize(
        onError: (e) => debugPrint('[VOICE] STT Error: $e'),
        onStatus: (s) => debugPrint('[VOICE] STT Status: $s'),
      );
      
      // Basic TTS config
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.setLanguage("en-US");
      
      _isInit = speechInit;
      return speechInit;
    } catch (e) {
      debugPrint('[VOICE] Init exception: $e');
      return false;
    }
  }

  /// Starts listening for voice commands.
  void startListening(void Function(String) onResult) {
    if (!_isInit) return;
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: true,
    );
  }

  /// Stops listening immediately.
  void stopListening() {
    _speech.stop();
  }

  /// speaks the provided text back to the user.
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  bool get isListening => _speech.isListening;
}
