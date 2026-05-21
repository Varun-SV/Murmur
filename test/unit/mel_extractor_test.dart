import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:murmur/core/audio/mel_extractor.dart';

void main() {
  group('MelExtractor', () {
    test('produces correct output shape for 1s of silence', () {
      final pcm = Float32List(16000); // 1s at 16 kHz, all zeros
      final (data, nMels, nFrames) = MelExtractor.computeForOnnx(pcm);

      expect(nMels, equals(80));
      // 1s: (16000 - 400) / 160 + 1 = 98 frames
      expect(nFrames, equals(98));
      expect(data.length, equals(nMels * nFrames));
    });

    test('output length matches nMels * nFrames', () {
      final pcm = Float32List(8000); // 0.5s
      final (data, nMels, nFrames) = MelExtractor.computeForOnnx(pcm);
      expect(data.length, equals(nMels * nFrames));
    });

    test('handles single-frame input (short clip)', () {
      final pcm = Float32List(400); // exactly one window
      final (data, nMels, nFrames) = MelExtractor.computeForOnnx(pcm);
      expect(nMels, equals(80));
      expect(nFrames, greaterThanOrEqualTo(1));
      expect(data.length, equals(nMels * nFrames));
    });

    test('silence produces uniform log-mel values near log(1e-10)', () {
      final pcm = Float32List(16000);
      final (data, _, _) = MelExtractor.computeForOnnx(pcm);
      // All values should be log(1e-10) ≈ -23.025 or close to it.
      for (final v in data) {
        expect(v, lessThanOrEqualTo(0.0));
        expect(v, greaterThanOrEqualTo(-30.0));
      }
    });

    test('sine wave produces non-trivial log-mel output', () {
      // 440 Hz sine at 16 kHz, 1s.
      final pcm = Float32List(16000);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = math.sin(2.0 * math.pi * 440.0 * i / 16000.0).toDouble();
      }
      final (data, nMels, nFrames) = MelExtractor.computeForOnnx(pcm);
      expect(data.length, equals(nMels * nFrames));

      // At least some bins should have energy well above the silence floor.
      final maxVal = data.reduce(math.max);
      expect(maxVal, greaterThan(-10.0));
    });

    test('compute() and computeForOnnx() produce identical data', () {
      final pcm = Float32List.fromList(
        List.generate(3200, (i) => (i % 100) / 100.0),
      );
      final direct = MelExtractor.compute(pcm);
      final (fromOnnx, _, _) = MelExtractor.computeForOnnx(pcm);
      expect(direct.length, equals(fromOnnx.length));
      for (var i = 0; i < direct.length; i++) {
        expect(direct[i], closeTo(fromOnnx[i], 1e-6));
      }
    });

    test('results are deterministic (called twice with same input)', () {
      final pcm = Float32List.fromList(
        List.generate(4800, (i) => math.sin(i * 0.1).toDouble()),
      );
      final a = MelExtractor.compute(pcm);
      final b = MelExtractor.compute(pcm);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], equals(b[i]));
      }
    });
  });
}
