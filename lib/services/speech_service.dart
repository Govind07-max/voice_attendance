import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

abstract class SpeechService {
  Future<bool> initialize();
  Future<void> startListening({required Function(String text) onResult});
  Future<void> stopListening();
  bool get isListening;
  bool get isAvailable;
}

class FlutterSpeechService implements SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  @override
  bool get isListening => _speech.isListening;

  @override
  bool get isAvailable => _isInitialized && _speech.isAvailable;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => print('SpeechToText error: $error'),
        onStatus: (status) => print('SpeechToText status: $status'),
      );
      return _isInitialized;
    } catch (e) {
      print('SpeechToText initialization failed: $e');
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<void> startListening({required Function(String text) onResult}) async {
    if (!_isInitialized) {
      bool initialized = await initialize();
      if (!initialized) return;
    }

    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: 'en_IN', // Default English (India) speech locale suitable for Indian student names
    );
  }

  @override
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}
