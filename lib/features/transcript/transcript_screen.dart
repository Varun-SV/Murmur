import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murmur/features/transcript/transcript_provider.dart';
import 'package:murmur/services/pipeline_orchestrator.dart';

class TranscriptScreen extends ConsumerStatefulWidget {
  const TranscriptScreen({super.key});

  @override
  ConsumerState<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends ConsumerState<TranscriptScreen> {
  late final TextEditingController _modelPathCtrl;
  late final ScrollController _scrollCtrl;

  static const _defaultModelPath = '/sdcard/Download/whisper-base.bin';

  @override
  void initState() {
    super.initState();
    _modelPathCtrl = TextEditingController(text: _defaultModelPath);
    _scrollCtrl = ScrollController();
    _loadModelPath();
  }

  @override
  void dispose() {
    _modelPathCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('model_path') ?? _defaultModelPath;
    if (mounted) setState(() => _modelPathCtrl.text = path);
  }

  Future<void> _saveModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('model_path', path);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _modelPathCtrl,
              decoration: const InputDecoration(
                labelText: 'Whisper model path',
                hintText: '/sdcard/Download/whisper-base.bin',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: _saveModelPath,
            ),
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
        await _saveModelPath(_modelPathCtrl.text);
        await notifier.startPipeline();
      case PipelineRecording() || PipelineTranscribing():
        await notifier.stopPipeline();
    }
  }

  static String _statusLabel(PipelineState s) => switch (s) {
        PipelineIdle() => 'Idle',
        PipelineRecording() => 'Recording…',
        PipelineTranscribing() => 'Transcribing…',
        PipelineError(:final message) => 'Error: $message',
      };

  static Widget _fabIcon(PipelineState s) => switch (s) {
        PipelineIdle() => const Icon(Icons.mic),
        PipelineRecording() => const Icon(Icons.stop),
        PipelineTranscribing() => const Icon(Icons.hourglass_bottom),
        PipelineError() => const Icon(Icons.refresh),
      };

  static String _fabTooltip(PipelineState s) => switch (s) {
        PipelineIdle() || PipelineError() => 'Start listening',
        PipelineRecording() || PipelineTranscribing() => 'Stop listening',
      };

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}
