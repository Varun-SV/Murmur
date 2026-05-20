import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/features/settings/settings_provider.dart';
import 'package:murmur/services/model_manager.dart';

final _vadDownloadProgressProvider = StreamProvider<double?>(
  (ref) => ref.read(modelManagerProvider).downloadProgress,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (settings) => ListView(
          children: [
            const _SectionHeader('VAD (Voice Activity Detection)'),
            SwitchListTile(
              title: const Text('Enable VAD'),
              subtitle: const Text('Skip silent audio segments before transcribing'),
              value: settings.vadEnabled,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setVadEnabled(v),
            ),
            ListTile(
              title: const Text('VAD Threshold'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: settings.vadThreshold,
                    min: 0.1,
                    max: 0.9,
                    divisions: 16,
                    label: settings.vadThreshold.toStringAsFixed(2),
                    onChanged: settings.vadEnabled
                        ? (v) => ref
                            .read(settingsProvider.notifier)
                            .setVadThreshold(v)
                        : null,
                  ),
                  Text(
                    'Current: ${settings.vadThreshold.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              isThreeLine: true,
            ),
            const Divider(),
            const _SectionHeader('Models'),
            ListTile(
              title: const Text('Whisper model path'),
              subtitle: Text(settings.whisperModelPath),
            ),
            const _VadModelTile(),
          ],
        ),
      ),
    );
  }
}

class _VadModelTile extends ConsumerWidget {
  const _VadModelTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_vadDownloadProgressProvider);

    return ListTile(
      title: const Text('Silero VAD model'),
      subtitle: progress.when(
        loading: () => const Text('Checking...'),
        error: (err, _) => Text('Error: $err'),
        data: (p) {
          if (p == null) {
            return const Text('Downloaded');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Downloading: ${(p * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: p),
            ],
          );
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download),
        tooltip: 'Re-download VAD model',
        onPressed: () {
          ref.read(modelManagerProvider).getVadModelPath();
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
