import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/result.dart';

final _log = Logger('VadDetector');

class VadDetector {
  OrtSession? _session;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  static const _chunkSize = 512; // 32ms at 16kHz
  static const _sampleRate = 16000;

  Future<Result<void>> load(String modelPath) async {
    try {
      final sessionOptions = OrtSessionOptions();
      _session = await OrtSession.fromFile(modelPath, sessionOptions);
      _loaded = true;
      _log.info('VadDetector loaded from $modelPath');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('Failed to load VAD model', e, st);
      return Err('Failed to load VAD model: $e', cause: e as Object);
    }
  }

  /// Returns the maximum speech probability across all 512-sample chunks.
  /// Returns Ok(0.0) if the buffer is too short for even one chunk.
  Future<Result<double>> maxSpeechProbability(Float32List pcmF32) async {
    if (!_loaded || _session == null) {
      return const Err('VadDetector not loaded');
    }

    if (pcmF32.length < _chunkSize) {
      return const Ok(0.0);
    }

    double maxProb = 0.0;
    // LSTM state: [2, 1, 64] flattened
    var h = Float32List(2 * 1 * 64);
    var c = Float32List(2 * 1 * 64);
    final sr = Int64List.fromList([_sampleRate]);

    int offset = 0;
    while (offset + _chunkSize <= pcmF32.length) {
      final chunk = Float32List.sublistView(pcmF32, offset, offset + _chunkSize);

      final inputTensor = OrtValueTensor.createTensorWithDataList(chunk, [1, _chunkSize]);
      final hTensor = OrtValueTensor.createTensorWithDataList(h, [2, 1, 64]);
      final cTensor = OrtValueTensor.createTensorWithDataList(c, [2, 1, 64]);
      final srTensor = OrtValueTensor.createTensorWithDataList(sr, [1]);

      final inputs = <String, OrtValue>{
        'input': inputTensor,
        'h': hTensor,
        'c': cTensor,
        'sr': srTensor,
      };

      try {
        final outputs = await _session!.run(inputs);

        final outputVal = outputs['output'];
        if (outputVal != null) {
          final valueList = (outputVal as OrtValueTensor).value as List;
          final prob = (valueList[0] as List)[0];
          final probDouble = (prob as num).toDouble();
          if (probDouble > maxProb) maxProb = probDouble;
        }

        // Carry LSTM state forward
        final hnVal = outputs['hn'];
        final cnVal = outputs['cn'];
        if (hnVal != null) {
          h = _flattenToFloat32((hnVal as OrtValueTensor).value as List);
        }
        if (cnVal != null) {
          c = _flattenToFloat32((cnVal as OrtValueTensor).value as List);
        }

        for (final t in inputs.values) {
          t.release();
        }
      } catch (e, st) {
        _log.severe('VAD inference error at offset $offset', e, st);
        for (final t in inputs.values) {
          t.release();
        }
        return Err('VAD inference failed: $e', cause: e as Object);
      }

      offset += _chunkSize;
    }

    return Ok(maxProb);
  }

  Float32List _flattenToFloat32(List nested) {
    final result = <double>[];
    void flatten(dynamic v) {
      if (v is List) {
        for (final item in v) {
          flatten(item);
        }
      } else {
        result.add((v as num).toDouble());
      }
    }
    flatten(nested);
    return Float32List.fromList(result);
  }

  void dispose() {
    _session?.release();
    _session = null;
    _loaded = false;
  }
}
