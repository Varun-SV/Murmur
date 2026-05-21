import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/data/models/speaker.dart';

class SpeakersNotifier extends Notifier<List<Speaker>> {
  @override
  List<Speaker> build() => [];

  void add(Speaker speaker) {
    if (!state.any((s) => s.id == speaker.id)) {
      state = [...state, speaker];
    }
  }

  void clear() => state = [];
}

final speakersProvider =
    NotifierProvider<SpeakersNotifier, List<Speaker>>(SpeakersNotifier.new);
