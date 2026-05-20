import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ── Opaque native type ──────────────────────────────────────────────────────

final class WhisperContext extends Opaque {}

// ── Native typedef pairs (C types on the left, Dart types on the right) ────

typedef _InitNative = Pointer<WhisperContext> Function(Pointer<Utf8> modelPath);
typedef _InitDart = Pointer<WhisperContext> Function(Pointer<Utf8> modelPath);

typedef _FreeNative = Void Function(Pointer<WhisperContext> ctx);
typedef _FreeDart = void Function(Pointer<WhisperContext> ctx);

typedef _TranscribeNative = Int32 Function(
  Pointer<WhisperContext> ctx,
  Pointer<Float> pcmF32,
  Int32 nSamples,
  Pointer<Utf8> outText,
  Pointer<Utf8> outLang,
  Pointer<Float> outConfidence,
);
typedef _TranscribeDart = int Function(
  Pointer<WhisperContext> ctx,
  Pointer<Float> pcmF32,
  int nSamples,
  Pointer<Utf8> outText,
  Pointer<Utf8> outLang,
  Pointer<Float> outConfidence,
);

// ── Public API ───────────────────────────────────────────────────────────────

/// Lazily-loaded Dart bindings for libwhisper.so.
///
/// These are hand-written to match whisper_bridge.h exactly.
/// Regenerate with ffigen if the C API changes:
///   dart run ffigen --config ffigen.yaml
///
/// Throws [ArgumentError] on platforms where libwhisper.so is unavailable.
/// [WhisperService.initialize] catches this and converts it to [Err].
class WhisperFfi {
  WhisperFfi._() {
    final lib = DynamicLibrary.open('libmurmur_bridge.so');
    init = lib.lookupFunction<_InitNative, _InitDart>('whisper_bridge_init');
    free = lib.lookupFunction<_FreeNative, _FreeDart>('whisper_bridge_free');
    transcribe =
        lib.lookupFunction<_TranscribeNative, _TranscribeDart>('whisper_bridge_transcribe');
  }

  static WhisperFfi? _instance;

  /// Returns the process-wide singleton. Throws if libwhisper.so cannot be loaded.
  static WhisperFfi get instance => _instance ??= WhisperFfi._();

  late final _InitDart init;
  late final _FreeDart free;
  late final _TranscribeDart transcribe;
}
