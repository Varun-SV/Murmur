import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger('RingBuffer');

/// In-RAM circular buffer for 16-bit PCM samples.
///
/// No I/O of any kind — the buffer lives entirely in RAM.
/// Default capacity: 30 s × 16 000 samples/s = 480 000 samples (~960 KB).
class RingBuffer {
  RingBuffer({int capacitySamples = 480000})
      : _buffer = Int16List(capacitySamples),
        _capacity = capacitySamples;

  final Int16List _buffer;
  final int _capacity;
  int _writeHead = 0; // Next write position (mod _capacity)
  int _count = 0; // Samples currently held (≤ _capacity)

  bool get isEmpty => _count == 0;
  int get count => _count;

  /// Write raw PCM bytes (int16 LE) into the ring buffer.
  ///
  /// Overwrites the oldest samples when the buffer is full.
  /// Silently drops the write if [pcmBytes] has an odd byte count.
  void write(Uint8List pcmBytes) {
    if (pcmBytes.lengthInBytes.isOdd) {
      _log.warning(
          'write() received odd byte count (${pcmBytes.lengthInBytes}) — dropping');
      return;
    }

    final samples = Int16List.view(
      pcmBytes.buffer,
      pcmBytes.offsetInBytes,
      pcmBytes.lengthInBytes ~/ 2,
    );

    final n = samples.length;
    if (n == 0) return;

    // Two-segment block copy to handle wrap-around efficiently.
    final roomToEnd = _capacity - _writeHead;
    if (n <= roomToEnd) {
      _buffer.setRange(_writeHead, _writeHead + n, samples);
    } else {
      _buffer.setRange(_writeHead, _capacity, samples, 0);
      _buffer.setRange(0, n - roomToEnd, samples, roomToEnd);
    }

    _writeHead = (_writeHead + n) % _capacity;
    _count = (_count + n).clamp(0, _capacity);
  }

  /// Return all buffered samples in chronological order and reset the buffer.
  ///
  /// Returns an empty [Int16List] if the buffer is empty.
  Int16List flush() {
    if (_count == 0) return Int16List(0);

    final out = Int16List(_count);
    final readHead = (_writeHead - _count + _capacity) % _capacity;
    final roomToEnd = _capacity - readHead;

    if (_count <= roomToEnd) {
      out.setRange(0, _count, _buffer, readHead);
    } else {
      out.setRange(0, roomToEnd, _buffer, readHead);
      out.setRange(roomToEnd, _count, _buffer, 0);
    }

    _writeHead = 0;
    _count = 0;
    return out;
  }
}
