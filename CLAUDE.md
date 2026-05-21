# CLAUDE.md — Murmur

Murmur is an always-on ambient reminder engine for Android (iOS later). It keeps a 30-second rolling audio buffer, transcribes speech fully on-device using Whisper, and silently extracts actionable reminders from conversations using rule-based NLP + an optional on-device LLM. No audio ever leaves the device.

---

## ⚠️ NON-NEGOTIABLE CONSTRAINTS

These rules cannot be relaxed for any reason, including testing or convenience:

1. **NEVER make a network request with audio data.** No STT APIs, no cloud functions, no telemetry.
2. **NEVER write raw PCM audio to disk.** The ring buffer lives in RAM only.
3. **ALWAYS run Whisper inference in a Dart Isolate.** It blocks for 3–8s — running on the main isolate freezes the UI.
4. **ALWAYS run the foreground service** when the mic is active. Android silently kills background mic access without it.
5. **NEVER load Gemma eagerly.** Load on first LLM extraction request, release after 60s idle.

---

## Pipeline (data flow)

```
Mic (AudioRecord)
  → PCM frames via EventChannel
  → RingBuffer (30s, RAM only)
  → [flush every 30s] → VAD check
      ├─ silent  → discard, loop
      └─ speech  → Whisper (Dart Isolate)
                     → transcript + language code
                     → SpeakerEncoder (ONNX, Isolate)
                         → speaker_id via cosine clustering
                     → RuleEngine (sync, main isolate OK)
                         ├─ no match → discard
                         └─ match    → LlmExtractor (MediaPipe, Isolate)
                                          → Reminder (task, scheduledAt, speakerId, language)
                                          → ReminderDao.insert()
                                          → NotificationService.schedule()
```

One Dart Isolate is reused for Whisper + SpeakerEncoder. LlmExtractor runs on a separate isolate managed by MediaPipe.

---

## Directory Structure

```
murmur/
├── android/
│   └── app/src/main/
│       ├── kotlin/com/murmur/app/
│       │   ├── MainActivity.kt
│       │   ├── MurmurForegroundService.kt   # mic lifecycle + notification
│       │   └── AudioCaptureChannel.kt       # MethodChannel + EventChannel impl
│       └── res/
├── native/
│   ├── whisper_cpp/                         # git submodule: ggerganov/whisper.cpp
│   ├── whisper_bridge.h                     # our C API surface (see FFI section)
│   ├── whisper_bridge.cpp                   # implementation wrapping whisper.cpp
│   └── CMakeLists.txt                       # builds libmurmur_bridge.so
├── lib/
│   ├── main.dart                            # ProviderScope + app entry
│   ├── app.dart                             # MaterialApp + router
│   ├── core/
│   │   ├── result.dart                      # sealed Result<T> type
│   │   ├── audio/
│   │   │   ├── ring_buffer.dart             # circular PCM buffer, RAM only
│   │   │   └── audio_capture_service.dart   # wraps platform channel
│   │   └── stt/
│   │       ├── whisper_ffi.dart             # hand-written FFI bindings
│   │       └── whisper_service.dart         # high-level Dart wrapper + Isolate mgmt
│   ├── data/
│   │   ├── database/
│   │   │   ├── app_database.dart            # sqflite setup + migrations
│   │   │   └── reminder_dao.dart            # all DB operations
│   │   └── models/
│   │       ├── reminder.dart                # Reminder + ReminderStatus
│   │       └── speaker.dart                 # Speaker (session-scoped)
│   ├── features/
│   │   ├── transcript/
│   │   │   ├── transcript_screen.dart       # Phase 1 debug UI
│   │   │   └── transcript_provider.dart     # TranscriptEntry + notifier
│   │   ├── reminders/
│   │   │   ├── reminders_screen.dart
│   │   │   ├── reminder_card.dart
│   │   │   └── reminders_provider.dart
│   │   └── settings/
│   │       ├── settings_screen.dart
│   │       └── settings_provider.dart
│   └── services/
│       ├── notification_service.dart        # flutter_local_notifications wrapper
│       ├── scheduler_service.dart           # android_alarm_manager_plus wrapper
│       └── pipeline_orchestrator.dart       # top-level pipeline state machine
├── test/
│   ├── unit/
│   └── widget/
├── assets/
│   └── patterns/
│       └── reminder_patterns.json
└── CLAUDE.md
```

