import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/audio/mel_extractor.dart';
import 'package:murmur/core/result.dart';

final _log = Logger('SpeakerEncoder');

// Expected ECAPA-TDNN ONNX model contract (SpeechBrain INT8 export):
//   input  "input"  shape [1, 80, T]   float32   log-mel spectrogram
//   output "output" shape [1, 192]     float32   L2-normalised d-vector
//
// Obtain a compatible model with:
//   pip install speechbrain onnx
//   python3 -c "
//     from speechbrain.pretrained import EncoderClassifier
//     m = EncoderClassifier.from_hparams('speechbrain/spkrec-ecapa-voxceleb')
//     m.export('ecapa_tdnn', format='onnx')
//   "
// Then INT8-quantize with onnxruntime.quantization.
class SpeakerEncoder {
  OrtSession? _session;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<Result<void>> load(String modelPath) async {
    try {
      final opts = OrtSessionOptions();
      _session = await OrtSession.fromFile(modelPath, opts);
      _loaded = true;
      _log.info('SpeakerEncoder loaded from $modelPath');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('Failed to load speaker encoder', e, st);
      return Err('Failed to load speaker encoder: $e', cause: e as Object);
    }
  }

  /// Returns an L2-normalised 192-dim speaker embedding, or null if not loaded.
  Future<Result<Float32List>> embed(Float32List pcmF32) async {
    if (!_loaded || _session == null) {
      return const Err('SpeakerEncoder not loaded');
    }

    try {
      final (melData, nMels, nFrames) = MelExtractor.computeForOnnx(pcmF32);

      // ONNX expects [1, nMels, nFrames].
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        melData,
        [1, nMels, nFrames],
      );

      final inputs = <String, OrtValue>{'input': inputTensor};
      final outputs = await _session!.run(inputs);

      inputTensor.release();

      final outputVal = outputs['output'] as OrtValueTensor?;
      if (outputVal == null) {
        return const Err('Speaker encoder produced no output');
      }

      final rawList = outputVal.value as List;
      final flat = _flattenToFloat32(rawList);
      return Ok(_l2Normalize(flat));
    } catch (e, st) {
      _log.severe('Speaker encoder inference failed', e, st);
      return Err('Speaker encoder inference failed: $e', cause: e as Object);
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    _loaded = false;
  }

  static Float32List _flattenToFloat32(List nested) {
    final result = <double>[];
    void flatten(dynamic v) {
      if (v is List) {
        for (final item in v) flatten(item);
      } else {
        result.add((v as num).toDouble());
      }
    }
    flatten(nested);
    return Float32List.fromList(result);
  }

  static Float32List _l2Normalize(Float32List v) {
    var norm = 0.0;
    for (final x in v) norm += x * x;
    norm = norm > 0 ? norm : 1.0;
    final scale = 1.0 / (norm < 1e-10 ? 1.0 : norm);
    final out = Float32List(v.length);
    for (var i = 0; i < v.length; i++) out[i] = v[i] * scale;
    return out;
  }
}
