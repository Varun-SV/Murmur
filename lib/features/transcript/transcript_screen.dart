import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/features/settings/settings_provider.dart';
import 'package:murmur/features/transcript/transcript_provider.dart';
import 'package:murmur/services/pipeline_orchestrator.dart';

class TranscriptScreen extends ConsumerStatefulWidget {
  const TranscriptScreen({super.key});

  @override
  ConsumerState<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends ConsumerState<TranscriptScreen> {
  final _scrollCtrl = ScrollController();
  bool _degradedBannerDismissed = false;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pipeline = ref.watch(pipelineProvider);
    final transcripts = ref.watch(transcriptProvider);

    ref.listen(transcriptProvider, (previous, next) {
      if (next.length > (previous?.length ?? 0)) _scrollToBottom();
    });

    // Reset banner dismissal when pipeline restarts.
    ref.listen(pipelineProvider, (previous, next) {
      if (previous is! PipelineRecording && next is PipelineRecording) {
        setState(() => _degradedBannerDismissed = false);
      }
    });

    final degraded = switch (pipeline) {
      PipelineRecording(:final degradedFeatures) => degradedFeatures,
      _ => const <String>[],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Murmur'),
        actions: [
          if (transcripts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear transcripts',
              onPressed: () => ref.read(transcriptProvider.notifier).clear(),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Degraded-mode banner
          if (degraded.isNotEmpty && !_degradedBannerDismissed)
            MaterialBanner(
              content: Text(
                'Running without: ${degraded.join(', ')}. '
                'Check model paths in Settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      setState(() => _degradedBannerDismissed = true),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Status: ${_statusLabel(pipeline)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (pipeline is PipelineError)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.error_outline, size: 14, color: Colors.red),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: transcripts.isEmpty
                ? const Center(
                    child: Text(
                      'No transcripts yet.\nTap ▶ to start listening.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: transcripts.length,
                    itemBuilder: (context, i) {
                      final t = transcripts[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text(
                            t.text.isEmpty ? '(no speech detected)' : t.text,
                          ),
                          subtitle: Text(
                            '${t.language.toUpperCase()} · '
                            '${(t.confidence * 100).toStringAsFixed(0)}% · '
                            '${_formatTime(t.timestamp)}',
                          ),
                          dense: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onFabTap(pipeline),
        tooltip: _fabTooltip(pipeline),
        child: _fabIcon(pipeline),
      ),
    );
  }

  Future<void> _onFabTap(PipelineState state) async {
    final notifier = ref.read(pipelineProvider.notifier);
    switch (state) {
      case PipelineIdle() || PipelineError():
        // Sync the whisper model path from settings before starting.
        await notifier.startPipeline();
      case PipelineRecording() || PipelineTranscribing() || PipelinePaused():
        await notifier.stopPipeline();
    }
  }

  static String _statusLabel(PipelineState s) => switch (s) {
        PipelineIdle() => 'Idle',
        PipelineRecording(degradedFeatures: final d) when d.isNotEmpty =>
          'Recording (degraded)',
        PipelineRecording() => 'Recording…',
        PipelineTranscribing() => 'Transcribing…',
        PipelinePaused() => 'Paused',
        PipelineError(:final message) => 'Error: $message',
      };

  static Widget _fabIcon(PipelineState s) => switch (s) {
        PipelineIdle() => const Icon(Icons.mic),
        PipelineRecording() || PipelineTranscribing() => const Icon(Icons.stop),
        PipelinePaused() => const Icon(Icons.stop),
        PipelineError() => const Icon(Icons.refresh),
      };

  static String _fabTooltip(PipelineState s) => switch (s) {
        PipelineIdle() || PipelineError() => 'Start listening',
        PipelineRecording() ||
        PipelineTranscribing() ||
        PipelinePaused() =>
          'Stop listening',
      };

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}
