import AVFoundation
import Flutter

// Implements the same platform channel contract as the Android AudioCaptureChannel:
//   MethodChannel  "com.murmur.audio/capture"  → start() / stop() / status()
//   EventChannel   "com.murmur.audio/pcm_stream" → Uint8List chunks (Int16 LE, 16 kHz mono)
//
// The Dart-side AudioCaptureService is unchanged — it talks to these channels
// the same way it talks to their Android counterparts.
//
// NOTE: Before using this file, run `flutter create --platforms=ios .` in the
// project root to generate the Xcode project structure (Runner.xcodeproj,
// AppDelegate.swift, Info.plist, etc.), then add AudioCaptureChannel.swift to
// the Runner target in Xcode.

class AudioCaptureChannel: NSObject {
  static let methodChannelName = "com.murmur.audio/capture"
  static let eventChannelName  = "com.murmur.audio/pcm_stream"

  // 16 kHz mono, matching Android AudioRecord configuration.
  private static let sampleRate: Double = 16_000
  // 200 ms chunks = 3200 samples = 6400 bytes (Int16 LE), matching Android.
  private static let chunkSamples = 3_200

  private let engine = AVAudioEngine()
  private var eventSink: FlutterEventSink?
  private var isCapturing = false
  // Converter created once in startCapture() and reused across tap callbacks.
  private var converter: AVAudioConverter?

  func register(with binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler(handleMethodCall)

    let eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: binaryMessenger
    )
    eventChannel.setStreamHandler(self)
  }

  // MARK: – MethodChannel handler

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      startCapture(result: result)
    case "stop":
      stopCapture()
      result(nil)
    case "status":
      result(isCapturing ? "recording" : "idle")
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: – Audio capture

  private func startCapture(result: @escaping FlutterResult) {
    guard !isCapturing else { result(nil); return }

    let session = AVAudioSession.sharedInstance()
    do {
      // Use .playAndRecord with .measurement mode so Murmur does not interrupt
      // other audio (music, podcasts). .mixWithOthers prevents session takeover.
      try session.setCategory(
        .playAndRecord,
        mode: .measurement,
        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
      )
      try session.setActive(true)
    } catch {
      result(FlutterError(code: "AUDIO_SESSION", message: error.localizedDescription, details: nil))
      return
    }

    // Configure the engine to produce 16 kHz mono Float32 from the input tap.
    let inputNode = engine.inputNode
    let nativeFormat = inputNode.outputFormat(forBus: 0)
    guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Self.sampleRate,
      channels: 1,
      interleaved: false
    ) else {
      result(FlutterError(code: "FORMAT", message: "Cannot create 16 kHz mono format", details: nil))
      return
    }

    // Create the converter once here; reuse it in every tap callback.
    guard let audioConverter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
      result(FlutterError(code: "CONVERTER", message: "Cannot create audio converter", details: nil))
      return
    }
    converter = audioConverter

    inputNode.installTap(
      onBus: 0,
      bufferSize: AVAudioFrameCount(nativeFormat.sampleRate * 0.2), // ~200 ms native
      format: nativeFormat
    ) { [weak self] buffer, _ in
      self?.processTap(buffer: buffer, targetFormat: targetFormat)
    }

    engine.prepare()

    // Observe engine configuration changes (e.g. audio route change, sample-rate shift).
    // When this fires we stop capture and notify the Dart side so it can reconnect.
    NotificationCenter.default.addObserver(
      forName: AVAudioEngine.configurationChangeNotification,
      object: engine,
      queue: nil
    ) { [weak self] _ in
      self?.stopCapture()
      self?.eventSink?(FlutterError(
        code: "AUDIO_CONFIG_CHANGED",
        message: "Audio engine configuration changed",
        details: nil
      ))
    }

    do {
      try engine.start()
    } catch {
      result(FlutterError(code: "ENGINE", message: error.localizedDescription, details: nil))
      return
    }

    isCapturing = true
    result(nil)
  }

  private func stopCapture() {
    guard isCapturing else { return }
    NotificationCenter.default.removeObserver(
      self,
      name: AVAudioEngine.configurationChangeNotification,
      object: engine
    )
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    converter = nil
    try? AVAudioSession.sharedInstance().setActive(false)
    isCapturing = false
  }

  private func processTap(
    buffer: AVAudioPCMBuffer,
    targetFormat: AVAudioFormat
  ) {
    // Nil-guard: if the Dart side has not subscribed (or cancelled), skip work.
    guard let sink = self.eventSink else { return }

    guard let conv = self.converter else { return }

    let targetFrames = AVAudioFrameCount(Self.sampleRate * 0.2) // 200 ms at 16 kHz
    guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrames)
    else { return }

    var error: NSError?
    var inputDone = false
    conv.convert(to: converted, error: &error) { _, outStatus in
      if inputDone {
        outStatus.pointee = .noDataNow
        return nil
      }
      inputDone = true
      outStatus.pointee = .haveData
      return buffer
    }

    guard error == nil, let floatData = converted.floatChannelData else { return }

    let frameCount = Int(converted.frameLength)
    // Convert Float32 [-1, 1] → Int16 and emit as Uint8List (little-endian).
    var int16Bytes = [UInt8](repeating: 0, count: frameCount * 2)
    for i in 0 ..< frameCount {
      let sample = max(-1.0, min(1.0, floatData[0][i]))
      let int16 = Int16(sample * 32767.0)
      int16Bytes[i * 2]     = UInt8(bitPattern: Int8(truncatingIfNeeded: int16 & 0xFF))
      int16Bytes[i * 2 + 1] = UInt8(bitPattern: Int8(truncatingIfNeeded: (int16 >> 8) & 0xFF))
    }

    // The FlutterEventChannel sink is thread-safe; call directly on the audio thread.
    let data = FlutterStandardTypedData(bytes: Data(int16Bytes))
    sink(data)
  }
}

// MARK: – FlutterStreamHandler

extension AudioCaptureChannel: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
