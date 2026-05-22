# Murmur

> Always-on ambient reminder engine — transcribes speech on-device, surfaces reminders silently. No audio ever leaves your phone.

[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.22-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%E2%89%A53.4-0175C2?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://developer.android.com)

---

## What is Murmur?

Murmur runs quietly in the background and listens for things you need to remember. It keeps a rolling 30-second audio buffer in RAM, and every time it detects speech, it transcribes the audio fully on-device using [whisper.cpp](https://github.com/ggerganov/whisper.cpp). It then scans those transcripts for actionable reminders — things like *"remind me to call the doctor tomorrow"* — and schedules a local notification at the right time.

There is no server, no cloud API, and no account. Every step of the pipeline — voice activity detection, transcription, speaker identification, and reminder extraction — runs entirely on the device. The raw audio buffer is never written to disk.

**Key features:**

- Always-on 30-second rolling audio buffer (RAM only, never persisted)
- On-device speech-to-text via whisper.cpp — no STT API calls
- Voice activity detection via Silero VAD (ONNX) to skip silent segments
- Speaker diarization via ECAPA-TDNN embeddings — reminders are attributed per speaker
- Two-stage reminder extraction: fast regex rule engine + optional Gemma LLM for complex phrasing
- Local notifications and alarm scheduling — no internet required
- Supports all languages Whisper supports (language is auto-detected per segment)

---

## Privacy

Murmur is built around a hard privacy contract:

| Guarantee | How it's enforced |
|---|---|
| Audio never sent over the network | No networking package (`http`, `dio`, etc.) is in the dependency tree |
| Raw PCM never written to disk | The ring buffer lives in a Dart `Float32List` in RAM; only transcripts reach SQLite |
| Inference runs on-device | Whisper (FFI), VAD (ONNX), speaker encoder (ONNX), and Gemma (MediaPipe) all run locally |
| Foreground service required | Android mandates a visible notification while the mic is active — Murmur won't silently record |

These constraints are non-negotiable and are enforced at the architecture level.

---

## How It Works

```
Mic (AudioRecord, 16 kHz mono int16)
  └─→ PCM frames via EventChannel (200 ms chunks)
        └─→ RingBuffer (30 s, RAM only)
              └─→ [flush every 30 s] → Silero VAD
                    ├─ silent  → discard, loop
                    └─ speech  → Whisper (Dart Isolate, ~3–8 s)
                                   → transcript + language code
                                   → ECAPA-TDNN speaker encoder (same Isolate)
                                       → speaker_id via cosine clustering
                                   → Rule engine (regex, synchronous)
                                       ├─ no match → discard
                                       └─ match    → Gemma LLM extractor (MediaPipe Isolate)
                                                        → Reminder { task, scheduledAt, speakerId, language }
                                                        → SQLite (ReminderDao)
                                                        → Local notification
```

Whisper and the speaker encoder share one long-lived Dart Isolate. Gemma runs on a separate Isolate managed by MediaPipe and is loaded lazily on first use, then released after 60 seconds of idle time.

---

## Getting Started (End Users)

### Requirements

- Android device running Android 8.0 (API 26) or later
- ~500 MB of free storage for model files
- A debug or release APK (see [Build Commands](#build-commands) or ask a developer for a build)

### Model Files

Murmur requires two model files that are not bundled in the APK:

| Model | File | Download |
|---|---|---|
| Whisper base (speech-to-text) | `ggml-base.bin` (~150 MB) | [HuggingFace — ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/main) |
| Gemma 2B IT (reminder extraction) | `gemma-2b-it-cpu-int8.bin` (~2 GB) | MediaPipe model gallery or Google AI Edge |

After installing the APK:

1. Copy the model files to your device (via ADB, Files app, or USB).
2. Open Murmur → **Settings**.
3. Set the **Whisper model path** and **Gemma model path** to wherever you placed the files (e.g. `/sdcard/Download/ggml-base.bin`).
4. Tap **Start Listening** on the main screen.

Murmur will begin transcribing and surfacing reminders as notifications.

---

## Developer Setup

### Prerequisites

- Flutter ≥ 3.22 and Dart ≥ 3.4 ([install guide](https://docs.flutter.dev/get-started/install))
- Android NDK (r25c or later) — install via Android Studio → SDK Manager → SDK Tools
- CMake 3.22+ (bundled with the NDK or installable via SDK Manager)
- A connected Android device or emulator (API 26+)

### 1. Clone and initialise submodules

```bash
git clone https://github.com/varun-sv/murmur.git
cd murmur
git submodule update --init native/whisper_cpp
```

### 2. Build the native bridge library

```bash
cmake -B build/android-arm64 \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21 \
  -DCMAKE_BUILD_TYPE=Release \
  native/
cmake --build build/android-arm64 --target murmur_bridge -j$(nproc)

mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp build/android-arm64/libmurmur_bridge.so android/app/src/main/jniLibs/arm64-v8a/
```

### 3. Install Flutter dependencies

```bash
flutter pub get
```

### 4. Push the Whisper model to your device

```bash
# Download ggml-base.bin from HuggingFace first, then:
adb push ggml-base.bin /sdcard/Download/whisper-base.bin
```

### 5. Run

```bash
flutter run
```

Set model paths in Settings on first launch.

### iOS

iOS setup requires macOS + Xcode ≥ 15. See the full iOS instructions in [CLAUDE.md](CLAUDE.md#ios-requires-macos-with-xcode--15).

---

## Build Commands

```bash
# Install dependencies
flutter pub get

# Run on connected device (debug)
flutter run

# Run with verbose pipeline logging
flutter run --dart-define=LOG_LEVEL=FINEST

# Build release APK
flutter build apk --release

# Run unit tests
flutter test test/unit/

# Regenerate Whisper FFI bindings (after editing native/whisper_bridge.h)
dart run ffigen --config ffigen.yaml
```

---

## Architecture Overview

The codebase is organised into four layers:

| Layer | Location | Responsibility |
|---|---|---|
| **Core** | `lib/core/` | Audio capture, ring buffer, VAD, Whisper FFI, speaker encoder, NLP rule engine |
| **Data** | `lib/data/` | SQLite database, `ReminderDao`, data models (`Reminder`, `Speaker`) |
| **Features** | `lib/features/` | Riverpod providers + Flutter screens for transcripts, reminders, speakers, and settings |
| **Services** | `lib/services/` | Pipeline orchestrator, notification scheduling, LLM extractor, model manager |

State management is [Riverpod](https://riverpod.dev) throughout — no `setState`, no `ChangeNotifier`. Errors are propagated via the sealed `Result<T>` type in `lib/core/result.dart`. Heavy inference (Whisper, ONNX, Gemma) always runs in a Dart Isolate — never on the main isolate.

For a detailed breakdown of conventions, platform channel contracts, and FFI bindings, see [CLAUDE.md](CLAUDE.md).

---

## Tech Stack

| Layer | Package / Tool | Version |
|---|---|---|
| Framework | Flutter + Dart | ≥ 3.22 / ≥ 3.4 |
| State management | flutter_riverpod | ^2.5.1 |
| Background mic | flutter_foreground_task | ^8.x |
| Audio capture | record | ^5.x |
| STT | whisper.cpp (git submodule) + Dart FFI | v1.8.4 |
| FFI code-gen | ffigen | ^9.x |
| VAD | Silero VAD via flutter_onnxruntime | ^1.x |
| Speaker encoder | ECAPA-TDNN INT8 via flutter_onnxruntime | ^1.x |
| LLM extraction | mediapipe_llm_inference | ^0.10.x |
| Database | sqflite | ^2.3.x |
| Notifications | flutter_local_notifications | ^17.x |
| Alarm scheduling | android_alarm_manager_plus | ^4.x |
| Shared prefs | shared_preferences | ^2.3.x |
| Timezone | timezone | ^0.9.x |

---

## License

MIT © 2026 Varun S V — see [LICENSE](LICENSE) for the full text.