**Note on native/ layout:** `whisper_bridge.h` and `whisper_bridge.cpp` live at the `native/` level (not inside `native/whisper_cpp/`) because files inside a git submodule directory cannot be tracked by the parent repository. The CMakeLists.txt uses `add_subdirectory(whisper_cpp)` to include the submodule's build, then links `murmur_bridge` against whisper's static target.

Models live outside the repo. See developer setup below.

---

## Tech Stack (locked)

| Layer | Package / Tool | Version |
|---|---|---|
| Framework | Flutter + Dart | ≥ 3.22 / ≥ 3.4 |
| State management | flutter_riverpod | ^2.5.1 |
| Background mic | flutter_foreground_task | ^8.x |
| Audio capture | record | ^5.x |
| STT | whisper.cpp (git submodule) + custom Dart FFI | v1.8.4 |
| FFI bindings | ffigen | ^9.x |
| VAD | Silero VAD via flutter_onnxruntime | ^1.x |
| Speaker encoder | ECAPA-TDNN (INT8 ONNX) via flutter_onnxruntime | ^1.x |
| LLM extraction | mediapipe_llm_inference | ^0.10.x |
| Database | sqflite | ^2.3.x |
| Notifications | flutter_local_notifications | ^17.x |
| Alarm scheduling | android_alarm_manager_plus | ^4.x (Android); flutter_local_notifications zonedSchedule (iOS) |
| Shared prefs | shared_preferences | ^2.3.x |
| Logging | logging | ^1.x |
| Timezone | timezone | ^0.9.x |
| Path utilities | path_provider | ^2.1.x |
| Path utilities | path | ^1.9.x |

Do not add packages outside this list without explicit discussion. Do not use `http`, `dio`, or any networking package.

---

## Platform Channel Contract

The platform ↔ Dart boundary is owned by the platform channel implementations and `audio_capture_service.dart`. Do not change the channel names or method signatures without updating both sides.

- **Android:** `AudioCaptureChannel.kt` + `MurmurForegroundService.kt`
- **iOS:** `ios/Runner/AudioCaptureChannel.swift`

```
MethodChannel: "com.murmur.audio/capture"

  start()   → void       Starts AudioRecord + foreground service
  stop()    → void       Stops capture + releases mic
  status()  → String     "recording" | "idle"

EventChannel: "com.murmur.audio/pcm_stream"
  stream → Uint8List     Raw PCM frames, 16 kHz, mono, int16 little-endian
                         Emitted as chunks of ~6400 bytes (200ms / 3200 samples)
```

`AudioCaptureService` in Dart wraps this channel. The rest of the app never touches platform channels directly.

**Ordering constraint:** Subscribe to the EventChannel's `pcmStream` BEFORE calling `start()`. Frames emitted before the subscription is active are lost.

---

## Whisper FFI Contract

The C API surface is in `native/whisper_bridge.h`. The Dart bindings in `whisper_ffi.dart` are hand-written to match this header exactly. To regenerate automatically:

```bash
dart run ffigen --config ffigen.yaml
```

```c
// native/whisper_bridge.h

typedef struct WhisperContext WhisperContext;

WhisperContext* whisper_bridge_init(const char* model_path);
void whisper_bridge_free(WhisperContext* ctx);

int whisper_bridge_transcribe(
  WhisperContext* ctx,
  const float*    pcm_f32,
  int             n_samples,
  char*           out_text,      // caller allocates 4096 bytes
  char*           out_lang,      // caller allocates 16 bytes (ISO 639-1)
  float*          out_confidence // geometric mean of token probabilities [0,1]
);
// Returns 0 on success, -1 on whisper_full failure, -2 if ctx is NULL.
```

The native library is named **`libmurmur_bridge.so`** (loaded via `DynamicLibrary.open('libmurmur_bridge.so')`).

Input PCM must be normalized to [-1.0, 1.0]. Convert from int16 before calling:
```dart
final floats = Float32List(pcm.length);
for (var i = 0; i < pcm.length; i++) {
  floats[i] = pcm[i] / 32768.0;
}
```

---

## State Management (Riverpod)

Use Riverpod exclusively. No `setState`, no `InheritedWidget`, no `Provider` (legacy).

**Provider conventions:**

```dart
// Pipeline state machine: NotifierProvider
final pipelineProvider = NotifierProvider<PipelineNotifier, PipelineState>(
  PipelineNotifier.new,
);

// Transcript list (Phase 1 debug): NotifierProvider
final transcriptProvider = NotifierProvider<TranscriptNotifier, List<TranscriptEntry>>(
  TranscriptNotifier.new,
);
```

