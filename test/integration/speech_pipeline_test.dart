import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/services/speech_service.dart';

const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

/// Verifies the microphone pipeline: permission request -> engine init ->
/// platform recognition callback -> onResult with the spoken text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'checkPermissionStatus') return 1; // granted
      // {permissionValue: status}
      if (call.method == 'requestPermissions') {
        final perms = (call.arguments as List).cast<int>();
        return {for (final p in perms) p: 1};
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, (call) async {
      switch (call.method) {
        case 'has_permission':
          return true;
        case 'initialize':
          return true;
        case 'listen':
          return true;
        case 'stop':
        case 'cancel':
          return null;
        case 'locales':
          return <dynamic>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, null);
  });

  test('the speech service returns the recognised words to onResult', () async {
    final service = FlutterSpeechService();

    final initialised = await service.initialize();
    expect(initialised, isTrue, reason: 'engine + mic permission must be OK');

    String? heard;
    bool? wasFinal;
    await service.startListening(onResult: (text, isFinal) {
      heard = text;
      wasFinal = isFinal;
    });

    // The platform pushes the recognition result back over the channel.
    final payload = jsonEncode({
      'alternates': [
        {
          'recognizedWords': 'Vedant Joshi',
          'confidence': 0.92,
          'recognizedPhrases': null,
        }
      ],
      'finalResult': true,
      'resultType': 2,
    });

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      speechChannel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('textRecognition', payload)),
      (_) {},
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(heard, 'Vedant Joshi');
    expect(wasFinal, isTrue, reason: 'a complete phrase must be final');
  });

  test('a denied microphone permission is reported as unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'checkPermissionStatus') return 0; // denied
      if (call.method == 'requestPermissions') {
        final perms = (call.arguments as List).cast<int>();
        return {for (final p in perms) p: 0};
      }
      return null;
    });

    final service = FlutterSpeechService();
    final initialised = await service.initialize();
    expect(initialised, isFalse,
        reason: 'a denied mic must not start listening');
  });
}
