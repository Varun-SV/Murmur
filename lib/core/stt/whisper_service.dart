import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/result.dart';
import 'package:murmur/core/stt/whisper_ffi.dart';

final _log = Logger('WhisperService');

// ── Value type returned by WhisperService.transcribe() ────────────────────────

class TranscriptResult {
  const TranscriptResult({
    required this.text,
    required this.language,
    required this.confidence,
  });

  final String text;
  final String language; // ISO 639-1
  final double confidence; // [0, 1]
}

// ── Isolate entry point (must be a top-level function) ───────────────────────

void _isolateEntry(Map<String, dynamic> args) {
  final modelPath = args['modelPath'] as String;
  final mainPort = args['mainPort'] as SendPort;

  // Load the native library and initialise the model inside the isolate.
  // WhisperFfi.instance throws ArgumentError if libwhisper.so is not present.
  Pointer<WhisperContext> ctxPtr;
  try {
    final ffi = WhisperFfi.instance;
    final modelPathPtr = modelPath.toNativeUtf8();
    try {
      ctxPtr = ffi.init(modelPathPtr);
    } finally {
      malloc.free(modelPathPtr);
    }
  } catch (e) {
    mainPort.send({'type': 'error', 'message': 'FFI load failed: $e'});
    return;
  }

  if (ctxPtr == nullptr) {
    mainPort.send({
      'type': 'error',
      'message':
          'whisper_bridge_init returned null — check model path and file integrity',
    });
    return;
  }

  // Signal successful initialisation and hand the caller our request port.
  final requestPort = ReceivePort();
  mainPort.send({'type': 'ready', 'port': requestPort.sendPort});

  requestPort.listen((dynamic message) {
    if (message == null) {
      // Shutdown sentinel.
      WhisperFfi.instance.free(ctxPtr);
      requestPort.close();
      return;
    }

    final req = message as Map<String, dynamic>;
    final pcmF32 = req['pcmData'] as Float32List;
    final replyPort = req['replyPort'] as SendPort;

    // Allocate output buffers.
    final outText = calloc<Utf8>(4096);
    final outLang = calloc<Utf8>(16);
    final outConf = calloc<Float>();
    Pointer<Float>? pcmPtr;

    try {
      // Copy Float32List into native heap.
      pcmPtr = calloc<Float>(pcmF32.length);
      pcmPtr.asTypedList(pcmF32.length).setAll(0, pcmF32);

      final rc = WhisperFfi.instance.transcribe(
        ctxPtr, pcmPtr, pcmF32.length, outText, outLang, outConf,
      );

      if (rc == 0) {
        replyPort.send({
          'type': 'ok',
          'text': outText.toDartString(),
          'lang': outLang.toDartString(),
          'conf': outConf.value,
        });
      } else {
        replyPort.send({'type': 'error', 'message': 'whisper_bridge_transcribe rc=$rc'});
      }
    } catch (e) {
      replyPort.send({'type': 'error', 'message': 'transcribe exception: $e'});
    } finally {
      calloc.free(outText);
      calloc.free(outLang);
      calloc.free(outConf);
      if (pcmPtr != null) calloc.free(pcmPtr);
    }
  });
}

// ── High-level service ────────────────────────────────────────────────────────

class WhisperService {
  bool _initialized = false;
  Isolate? _isolate;
  SendPort? _isolateSendPort;

  /// Spawn the Whisper isolate and load the model.
  ///
  /// Model loading can take 5–30 s depending on model size and device speed.
  /// Returns [Err] if the library is missing, the model path is wrong, or
  /// the isolate times out (60 s hard limit).
  Future<Result<void>> initialize(String modelPath) async {
    if (_initialized) return const Ok(null);

    final mainPort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(
        _isolateEntry,
        {'modelPath': modelPath, 'mainPort': mainPort.sendPort},
        errorsAreFatal: false,
      );
    } catch (e) {
      mainPort.close();
      return Err('Failed to spawn Whisper isolate: $e', cause: e as Object);
    }

    // Wait for 'ready' or 'error'.  Model loading on a slow device can take ~30s.
    final response = await mainPort.first.timeout(
      const Duration(seconds: 60),
      // mainPort.first auto-closes the port on receipt — explicit close in timeout only.
      onTimeout: () {
        mainPort.close();
        return null;
      },
    );

    if (response == null) {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      return const Err('Whisper isolate init timed out (60 s)');
    }

    final msg = response as Map<String, dynamic>;
    if (msg['type'] == 'error') {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      return Err('Whisper init failed: ${msg['message']}');
    }

    _isolateSendPort = msg['port'] as SendPort;
    _initialized = true;
    _log.info('WhisperService ready, model=$modelPath');
    return const Ok(null);
  }

  /// Transcribe [pcm] (int16 LE, 16 kHz, mono) in the long-lived isolate.
  ///
  /// Times out after 30 s to guard against isolate hangs.
  Future<Result<TranscriptResult>> transcribe(Int16List pcm) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    // Convert int16 → float32 on the caller isolate before crossing the boundary.
    // Crossing with Float32List copies ~1.9 MB for a 30-s buffer, which takes < 10 ms.
    final pcmF32 = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      pcmF32[i] = pcm[i] / 32768.0;
    }

    final replyPort = ReceivePort();

    _isolateSendPort!.send({
      'pcmData': pcmF32,
      'replyPort': replyPort.sendPort,
    });

    dynamic response;
    try {
      response = await replyPort.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          replyPort.close();
          return null;
        },
      );
    } catch (e) {
      replyPort.close();
      return Err('transcribe() exception: $e', cause: e as Object);
    }

    if (response == null) {
      return const Err('Transcription timed out (30 s)');
    }

    final msg = response as Map<String, dynamic>;
    if (msg['type'] == 'error') {
      return Err('Transcription failed: ${msg['message']}');
    }

    return Ok(TranscriptResult(
      text: (msg['text'] as String).trim(),
      language: msg['lang'] as String,
      confidence: (msg['conf'] as num).toDouble(),
    ));
  }

  /// Shut down the Whisper isolate and release the model from memory.
  Future<void> dispose() async {
    if (!_initialized) return;
    _log.info('Disposing WhisperService');
    _isolateSendPort?.send(null); // Shutdown sentinel
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _initialized = false;
  }
}
