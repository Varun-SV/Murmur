import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:murmur/core/stt/speaker_registry.dart';

Float32List _unit(List<double> v) {
  var norm = 0.0;
  for (final x in v) norm += x * x;
  norm = math.sqrt(norm);
  return Float32List.fromList(v.map((x) => x / norm).toList());
}

Float32List _zeros(int n) => Float32List(n);

void main() {
  group('SpeakerRegistry', () {
    late SpeakerRegistry registry;

    setUp(() => registry = SpeakerRegistry());

    test('first embedding creates a new speaker', () {
      final emb = _unit([1.0, 0.0, 0.0]);
      final (id, isNew) = registry.identify(emb);
      expect(id, equals('spk_1'));
      expect(isNew, isTrue);
      expect(registry.speakers.length, equals(1));
    });

    test('identical embedding matches existing speaker', () {
      final emb = _unit([1.0, 0.0, 0.0]);
      registry.identify(emb);
      final (id, isNew) = registry.identify(emb);
      expect(id, equals('spk_1'));
      expect(isNew, isFalse);
      expect(registry.speakers.length, equals(1));
    });

    test('orthogonal embedding creates a second speaker', () {
      registry.identify(_unit([1.0, 0.0, 0.0]));
      final (id, isNew) = registry.identify(_unit([0.0, 1.0, 0.0]));
      expect(id, equals('spk_2'));
      expect(isNew, isTrue);
      expect(registry.speakers.length, equals(2));
    });

    test('near-identical embedding (high cosine sim) matches same speaker', () {
      // Slightly perturbed unit vector — cosine sim > 0.75.
      registry.identify(_unit([1.0, 0.0, 0.0]));
      final (id, isNew) = registry.identify(_unit([0.99, 0.14, 0.0]));
      expect(isNew, isFalse);
      expect(id, equals('spk_1'));
    });

    test('clear() removes all speakers', () {
      registry.identify(_unit([1.0, 0.0, 0.0]));
      registry.identify(_unit([0.0, 1.0, 0.0]));
      registry.clear();
      expect(registry.speakers, isEmpty);

      // Next identification should create spk_1 again.
      final (id, isNew) = registry.identify(_unit([1.0, 0.0, 0.0]));
      expect(id, equals('spk_1'));
      expect(isNew, isTrue);
    });

    test('speaker() returns correct Speaker for known id', () {
      final emb = _unit([1.0, 0.0, 0.0]);
      final (id, _) = registry.identify(emb);
      final speaker = registry.speaker(id);
      expect(speaker, isNotNull);
      expect(speaker!.id, equals(id));
      expect(speaker.label, equals('Speaker 1'));
    });

    test('speaker() returns null for unknown id', () {
      expect(registry.speaker('spk_99'), isNull);
    });

    test('multiple calls refine centroid without creating new speakers', () {
      // Register spk_1 with a base vector.
      registry.identify(_unit([1.0, 0.1, 0.0]));
      // Subsequent similar embeddings should match spk_1 and refine centroid.
      for (var i = 0; i < 5; i++) {
        final (id, isNew) = registry.identify(_unit([1.0, 0.1 + i * 0.01, 0.0]));
        expect(id, equals('spk_1'));
        expect(isNew, isFalse);
      }
      expect(registry.speakers.length, equals(1));
    });

    test('zero-length embedding does not crash', () {
      final emb = _zeros(192);
      expect(() => registry.identify(emb), returnsNormally);
    });
  });
}
