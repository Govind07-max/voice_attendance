import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

abstract class SpeechService {
  Future<bool> initialize();
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(String status)? onStatus,
    List<String> contextualPhrases,
  });
  Future<void> stopListening();
  bool get isListening;
  bool get isAvailable;
}

class FlutterSpeechService implements SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  /// The latest status listener. The plugin only accepts it at initialize
  /// time, so it is kept here and delegated to.
  Function(String status)? _statusListener;

  @override
  bool get isListening => _speech.isListening;

  @override
  bool get isAvailable => _isInitialized && _speech.isAvailable;

  /// Requests mic permission first (required on Android APK), then
  /// initializes the speech engine. Returns false when the user denies
  /// permission or no recognizer is available.
  @override
  Future<bool> initialize() async {
    if (_isInitialized && _speech.isAvailable) return true;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted && !status.isLimited) {
        debugPrint('[SPEECH] Mic permission denied: $status');
        return false;
      }

      _isInitialized = await _speech.initialize(
        onError: (error) => debugPrint('[SPEECH] error: ${error.errorMsg}'),
        onStatus: (status) {
          debugPrint('[SPEECH] status: $status');
          _statusListener?.call(status);
        },
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('[SPEECH] init exception: $e');
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(String status)? onStatus,
    List<String> contextualPhrases = const [],
  }) async {
    _statusListener = onStatus;

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          onResult(result.recognizedWords, result.finalResult);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        // A pause of 4 s ends one instruction ("name present") and starts the
        // next one.
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        localeId: 'en_IN',
        // Dictation keeps the microphone open so the teacher can call out
        // one student after another without re-tapping.
        listenMode: stt.ListenMode.dictation,
        // Telling the recogniser the student names makes it far more
        // accurate for Indian names.
        contextualPhrases: contextualPhrases.isEmpty
            ? null
            : contextualPhrases.take(60).toList(),
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}
