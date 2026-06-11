import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:murmur/data/database/database_providers.dart';
import 'package:murmur/data/models/speaker.dart';

final _log = Logger('SpeakersNotifier');

class SpeakersNotifier extends AsyncNotifier<List<Speaker>> {
  @override
  Future<List<Speaker>> build() async {
    final dao = ref.read(speakerDaoProvider);
    return dao.queryAll();
  }

  /// Upserts [speaker] into the database and refreshes state.
  Future<void> add(Speaker speaker) async {
    final dao = ref.read(speakerDaoProvider);
    try {
      await dao.upsert(speaker);
      state = await AsyncValue.guard(() => dao.queryAll());
    } catch (e, st) {
      _log.severe('add failed', e, st);
      state = AsyncError(e, st);
    }
  }

  /// Updates the display label for [id] and refreshes in-memory state.
  Future<void> updateLabel(String id, String label) async {
    final dao = ref.read(speakerDaoProvider);
    try {
      await dao.updateLabel(id, label);
      // Optimistic in-memory patch so the UI doesn't flash.
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(
          current
              .map((s) => s.id == id ? s.copyWith(label: label) : s)
              .toList(),
        );
      }
    } catch (e, st) {
      _log.severe('updateLabel failed', e, st);
      state = AsyncError(e, st);
    }
  }

  /// Deletes [id] from the database and removes it from state.
  Future<void> remove(String id) async {
    final dao = ref.read(speakerDaoProvider);
    try {
      await dao.delete(id);
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current.where((s) => s.id != id).toList());
      }
    } catch (e, st) {
      _log.severe('remove failed', e, st);
      state = AsyncError(e, st);
    }
  }

  /// Deletes all speakers from the database and clears state.
  Future<void> clear() async {
    final dao = ref.read(speakerDaoProvider);
    try {
      await dao.deleteAll();
      state = const AsyncData([]);
    } catch (e, st) {
      _log.severe('clear failed', e, st);
      state = AsyncError(e, st);
    }
  }

  /// Returns the speaker with [id], or null if not loaded / not found.
  Speaker? speakerById(String id) {
    final speakers = state.valueOrNull;
    if (speakers == null) return null;
    try {
      return speakers.firstWhere((s) => s.id == id);
    } on StateError {
      return null;
    }
  }
}

final speakersProvider =
    AsyncNotifierProvider<SpeakersNotifier, List<Speaker>>(
  SpeakersNotifier.new,
);
