import 'dart:async';
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

  static const _maxReconnectAttempts = 3;
  static const _reconnectDelayMs = 2000;

  Stream<Uint8List>? _pcmStream;
  StreamSubscription<Uint8List>? _pcmSubscription;
  int _reconnectAttempts = 0;

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
  ///
  /// IMPORTANT: Subscribe to pcmStream BEFORE calling start(). Frames emitted
  /// before the subscription is active are lost.
  Future<Result<void>> start() async {
    // IMPORTANT: Subscribe to pcmStream BEFORE calling start(). Frames emitted
    // before subscription are lost. The orchestrator must set up its pcmStream
    // listener prior to invoking this method.
    try {
      final result = await _methodChannel.invokeMethod<String>('start');
      if (result == 'ok') {
        _log.info('Audio capture started');
        _reconnectAttempts = 0;
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

  /// Listen to [pcmStream] and forward chunks to [onData].
  ///
  /// Handles stream errors by logging at severe level and attempting to
  /// reconnect up to [_maxReconnectAttempts] times with a 2-second delay.
  /// The reconnect attempt counter resets on the next successful [start] call.
  void listenWithReconnect({
    required void Function(Uint8List chunk) onData,
    void Function()? onDone,
  }) {
    _pcmSubscription?.cancel();
    _pcmSubscription = pcmStream.listen(
      (chunk) {
        onData(chunk);
      },
      onError: (Object error, StackTrace st) {
        _log.severe('PCM stream error — attempting reconnect', error, st);
        _pcmSubscription?.cancel();
        _pcmSubscription = null;

        if (_reconnectAttempts < _maxReconnectAttempts) {
          _reconnectAttempts++;
          _log.warning(
              'Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts '
              'in ${_reconnectDelayMs}ms');
          Future<void>.delayed(
            const Duration(milliseconds: _reconnectDelayMs),
            () {
              // Re-attach listener before calling start so no frames are lost.
              listenWithReconnect(onData: onData, onDone: onDone);
              start();
            },
          );
        } else {
          _log.severe(
              'Max reconnect attempts ($_maxReconnectAttempts) reached. '
              'Giving up on PCM stream.');
        }
      },
      onDone: () {
        _log.info('PCM stream closed');
        onDone?.call();
      },
      cancelOnError: true,
    );
  }

  /// Cancel the active PCM stream subscription, if any.
  Future<void> cancelSubscription() async {
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
  }
}
