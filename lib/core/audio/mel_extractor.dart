import 'dart:math' as math;
import 'dart:typed_data';

// Computes log-mel spectrograms compatible with standard speaker encoder models.
//
// Parameters match the SpeechBrain ECAPA-TDNN defaults:
//   sample_rate=16000, n_mels=80, win_length=25ms, hop_length=10ms,
//   f_min=80, f_max=7600, window=hann.
class MelExtractor {
  MelExtractor._();

  static const _sampleRate = 16000;
  static const _nMels = 80;
  static const _winSamples = 400; // 25ms
  static const _hopSamples = 160; // 10ms
  static const _fftSize = 512; // next power-of-2 >= 400
  static const _fMin = 80.0;
  static const _fMax = 7600.0;

  // Precomputed once per process.
  static List<Float32List>? _filterbank;
  static Float32List? _hann;

  // Returns log-mel spectrogram as Float32List of shape [nMels, nFrames]
  // stored row-major (mel bin varies fastest in stride, frames are columns).
  // The caller must reshape to [1, nMels, nFrames] for ONNX input.
  static Float32List compute(Float32List pcm) {
    _ensurePrecomputed();

    final hann = _hann!;
    final filterbank = _filterbank!;

    final nFrames =
        ((pcm.length - _winSamples) / _hopSamples).floor().clamp(1, 10000) + 1;

    // Allocate output: [nMels × nFrames]
    final out = Float32List(_nMels * nFrames);

    final frame = Float64List(_fftSize);
    final real = Float64List(_fftSize);
    final imag = Float64List(_fftSize);

    for (var t = 0; t < nFrames; t++) {
      final start = t * _hopSamples;

      // Fill frame with windowed PCM.
      for (var i = 0; i < _fftSize; i++) {
        final srcIdx = start + i;
        final sample = (srcIdx < pcm.length) ? pcm[srcIdx] : 0.0;
        frame[i] = sample * (i < _winSamples ? hann[i] : 0.0);
      }

      // In-place radix-2 FFT.
      _fft(frame, real, imag);

      // Power spectrum (one-sided, DC through Nyquist).
      final halfSize = _fftSize ~/ 2 + 1;
      final power = Float64List(halfSize);
      for (var i = 0; i < halfSize; i++) {
        power[i] = real[i] * real[i] + imag[i] * imag[i];
      }

      // Apply mel filterbank and log.
      for (var m = 0; m < _nMels; m++) {
        var energy = 0.0;
        final filter = filterbank[m];
        for (var i = 0; i < halfSize; i++) {
          energy += filter[i] * power[i];
        }
        // Stabilised log (matches librosa default floor 1e-10).
        out[m * nFrames + t] = math.log(math.max(energy, 1e-10)).toDouble();
      }
    }

    return out;
  }

  /// Convenience wrapper: returns [1, nMels, nFrames] for ONNX input.
  static (Float32List data, int nMels, int nFrames) computeForOnnx(Float32List pcm) {
    final nFrames =
        ((pcm.length - _winSamples) / _hopSamples).floor().clamp(1, 10000) + 1;
    final data = compute(pcm);
    return (data, _nMels, nFrames);
  }

  // ── Radix-2 Cooley-Tukey FFT (real input, bit-reversal permutation) ─────────

  static void _fft(Float64List signal, Float64List outReal, Float64List outImag) {
    final n = signal.length; // must be a power of 2

    // Bit-reversal permutation.
    for (var i = 0; i < n; i++) {
      outReal[i] = signal[_bitReverse(i, n)];
      outImag[i] = 0.0;
    }

    // Butterfly stages.
    var step = 2;
    while (step <= n) {
      final halfStep = step ~/ 2;
      final angle = -2.0 * math.pi / step;
      final wRe = math.cos(angle);
      final wIm = math.sin(angle);

      for (var k = 0; k < n; k += step) {
        var tRe = 1.0;
        var tIm = 0.0;
        for (var j = 0; j < halfStep; j++) {
          final uRe = outReal[k + j];
          final uIm = outImag[k + j];
          final vRe = outReal[k + j + halfStep] * tRe - outImag[k + j + halfStep] * tIm;
          final vIm = outReal[k + j + halfStep] * tIm + outImag[k + j + halfStep] * tRe;
          outReal[k + j] = uRe + vRe;
          outImag[k + j] = uIm + vIm;
          outReal[k + j + halfStep] = uRe - vRe;
          outImag[k + j + halfStep] = uIm - vIm;
          final nextTRe = tRe * wRe - tIm * wIm;
          tIm = tRe * wIm + tIm * wRe;
          tRe = nextTRe;
        }
      }
      step *= 2;
    }
  }

  static int _bitReverse(int x, int n) {
    final bits = (math.log(n) / math.log(2)).round();
    var reversed = 0;
    for (var i = 0; i < bits; i++) {
      reversed = (reversed << 1) | (x & 1);
      x >>= 1;
    }
    return reversed;
  }

  // ── Precomputed tables ───────────────────────────────────────────────────────

  static void _ensurePrecomputed() {
    if (_hann != null) return;
    _hann = _makeHann(_winSamples);
    _filterbank = _makeMelFilterbank();
  }

  static Float32List _makeHann(int n) {
    final w = Float32List(n);
    for (var i = 0; i < n; i++) {
      w[i] = (0.5 * (1.0 - math.cos(2.0 * math.pi * i / (n - 1)))).toDouble();
    }
    return w;
  }

  static List<Float32List> _makeMelFilterbank() {
    final halfSize = _fftSize ~/ 2 + 1;
    final melMin = _hzToMel(_fMin);
    final melMax = _hzToMel(_fMax);

    // _nMels + 2 evenly-spaced mel points (including endpoints).
    final melPoints = List<double>.generate(
      _nMels + 2,
      (i) => melMin + i * (melMax - melMin) / (_nMels + 1),
    );

    // Convert mel points to FFT bin indices.
    final binPoints = melPoints
        .map((m) => (_melToHz(m) / _sampleRate * _fftSize).round())
        .toList();

    final filters = List<Float32List>.generate(_nMels, (m) {
      final filter = Float32List(halfSize);
      final left = binPoints[m];
      final center = binPoints[m + 1];
      final right = binPoints[m + 2];

      for (var i = left; i <= center && i < halfSize; i++) {
        if (center > left) filter[i] = (i - left) / (center - left);
      }
      for (var i = center; i <= right && i < halfSize; i++) {
        if (right > center) filter[i] = (right - i) / (right - center);
      }
      return filter;
    });

    return filters;
  }

  static double _hzToMel(double hz) => 2595.0 * math.log(1.0 + hz / 700.0) / math.log(10.0);
  static double _melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);
}
