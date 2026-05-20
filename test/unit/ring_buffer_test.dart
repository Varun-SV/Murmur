import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:murmur/core/audio/ring_buffer.dart';

void main() {
  group('RingBuffer', () {
    Int16List _int16(List<int> samples) => Int16List.fromList(samples);

    Uint8List _bytes(List<int> samples) {
      final buf = Int16List.fromList(samples);
      return Uint8List.view(buf.buffer);
    }

    test('write then flush returns same samples', () {
      final rb = RingBuffer(capacitySamples: 100);
      rb.write(_bytes([1, 2, 3, 4, 5]));
      final out = rb.flush();
      expect(out, equals(_int16([1, 2, 3, 4, 5])));
    });

    test('flush resets state — second flush returns empty', () {
      final rb = RingBuffer(capacitySamples: 100);
      rb.write(_bytes([10, 20]));
      rb.flush();
      expect(rb.flush().isEmpty, isTrue);
      expect(rb.isEmpty, isTrue);
    });

    test('multiple writes are concatenated in order', () {
      final rb = RingBuffer(capacitySamples: 100);
      rb.write(_bytes([1, 2, 3]));
      rb.write(_bytes([4, 5, 6]));
      expect(rb.flush(), equals(_int16([1, 2, 3, 4, 5, 6])));
    });

    test('wrap-around preserves chronological order', () {
      // Capacity 8, write 6 samples, then write 4 more (crosses end of buffer).
      final rb = RingBuffer(capacitySamples: 8);
      rb.write(_bytes([1, 2, 3, 4, 5, 6])); // fills 6/8 slots
      rb.write(_bytes([7, 8, 9, 10])); // 2 fit at end, 2 wrap to start
      // Buffer is full (8 samples). Oldest 2 (1, 2) are overwritten.
      final out = rb.flush();
      expect(out.length, 8);
      expect(out, equals(_int16([3, 4, 5, 6, 7, 8, 9, 10])));
    });

    test('overflow: writing more than capacity discards oldest samples', () {
      final rb = RingBuffer(capacitySamples: 5);
      rb.write(_bytes([1, 2, 3, 4, 5, 6, 7])); // 7 > 5, oldest 2 discarded
      final out = rb.flush();
      expect(out.length, 5);
      expect(out, equals(_int16([3, 4, 5, 6, 7])));
    });

    test('odd byte count is rejected gracefully — buffer stays empty', () {
      final rb = RingBuffer(capacitySamples: 10);
      // Build a 3-byte slice (odd).
      final oddBytes = Uint8List.fromList([0x01, 0x00, 0x02]);
      rb.write(oddBytes); // should log warning and do nothing
      expect(rb.isEmpty, isTrue);
    });

    test('flush on empty buffer returns empty Int16List', () {
      final rb = RingBuffer(capacitySamples: 10);
      final out = rb.flush();
      expect(out.isEmpty, isTrue);
    });

    test('count tracks how many samples are held', () {
      final rb = RingBuffer(capacitySamples: 10);
      expect(rb.count, 0);
      rb.write(_bytes([1, 2, 3]));
      expect(rb.count, 3);
      rb.flush();
      expect(rb.count, 0);
    });
  });
}
