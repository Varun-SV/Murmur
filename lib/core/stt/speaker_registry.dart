import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'package:murmur/data/models/speaker.dart';

final _log = Logger('SpeakerRegistry');

// Cosine similarity threshold for speaker matching.
const _kSimilarityThreshold = 0.75;

/// Session-scoped speaker registry. Never persisted to SQLite.
/// All state resets when the pipeline stops and the object is discarded.
class SpeakerRegistry {
  final Map<String, Float32List> _centroids = {};
  final Map<String, int> _counts = {};
  final Map<String, Speaker> _speakers = {};

  List<Speaker> get speakers => List.unmodifiable(_speakers.values.toList());

  /// Identifies or creates a speaker from a 192-dim L2-normalised embedding.
  ///
  /// Returns `(speakerId, isNew)`. `isNew` is true the first time a speaker
  /// is assigned that ID so the caller can notify the UI.
  (String speakerId, bool isNew) identify(Float32List embedding) {
    String? bestId;
    var bestSim = -1.0;

    for (final entry in _centroids.entries) {
      final sim = _cosineSimilarity(embedding, entry.value);
      if (sim > bestSim) {
        bestSim = sim;
        bestId = entry.key;
      }
    }

    if (bestId != null && bestSim >= _kSimilarityThreshold) {
      _updateCentroid(bestId, embedding);
      _log.fine('Speaker match: $bestId (sim=${bestSim.toStringAsFixed(3)})');
      return (bestId, false);
    }

    // New speaker.
    final newId = 'spk_${_centroids.length + 1}';
    final label = 'Speaker ${_centroids.length + 1}';
    _centroids[newId] = _l2Normalize(embedding);
    _counts[newId] = 1;
    _speakers[newId] = Speaker(id: newId, label: label, firstSeen: DateTime.now());
    _log.info('New speaker: $newId "$label"');
    return (newId, true);
  }

  Speaker? speaker(String id) => _speakers[id];

  void clear() {
    _centroids.clear();
    _counts.clear();
    _speakers.clear();
    _log.info('SpeakerRegistry cleared');
  }

  // Running centroid update (online mean).
  void _updateCentroid(String id, Float32List embedding) {
    final n = _counts[id]!;
    final centroid = _centroids[id]!;
    final norm = _l2Normalize(embedding);
    for (var i = 0; i < centroid.length; i++) {
      centroid[i] = (centroid[i] * n + norm[i]) / (n + 1);
    }
    _counts[id] = n + 1;
    // Re-normalise centroid.
    _l2NormalizeInPlace(centroid);
  }

  static double _cosineSimilarity(Float32List a, Float32List b) {
    var dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    // Vectors are L2-normalised, so |a||b| ≈ 1.
    return dot.clamp(-1.0, 1.0);
  }

  static Float32List _l2Normalize(Float32List v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm < 1e-10) return Float32List.fromList(v);
    final out = Float32List(v.length);
    for (var i = 0; i < v.length; i++) {
      out[i] = v[i] / norm;
    }
    return out;
  }

  static void _l2NormalizeInPlace(Float32List v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm < 1e-10) return;
    for (var i = 0; i < v.length; i++) {
      v[i] /= norm;
    }
  }
}
