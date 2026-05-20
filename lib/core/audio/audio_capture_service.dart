import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/result.dart';

final _log = Logger('AudioCaptureService');

/// Wraps the Android ↔ Dart platform-channel contract defined in AudioCaptureChannel.kt.
///
/// Subscribe to [pcmStream] BEFORE calling [start]; frames emitted before the
/// subscription are lost.
class AudioCaptureService {
  static const _methodChannel = MethodChannel('com.murmur.audio/capture');
  static const _eventChannel = EventChannel('com.murmur.audio/pcm_stream');

  Stream<Uint8List>? _pcmStream;

  /// Broadcast stream of raw PCM chunks (16 kHz, mono, int16 LE).
  ///
  /// Must be subscribed before [start] is called.
  Stream<Uint8List> get pcmStream {
    _pcmStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic data) => data as Uint8List);
    return _pcmStream!;
  }

  /// Ask the native layer to start AudioRecord and the foreground service.
  Future<Result<void>> start() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('start');
      if (result == 'ok') {
        _log.info('Audio capture started');
        return const Ok(null);
      }
      return Err(result ?? 'unknown error from start()');
    } on PlatformException catch (e, st) {
      _log.severe('start() PlatformException', e, st);
      return Err('PlatformException: ${e.message}', cause: e);
    }
  }

  /// Ask the native layer to stop AudioRecord and the foreground service.
  Future<Result<void>> stop() async {
    try {
      await _methodChannel.invokeMethod<String>('stop');
      _log.info('Audio capture stopped');
      return const Ok(null);
    } on PlatformException catch (e, st) {
      _log.severe('stop() PlatformException', e, st);
      return Err('PlatformException: ${e.message}', cause: e);
    }
  }

  /// Returns the current capture state as reported by the native layer.
  Future<String> status() async {
    try {
      return await _methodChannel.invokeMethod<String>('status') ?? 'idle';
    } on PlatformException catch (e) {
      _log.warning('status() PlatformException: ${e.message}');
      return 'idle';
    }
  }
}
