import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.vadEnabled = true,
    this.vadThreshold = 0.5,
    this.whisperModelPath = '/sdcard/Download/whisper-base.bin',
  });

  final bool vadEnabled;
  final double vadThreshold;
  final String whisperModelPath;

  AppSettings copyWith({
    bool? vadEnabled,
    double? vadThreshold,
    String? whisperModelPath,
  }) {
    return AppSettings(
      vadEnabled: vadEnabled ?? this.vadEnabled,
      vadThreshold: vadThreshold ?? this.vadThreshold,
      whisperModelPath: whisperModelPath ?? this.whisperModelPath,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _keyVadEnabled = 'vad_enabled';
  static const _keyVadThreshold = 'vad_threshold';
  static const _keyModelPath = 'model_path';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      vadEnabled: prefs.getBool(_keyVadEnabled) ?? true,
      vadThreshold: prefs.getDouble(_keyVadThreshold) ?? 0.5,
      whisperModelPath:
          prefs.getString(_keyModelPath) ?? '/sdcard/Download/whisper-base.bin',
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
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
