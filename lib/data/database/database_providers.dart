import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/data/database/speaker_dao.dart';

/// Provides a [SpeakerDao] backed by the singleton [AppDatabase].
final speakerDaoProvider = Provider<SpeakerDao>((_) => const SpeakerDao());