- One provider file per feature.
- Notifiers contain logic. Screens contain only layout and `ref.watch`.
- Never call `ref.read` inside `build()`.

---

## Key Data Models

```dart
// lib/features/transcript/transcript_provider.dart (Phase 1)
@immutable
class TranscriptEntry {
  final String   text;
  final String   language;    // ISO 639-1
  final double   confidence;  // [0, 1]
  final DateTime timestamp;
}
```

Phase 2 adds `Reminder`, `Speaker`, and the SQLite schema.

---

## Dart Coding Conventions

**Naming:**
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Private fields: `_camelCase`
- Constants: `lowerCamelCase`

**Error handling:**
Sealed `Result<T>` in `lib/core/result.dart`. Never throw from service classes — return `Err(...)`.

**Isolates:**
Use `Isolate.spawn()` with a long-lived `ReceivePort` for streaming/repeated tasks (Whisper). Do not use `compute()`.

**Logging:**
```dart
import 'package:logging/logging.dart';
final _log = Logger('ClassName');
_log.info('...');
_log.warning('...');
_log.severe('...', error, stackTrace);
```
Never use `print()`.

**Null safety:**
Prefer non-nullable. Use `?` only when null is meaningful. Never use `!` without a prior null check.

---

## Build & Run

```bash
# Install dependencies
flutter pub get

# Run on connected Android device (debug)
flutter run

# Build release APK
flutter build apk --release

# Regenerate Whisper FFI bindings (after editing whisper_bridge.h)
dart run ffigen --config ffigen.yaml

# Run all unit tests
flutter test test/unit/

# Run with verbose pipeline logging
flutter run --dart-define=LOG_LEVEL=FINEST
```

---

## Developer Setup (first time)

### Android

```bash
# 1. Pull the whisper.cpp submodule
git submodule update --init native/whisper_cpp

# 2. Build libmurmur_bridge.so for Android arm64-v8a (requires Android NDK)
cmake -B build/android-arm64 \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21 \
  -DCMAKE_BUILD_TYPE=Release \
  native/
cmake --build build/android-arm64 --target murmur_bridge -j$(nproc)

# 3. Copy the shared library into the Android JNI directory
mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp build/android-arm64/libmurmur_bridge.so android/app/src/main/jniLibs/arm64-v8a/

# 4. Download the Whisper base model (~150 MB) and push to the device
# Download from: https://huggingface.co/ggerganov/whisper.cpp/tree/main
adb push ggml-base.bin /sdcard/Download/whisper-base.bin

# 5. Run
flutter run
```

### iOS (requires macOS with Xcode ≥ 15)

```bash
# 1. Scaffold the iOS project (generates Runner.xcodeproj, Podfile, etc.)
flutter create --platforms=ios .

# 2. Build libmurmur_bridge.dylib for iOS arm64
cmake -G Xcode -B build/ios \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  native/
cmake --build build/ios --target murmur_bridge --config Release

# 3. Copy the dylib into the iOS Frameworks directory
mkdir -p ios/Frameworks
cp build/ios/Release-iphoneos/libmurmur_bridge.dylib ios/Frameworks/
# Add ios/Frameworks/libmurmur_bridge.dylib to the Runner target in Xcode
# (Build Phases → Embed Frameworks)

# 4. Copy model files to the device via Xcode or Files app
#    Default paths expected by the app:
#    /private/var/mobile/Containers/Data/Application/<UUID>/Documents/whisper-base.bin
#    (update Settings screen paths after first launch)

# 5. Run
flutter run -d <ios-device-udid>
```

---

## DO NOTs

- **Do not** use `http` or any network package.
- **Do not** write audio bytes to any disk path.
- **Do not** run Whisper, ONNX, or Gemma inference on the main Dart isolate.
- **Do not** load Gemma at app start.
- **Do not** persist `Speaker` objects to SQLite.
- **Do not** use `setState` or `ChangeNotifier`. Riverpod only.
- **Do not** catch and swallow exceptions silently.
- **Do not** add new top-level packages without updating this file.
- **Do not** store model files inside the Flutter assets bundle.

---

## Phase Scope

| Phase | Scope | Status |
|---|---|---|
| 1 | Mic → ring buffer → Whisper → console transcript | ✅ Done |
| 2 | VAD + rule engine + SQLite + notifications + basic UI | ✅ Done |
| 3 | Gemma LLM extraction + speaker diarization | ✅ Done |
| 4 | Polish + iOS port | ✅ Done |
