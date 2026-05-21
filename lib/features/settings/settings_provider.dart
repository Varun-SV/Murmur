import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.vadEnabled = true,
    this.vadThreshold = 0.5,
    this.whisperModelPath = '/sdcard/Download/whisper-base.bin',
    this.speakerEncoderEnabled = true,
    this.speakerModelPath = '/sdcard/Download/ecapa_tdnn.onnx',
    this.llmEnabled = true,
    this.gemmaModelPath = '/sdcard/Download/gemma-2b.bin',
  });

  final bool vadEnabled;
  final double vadThreshold;
  final String whisperModelPath;
  final bool speakerEncoderEnabled;
  final String speakerModelPath;
  final bool llmEnabled;
  final String gemmaModelPath;

  AppSettings copyWith({
    bool? vadEnabled,
    double? vadThreshold,
    String? whisperModelPath,
    bool? speakerEncoderEnabled,
    String? speakerModelPath,
    bool? llmEnabled,
    String? gemmaModelPath,
  }) {
    return AppSettings(
      vadEnabled: vadEnabled ?? this.vadEnabled,
      vadThreshold: vadThreshold ?? this.vadThreshold,
      whisperModelPath: whisperModelPath ?? this.whisperModelPath,
      speakerEncoderEnabled: speakerEncoderEnabled ?? this.speakerEncoderEnabled,
      speakerModelPath: speakerModelPath ?? this.speakerModelPath,
      llmEnabled: llmEnabled ?? this.llmEnabled,
      gemmaModelPath: gemmaModelPath ?? this.gemmaModelPath,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _keyVadEnabled = 'vad_enabled';
  static const _keyVadThreshold = 'vad_threshold';
  static const _keyModelPath = 'model_path';
  static const _keySpeakerEnabled = 'speaker_enabled';
  static const _keySpeakerModelPath = 'speaker_model_path';
  static const _keyLlmEnabled = 'llm_enabled';
  static const _keyGemmaModelPath = 'gemma_model_path';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      vadEnabled: prefs.getBool(_keyVadEnabled) ?? true,
      vadThreshold: prefs.getDouble(_keyVadThreshold) ?? 0.5,
      whisperModelPath:
          prefs.getString(_keyModelPath) ?? '/sdcard/Download/whisper-base.bin',
      speakerEncoderEnabled: prefs.getBool(_keySpeakerEnabled) ?? true,
      speakerModelPath:
          prefs.getString(_keySpeakerModelPath) ?? '/sdcard/Download/ecapa_tdnn.onnx',
      llmEnabled: prefs.getBool(_keyLlmEnabled) ?? true,
      gemmaModelPath:
          prefs.getString(_keyGemmaModelPath) ?? '/sdcard/Download/gemma-2b.bin',
    );
  }

  Future<void> setVadEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVadEnabled, value);
    state = AsyncData(state.value!.copyWith(vadEnabled: value));
  }

  Future<void> setVadThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVadThreshold, value);
    state = AsyncData(state.value!.copyWith(vadThreshold: value));
  }

  Future<void> setWhisperModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModelPath, path);
    state = AsyncData(state.value!.copyWith(whisperModelPath: path));
  }

  Future<void> setSpeakerEncoderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySpeakerEnabled, value);
    state = AsyncData(state.value!.copyWith(speakerEncoderEnabled: value));
  }

  Future<void> setSpeakerModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpeakerModelPath, path);
    state = AsyncData(state.value!.copyWith(speakerModelPath: path));
  }

  Future<void> setLlmEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLlmEnabled, value);
    state = AsyncData(state.value!.copyWith(llmEnabled: value));
  }

  Future<void> setGemmaModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGemmaModelPath, path);
    state = AsyncData(state.value!.copyWith(gemmaModelPath: path));
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
