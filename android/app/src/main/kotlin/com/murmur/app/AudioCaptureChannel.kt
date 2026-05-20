package com.murmur.app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class AudioCaptureChannel(private val context: Context) {

    companion object {
        const val METHOD_CHANNEL = "com.murmur.audio/capture"
        const val EVENT_CHANNEL = "com.murmur.audio/pcm_stream"

        // Written by EventChannel.StreamHandler.onListen, read by MurmurForegroundService.
        // Both accesses happen on the main thread (EventChannel guarantees this for the
        // StreamHandler callbacks; MurmurForegroundService posts to main before reading).
        @Volatile
        var pcmEventSink: EventChannel.EventSink? = null
    }

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    MurmurForegroundService.start(context)
                    result.success("ok")
                }
                "stop" -> {
                    MurmurForegroundService.stop(context)
                    result.success("ok")
                }
                "status" -> {
                    val status = if (MurmurForegroundService.isRunning) "recording" else "idle"
                    result.success(status)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                // Must be subscribed before calling start() so no PCM frames are lost.
                pcmEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                // Only clear the reference; the MethodChannel stop() call is the
                // authoritative trigger for stopping AudioRecord and the service.
                pcmEventSink = null
            }
        })
    }
}
