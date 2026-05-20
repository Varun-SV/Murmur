import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:murmur/core/result.dart';
import 'package:murmur/core/stt/whisper_service.dart';
import 'package:murmur/core/stt/whisper_service.dart';

void main() {
  group('WhisperService', () {
    test('initialize returns Err when libwhisper.so is unavailable', () async {
      // On a test host (non-Android), DynamicLibrary.open('libwhisper.so')
      // throws ArgumentError inside the isolate, which the service converts to Err.
      final svc = WhisperService();
      final result = await svc.initialize('/nonexistent/model.bin');
      expect(result, isA<Err<void>>());
      final err = result as Err<void>;
      expect(err.message, isNotEmpty);
    });

    test('transcribe before initialize returns Err', () async {
      final svc = WhisperService();
      final result = await svc.transcribe(Int16List(100));
      expect(result, isA<Err<TranscriptResult>>());
    });

    test('dispose on uninitialized service completes without error', () async {
      final svc = WhisperService();
      await expectLater(svc.dispose(), completes);
    });
  });
}
