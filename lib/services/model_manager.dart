import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:murmur/core/result.dart';

final modelManagerProvider = Provider<ModelManager>((ref) {
  final mgr = ModelManager();
  ref.onDispose(mgr.dispose);
  return mgr;
});

final _log = Logger('ModelManager');

class ModelManager {
  static const _vadModelUrl =
      'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx';
  static const _vadModelFilename = 'silero_vad.onnx';

  final StreamController<double?> _progressController =
      StreamController<double?>.broadcast();

  Stream<double?> get downloadProgress => _progressController.stream;

  /// Returns the on-disk path to the VAD model, downloading it if absent.
  Future<Result<String>> getVadModelPath() async {
    try {
      final path = await _modelPath();
      final file = File(path);

      if (file.existsSync()) {
        _log.info('VAD model found at $path');
        return Ok(path);
      }

      return _download(path);
    } catch (e, st) {
      _log.severe('getVadModelPath failed', e, st);
      return Err('Failed to get VAD model path: $e', cause: e as Object);
    }
  }

  Future<Result<String>> _download(String destPath) async {
    _log.info('Downloading VAD model from $_vadModelUrl');
    final file = File(destPath);
    await Directory(file.parent.path).create(recursive: true);

    HttpClient? client;
    try {
      client = HttpClient();
      final request = await client.getUrl(Uri.parse(_vadModelUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        return Err('VAD model download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            _progressController.add(receivedBytes / totalBytes);
          }
        }
      } finally {
        await sink.close();
      }

      _progressController.add(null); // download complete
      _log.info('VAD model downloaded to $destPath');
      return Ok(destPath);
    } catch (e, st) {
      _log.severe('Download failed', e, st);
      // Remove partial file
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {}
      _progressController.addError(e);
      return Err('VAD model download error: $e', cause: e as Object);
    } finally {
      client?.close();
    }
  }

  Future<String> _modelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/$_vadModelFilename';
  }

  void dispose() {
    _progressController.close();
  }
}
