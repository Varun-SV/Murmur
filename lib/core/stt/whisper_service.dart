import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/audio/vad_detector.dart';
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

// ── Isolate helpers ───────────────────────────────────────────────────────────

Future<void> _handleVadInit(
    Map<String, dynamic> req, VadDetector vadDetector) async {
  final vadModelPath = req['modelPath'] as String;
  final replyPort = req['replyPort'] as SendPort;
  final result = await vadDetector.load(vadModelPath);
  switch (result) {
    case Ok():
      replyPort.send({'type': 'ok'});
    case Err(:final message):
      replyPort.send({'type': 'error', 'message': message});
  }
}

Future<void> _handleDetectAndTranscribe(
  Map<String, dynamic> req,
  Pointer<WhisperContext> ctxPtr,
  VadDetector vadDetector,
) async {
  final pcmF32 = req['pcmData'] as Float32List;
  final vadThreshold = (req['vadThreshold'] as num?)?.toDouble() ?? 0.5;
  final replyPort = req['replyPort'] as SendPort;

  if (vadThreshold > 0.0 && vadDetector.isLoaded) {
    final vadResult = await vadDetector.maxSpeechProbability(pcmF32);
    switch (vadResult) {
      case Ok(:final value):
        if (value < vadThreshold) {
          replyPort.send({'type': 'silent', 'maxProb': value});
          return;
        }
      case Err(:final message):
        _log.warning('VAD failed, proceeding without gate: $message');
    }
  }

  _handleTranscribePcm(pcmF32, ctxPtr, replyPort);
}

void _handleTranscribePcm(
  Float32List pcmF32,
  Pointer<WhisperContext> ctxPtr,
  SendPort replyPort,
) {
  final outText = calloc<Utf8>(4096);
  final outLang = calloc<Utf8>(16);
  final outConf = calloc<Float>();
  Pointer<Float>? pcmPtr;

  try {
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
}

// ── Isolate entry point (must be a top-level function) ───────────────────────

void _isolateEntry(Map<String, dynamic> args) {
  final modelPath = args['modelPath'] as String;
  final mainPort = args['mainPort'] as SendPort;
  final rootToken = args['rootIsolateToken'] as RootIsolateToken?;

  // Required so Flutter plugins (flutter_onnxruntime) work in this isolate.
  if (rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  }

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
      'message': 'whisper_bridge_init returned null — check model path and file integrity',
    });
    return;
  }

  final requestPort = ReceivePort();
  mainPort.send({'type': 'ready', 'port': requestPort.sendPort});

  final vadDetector = VadDetector();

  requestPort.listen((dynamic message) async {
    if (message == null) {
      WhisperFfi.instance.free(ctxPtr);
      vadDetector.dispose();
      requestPort.close();
      return;
    }

    final req = message as Map<String, dynamic>;
    final type = req['type'] as String? ?? 'transcribe';

    switch (type) {
      case 'init_vad':
        await _handleVadInit(req, vadDetector);
      case 'detect_and_transcribe':
        await _handleDetectAndTranscribe(req, ctxPtr, vadDetector);
      case 'transcribe':
        final pcmF32 = req['pcmData'] as Float32List;
        final replyPort = req['replyPort'] as SendPort;
        _handleTranscribePcm(pcmF32, ctxPtr, replyPort);
    }
  });
}

// ── High-level service ────────────────────────────────────────────────────────

class WhisperService {
  bool _initialized = false;
  Isolate? _isolate;
  SendPort? _isolateSendPort;

  Future<Result<void>> initialize(String modelPath) async {
    if (_initialized) return const Ok(null);

    final mainPort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(
        _isolateEntry,
        {
          'modelPath': modelPath,
          'mainPort': mainPort.sendPort,
          'rootIsolateToken': RootIsolateToken.instance,
        },
        errorsAreFatal: false,
      );
    } catch (e) {
      mainPort.close();
      return Err('Failed to spawn Whisper isolate: $e', cause: e as Object);
    }

    final response = await mainPort.first.timeout(
      const Duration(seconds: 60),
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

  /// Initialise the VAD detector inside the Whisper isolate.
  Future<Result<void>> initVad(String vadModelPath) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    final replyPort = ReceivePort();
    _isolateSendPort!.send({
      'type': 'init_vad',
      'modelPath': vadModelPath,
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
      return Err('initVad() exception: $e', cause: e as Object);
    }

    if (response == null) return const Err('VAD init timed out');

    final msg = response as Map<String, dynamic>;
    if (msg['type'] == 'error') return Err('VAD init failed: ${msg['message']}');

    _log.info('VAD detector ready, model=$vadModelPath');
    return const Ok(null);
  }

  /// Run VAD then (if speech detected) Whisper transcription.
  ///
  /// Returns [Ok(null)] for silent segments, [Ok(TranscriptResult)] for speech.
  /// Set [vadThreshold] to 0.0 to skip VAD and always transcribe.
  Future<Result<TranscriptResult?>> detectAndTranscribe(
    Int16List pcm, {
    double vadThreshold = 0.5,
  }) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    final pcmF32 = _toFloat32(pcm);
    final replyPort = ReceivePort();

    _isolateSendPort!.send({
      'type': 'detect_and_transcribe',
      'pcmData': pcmF32,
      'vadThreshold': vadThreshold,
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
      return Err('detectAndTranscribe() exception: $e', cause: e as Object);
    }

    if (response == null) return const Err('detectAndTranscribe timed out (30 s)');

    final msg = response as Map<String, dynamic>;
    switch (msg['type'] as String) {
      case 'silent':
        return const Ok(null);
      case 'error':
        return Err('detectAndTranscribe failed: ${msg['message']}');
      default:
        return Ok(TranscriptResult(
          text: (msg['text'] as String).trim(),
          language: msg['lang'] as String,
          confidence: (msg['conf'] as num).toDouble(),
        ));
    }
  }

  /// Transcribe without VAD gating (Phase 1 compatibility).
  Future<Result<TranscriptResult>> transcribe(Int16List pcm) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    final pcmF32 = _toFloat32(pcm);
    final replyPort = ReceivePort();

    _isolateSendPort!.send({
      'type': 'transcribe',
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

    if (response == null) return const Err('Transcription timed out (30 s)');

    final msg = response as Map<String, dynamic>;
    if (msg['type'] == 'error') return Err('Transcription failed: ${msg['message']}');

    return Ok(TranscriptResult(
      text: (msg['text'] as String).trim(),
      language: msg['lang'] as String,
      confidence: (msg['conf'] as num).toDouble(),
    ));
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _log.info('Disposing WhisperService');
    _isolateSendPort?.send(null);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _initialized = false;
  }

  static Float32List _toFloat32(Int16List pcm) {
    final f = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      f[i] = pcm[i] / 32768.0;
    }
    return f;
  }
}
