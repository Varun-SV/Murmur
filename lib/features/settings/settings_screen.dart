import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/core/result.dart';
import 'package:murmur/features/settings/settings_provider.dart';
import 'package:murmur/services/model_manager.dart';

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
            const _SectionHeader('Speaker Diarization'),
            SwitchListTile(
              title: const Text('Enable speaker encoder'),
              subtitle: const Text('Identify who is speaking using ECAPA-TDNN'),
              value: settings.speakerEncoderEnabled,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setSpeakerEncoderEnabled(v),
            ),
            _ModelPathTile(
              title: 'Speaker model path',
              path: settings.speakerModelPath,
              enabled: settings.speakerEncoderEnabled,
              onSave: (p) =>
                  ref.read(settingsProvider.notifier).setSpeakerModelPath(p),
            ),
            const Divider(),
            const _SectionHeader('LLM Extraction'),
            SwitchListTile(
              title: const Text('Enable Gemma LLM'),
              subtitle: const Text('Refine reminder extraction with on-device Gemma'),
              value: settings.llmEnabled,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setLlmEnabled(v),
            ),
            _ModelPathTile(
              title: 'Gemma model path',
              path: settings.gemmaModelPath,
              enabled: settings.llmEnabled,
              onSave: (p) =>
                  ref.read(settingsProvider.notifier).setGemmaModelPath(p),
            ),
            const Divider(),
            const _SectionHeader('Models'),
            _ModelPathTile(
              title: 'Whisper model path',
              path: settings.whisperModelPath,
              enabled: true,
              onSave: (p) =>
                  ref.read(settingsProvider.notifier).setWhisperModelPath(p),
            ),
            const _VadModelTile(),
          ],
        ),
      ),
    );
  }
}

/// Tappable model-path tile that opens an edit dialog.
class _ModelPathTile extends StatelessWidget {
  const _ModelPathTile({
    required this.title,
    required this.path,
    required this.enabled,
    required this.onSave,
  });

  final String title;
  final String path;
  final bool enabled;
  final void Function(String) onSave;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      enabled: enabled,
      trailing: enabled ? const Icon(Icons.edit_outlined, size: 18) : null,
      onTap: enabled ? () => _showEditDialog(context) : null,
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            helperText: 'Full path on device, e.g. /sdcard/Download/…',
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (confirmed == true) onSave(ctrl.text.trim());
  }
}

/// VAD model download tile with progress indicator and SnackBar feedback.
class _VadModelTile extends ConsumerStatefulWidget {
  const _VadModelTile();

  @override
  ConsumerState<_VadModelTile> createState() => _VadModelTileState();
}

class _VadModelTileState extends ConsumerState<_VadModelTile> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Silero VAD model'),
      subtitle: StreamBuilder<double?>(
        stream: ref.read(modelManagerProvider).downloadProgress,
        builder: (context, snap) {
          if (_downloading && snap.hasData && snap.data != null) {
            final p = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloading: ${(p * 100).toStringAsFixed(0)}%'),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: p),
              ],
            );
          }
          return const Text('Tap to download / re-download');
        },
      ),
      trailing: _downloading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download VAD model',
              onPressed: _download,
            ),
    );
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    final result = await ref.read(modelManagerProvider).getVadModelPath();
    if (!mounted) return;
    setState(() => _downloading = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case Ok():
        messenger.showSnackBar(
          const SnackBar(content: Text('VAD model ready')),
        );
      case Err(:final message):
        messenger.showSnackBar(
          SnackBar(content: Text('Download failed: $message')),
        );
    }
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
