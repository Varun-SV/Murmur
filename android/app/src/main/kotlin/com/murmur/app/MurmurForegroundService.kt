package com.murmur.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class MurmurForegroundService : Service() {

    companion object {
        private const val TAG = "MurmurForegroundService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "murmur_mic_channel"
        private const val SAMPLE_RATE = 16000
        // 200ms chunks: 16000 samples/s × 0.2s × 2 bytes = 6400 bytes
        private const val CHUNK_SIZE_BYTES = 6400

        @Volatile
        var isRunning = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, MurmurForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MurmurForegroundService::class.java))
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null

    @Volatile
    private var isCapturing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()

        // startForeground must be called within 5 seconds on Android 12+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }

        if (!isCapturing) {
            startCapture()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopCapture()
        isRunning = false
        super.onDestroy()
    }

    private fun startCapture() {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(CHUNK_SIZE_BYTES)

        val record = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuf,
        )

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord failed to initialize")
            mainHandler.post {
                AudioCaptureChannel.pcmEventSink?.error(
                    "AUDIO_INIT_ERROR", "AudioRecord failed to initialize", null,
                )
            }
            stopSelf()
            return
        }

        audioRecord = record
        isCapturing = true
        isRunning = true
        record.startRecording()

        recordingThread = Thread({
            val buf = ByteArray(CHUNK_SIZE_BYTES)
            while (isCapturing) {
                val bytesRead = record.read(buf, 0, buf.size)
                if (bytesRead > 0) {
                    val chunk = buf.copyOf(bytesRead)
                    mainHandler.post {
                        // Null-safe: sink may have been cleared by onCancel.
                        AudioCaptureChannel.pcmEventSink?.success(chunk)
                    }
                } else if (bytesRead < 0) {
                    Log.e(TAG, "AudioRecord.read error: $bytesRead")
                    mainHandler.post {
                        AudioCaptureChannel.pcmEventSink?.error(
                            "AUDIO_READ_ERROR", "AudioRecord.read returned $bytesRead", null,
                        )
                    }
                    break
                }
            }
            Log.d(TAG, "Recording thread exiting")
        }, "murmur-audio-capture")

        recordingThread!!.start()
        Log.i(TAG, "Audio capture started at ${SAMPLE_RATE}Hz mono int16")
    }

    private fun stopCapture() {
        isCapturing = false
        audioRecord?.stop()
        recordingThread?.join(1000)
        audioRecord?.release()
        audioRecord = null
        recordingThread = null
        Log.i(TAG, "Audio capture stopped")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Murmur Listening",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while Murmur is actively capturing audio"
                setShowBadge(false)
            }
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Murmur")
            .setContentText("Listening for reminders…")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .build()
    }
}
