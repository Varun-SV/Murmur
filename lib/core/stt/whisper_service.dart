import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/audio/vad_detector.dart';
import 'package:murmur/core/result.dart';
import 'package:murmur/core/stt/speaker_encoder.dart';
import 'package:murmur/core/stt/whisper_ffi.dart';

final _log = Logger('WhisperService');

// ── Value type returned by WhisperService.transcribe() ────────────────────────

class TranscriptResult {
  const TranscriptResult({
    required this.text,
    required this.language,
    required this.confidence,
    this.speakerEmbedding,
  });

  final String text;
  final String language; // ISO 639-1
  final double confidence; // [0, 1]
  final Float32List? speakerEmbedding; // L2-normalised 192-dim, null if encoder not loaded
}

// ── Internal queue type ────────────────────────────────────────────────────────

class _TranscribeRequest {
  _TranscribeRequest({
    required this.type,
    required this.payload,
    required this.completer,
  });

  final String type; // 'transcribe' | 'detect_and_transcribe'
  final Map<String, dynamic> payload;
  final Completer<Result<dynamic>> completer;
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

Future<void> _handleSpeakerEncoderInit(
    Map<String, dynamic> req, SpeakerEncoder speakerEncoder) async {
  final modelPath = req['modelPath'] as String;
  final replyPort = req['replyPort'] as SendPort;
  final result = await speakerEncoder.load(modelPath);
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
  SpeakerEncoder speakerEncoder,
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

  await _handleTranscribePcm(pcmF32, ctxPtr, replyPort, speakerEncoder);
}

Future<void> _handleTranscribePcm(
  Float32List pcmF32,
  Pointer<WhisperContext> ctxPtr,
  SendPort replyPort,
  SpeakerEncoder speakerEncoder,
) async {
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
      // Run speaker encoder on the same PCM if loaded.
      Float32List? embedding;
      if (speakerEncoder.isLoaded) {
        final embResult = await speakerEncoder.embed(pcmF32);
        switch (embResult) {
          case Ok(:final value):
            embedding = value;
          case Err(:final message):
            _log.warning('Speaker encoder failed: $message');
        }
      }

      replyPort.send({
        'type': 'ok',
        'text': outText.toDartString(),
        'lang': outLang.toDartString(),
        'conf': outConf.value,
        'embedding': embedding, // Float32List? — null if encoder not loaded
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
  final speakerEncoder = SpeakerEncoder();

  requestPort.listen((dynamic message) async {
    if (message == null) {
      WhisperFfi.instance.free(ctxPtr);
      vadDetector.dispose();
      speakerEncoder.dispose();
      requestPort.close();
      return;
    }

    final req = message as Map<String, dynamic>;
    final type = req['type'] as String? ?? 'transcribe';

    switch (type) {
      case 'ping':
        // Heartbeat — reply immediately so the host knows the isolate is alive.
        final replyPort = req['replyPort'] as SendPort;
        replyPort.send({'type': 'pong'});
      case 'init_vad':
        await _handleVadInit(req, vadDetector);
      case 'init_speaker_encoder':
        await _handleSpeakerEncoderInit(req, speakerEncoder);
      case 'detect_and_transcribe':
        await _handleDetectAndTranscribe(req, ctxPtr, vadDetector, speakerEncoder);
      case 'transcribe':
        final pcmF32 = req['pcmData'] as Float32List;
        final replyPort = req['replyPort'] as SendPort;
        await _handleTranscribePcm(pcmF32, ctxPtr, replyPort, speakerEncoder);
    }
  });
}

// ── High-level service ────────────────────────────────────────────────────────

class WhisperService {
  bool _initialized = false;
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  String? _modelPath;

  // Heartbeat / watchdog state.
  Timer? _heartbeatTimer;
  bool _pongReceived = true; // true until first ping is sent
  ReceivePort? _pongPort;

  // Error port for uncaught isolate errors.
  ReceivePort? _errorPort;

  // In-flight transcription tracking.
  bool _inFlight = false;

  // Backpressure queue — capped at 2; oldest is dropped when full.
  static const _maxQueueDepth = 2;
  final Queue<_TranscribeRequest> _queue = Queue();

  // ── Spawn helper ─────────────────────────────────────────────────────────────

  /// Spawns (or respawns) the Whisper isolate using [modelPath].
  /// Wires up the ready handshake, error port, pong port, and heartbeat timer.
  /// Returns [Ok] when the isolate signals 'ready', [Err] on failure.
  Future<Result<void>> _spawnIsolate(String modelPath) async {
    // Tear down anything from a prior spawn.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongPort?.close();
    _pongPort = null;
    _errorPort?.close();
    _errorPort = null;

    final mainPort = ReceivePort();

    // Error port: receives [error, stackTrace] pairs for uncaught isolate errors.
    _errorPort = ReceivePort();
    _errorPort!.listen((dynamic errPair) {
      if (errPair is List && errPair.length >= 2) {
        _log.severe(
          'Uncaught error in Whisper isolate: ${errPair[0]}',
          errPair[0],
          StackTrace.fromString(errPair[1].toString()),
        );
      } else {
        _log.severe('Uncaught error in Whisper isolate: $errPair');
      }
      // Trigger respawn after an uncaught isolate error.
      _respawn();
    });

    try {
      _isolate = await Isolate.spawn(
        _isolateEntry,
        {
          'modelPath': modelPath,
          'mainPort': mainPort.sendPort,
          'rootIsolateToken': RootIsolateToken.instance,
        },
        errorsAreFatal: false,
        onError: _errorPort!.sendPort,
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
    _modelPath = modelPath;
    _pongReceived = true;

    _startHeartbeat();

    _log.info('WhisperService isolate ready, model=$modelPath');
    return const Ok(null);
  }

  // ── Heartbeat ─────────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _pongPort?.close();
    _pongPort = ReceivePort();

    _pongPort!.listen((dynamic msg) {
      if (msg is Map && msg['type'] == 'pong') {
        _pongReceived = true;
      }
    });

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_pongReceived) {
        _log.severe('Whisper isolate watchdog: pong not received — respawning');
        _respawn();
        return;
      }
      _pongReceived = false; // arm the watchdog for this cycle
      _isolateSendPort?.send({
        'type': 'ping',
        'replyPort': _pongPort!.sendPort,
      });
    });
  }

  // ── Respawn ───────────────────────────────────────────────────────────────────

  /// Kills the current isolate and spawns a fresh one with the same model path.
  void _respawn() {
    final path = _modelPath;
    if (path == null) return;

    _log.warning('Respawning Whisper isolate (model=$path)');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongPort?.close();
    _pongPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;

    _spawnIsolate(path).then((result) {
      switch (result) {
        case Ok():
          _log.info('Whisper isolate respawned successfully');
          _drainQueue();
        case Err(:final message):
          _log.severe('Whisper isolate respawn failed: $message');
      }
    });
  }

  // ── Public API ────────────────────────────────────────────────────────────────

  Future<Result<void>> initialize(String modelPath) async {
    if (_initialized) return const Ok(null);

    final result = await _spawnIsolate(modelPath);
    if (result is Err) return result;

    _initialized = true;
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

  /// Initialise the ECAPA-TDNN speaker encoder inside the Whisper isolate.
  Future<Result<void>> initSpeakerEncoder(String modelPath) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    final replyPort = ReceivePort();
    _isolateSendPort!.send({
      'type': 'init_speaker_encoder',
      'modelPath': modelPath,
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
      return Err('initSpeakerEncoder() exception: $e', cause: e as Object);
    }

    if (response == null) return const Err('Speaker encoder init timed out');

    final msg = response as Map<String, dynamic>;
    if (msg['type'] == 'error') {
      return Err('Speaker encoder init failed: ${msg['message']}');
    }

    _log.info('Speaker encoder ready, model=$modelPath');
    return const Ok(null);
  }

  /// Run VAD then (if speech detected) Whisper + speaker encoding.
  ///
  /// Returns [Ok(null)] for silent segments.
  /// Returns [Ok(TranscriptResult)] for speech; [speakerEmbedding] is non-null
  /// only when the speaker encoder was previously initialised.
  /// Set [vadThreshold] to 0.0 to skip VAD and always transcribe.
  Future<Result<TranscriptResult?>> detectAndTranscribe(
    Int16List pcm, {
    double vadThreshold = 0.5,
  }) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    // Guard: RootIsolateToken must be available before sending to isolate.
    if (ServicesBinding.rootIsolateToken == null) {
      return const Err('No root isolate token');
    }

    final pcmF32 = _toFloat32(pcm);
    final completer = Completer<Result<dynamic>>();
    final request = _TranscribeRequest(
      type: 'detect_and_transcribe',
      payload: {
        'type': 'detect_and_transcribe',
        'pcmData': pcmF32,
        'vadThreshold': vadThreshold,
      },
      completer: completer,
    );

    _enqueue(request);

    final raw = await completer.future;
    if (raw is Err) return Err((raw as Err).message);
    final msg = (raw as Ok).value as Map<String, dynamic>;
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
          speakerEmbedding: msg['embedding'] as Float32List?,
        ));
    }
  }

  /// Transcribe without VAD gating (Phase 1 compatibility).
  Future<Result<TranscriptResult>> transcribe(Int16List pcm) async {
    if (!_initialized || _isolateSendPort == null) {
      return const Err('WhisperService not initialized');
    }

    // Guard: RootIsolateToken must be available before sending to isolate.
    if (ServicesBinding.rootIsolateToken == null) {
      return const Err('No root isolate token');
    }

    final pcmF32 = _toFloat32(pcm);
    final completer = Completer<Result<dynamic>>();
    final request = _TranscribeRequest(
      type: 'transcribe',
      payload: {
        'type': 'transcribe',
        'pcmData': pcmF32,
      },
      completer: completer,
    );

    _enqueue(request);

    final raw = await completer.future;
    if (raw is Err) return Err((raw as Err).message);
    final msg = (raw as Ok).value as Map<String, dynamic>;
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongPort?.close();
    _pongPort = null;
    _errorPort?.close();
    _errorPort = null;
    _isolateSendPort?.send(null);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _initialized = false;
    _modelPath = null;
    // Drain any queued requests with an error.
    for (final req in _queue) {
      req.completer.complete(const Err('WhisperService disposed'));
    }
    _queue.clear();
  }

  // ── Queue management ──────────────────────────────────────────────────────────

  void _enqueue(_TranscribeRequest request) {
    if (_inFlight) {
      // Cap at _maxQueueDepth — drop the oldest if full.
      while (_queue.length >= _maxQueueDepth) {
        final dropped = _queue.removeFirst();
        _log.warning('Transcription queue full — dropping oldest request');
        dropped.completer.complete(const Err('Dropped: transcription queue full'));
      }
      _queue.addLast(request);
    } else {
      _dispatch(request);
    }
  }

  void _drainQueue() {
    if (_inFlight || _queue.isEmpty) return;
    final next = _queue.removeFirst();
    _dispatch(next);
  }

  void _dispatch(_TranscribeRequest request) {
    if (_isolateSendPort == null) {
      request.completer.complete(const Err('Whisper isolate not available'));
      return;
    }

    _inFlight = true;
    final replyPort = ReceivePort();
    final payload = Map<String, dynamic>.from(request.payload)
      ..['replyPort'] = replyPort.sendPort;

    _isolateSendPort!.send(payload);

    replyPort.first
        .timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        replyPort.close();
        _log.severe('Transcription timed out (45 s) — respawning isolate');
        _respawn();
        return null;
      },
    )
        .then((dynamic response) {
      _inFlight = false;
      if (response == null) {
        request.completer.complete(const Err('Transcription timed out (45 s)'));
      } else {
        request.completer.complete(Ok(response));
      }
      _drainQueue();
    }).catchError((Object e, StackTrace st) {
      _inFlight = false;
      _log.severe('Transcription dispatch error', e, st);
      request.completer.complete(Err('Transcription dispatch error: $e', cause: e));
      _drainQueue();
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static Float32List _toFloat32(Int16List pcm) {
    final f = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      f[i] = pcm[i] / 32768.0;
    }
    return f;
  }
}
