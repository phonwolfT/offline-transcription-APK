package com.example.frontend_flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.meetily/internal_audio"
    private val EVENT_CHANNEL = "com.example.meetily/internal_audio_stream"
    private val REQUEST_MEDIA_PROJECTION = 1001

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    
    private var isRecording = false
    private var eventSink: EventChannel.EventSink? = null
    private var recordingThread: Thread? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopInternalRecording()
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startInternalRecording" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startInternalRecordingActivity()
                        result.success(true)
                    } else {
                        result.error("UNSUPPORTED_VERSION", "AudioPlaybackCapture requires Android 10 (API 29) or higher.", null)
                    }
                }
                "stopInternalRecording" -> {
                    stopInternalRecording()
                    result.success(true)
                }
                "isInternalCaptureSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startInternalRecordingActivity() {
        val intent = Intent(this, InternalAudioCaptureService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        startActivityForResult(mediaProjectionManager?.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == RESULT_OK && data != null) {
                mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)
                startAudioCapture()
            } else {
                eventSink?.error("PERMISSION_DENIED", "Media Projection Permission Denied", null)
                stopInternalRecording()
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun startAudioCapture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || mediaProjection == null) return
        
        val config = AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(16000)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()

        val bufferSize = AudioRecord.getMinBufferSize(
            16000,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioRecord = AudioRecord.Builder()
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize)
            .setAudioPlaybackCaptureConfig(config)
            .build()

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            eventSink?.error("INIT_FAILED", "Failed to initialize AudioRecord", null)
            return
        }

        audioRecord?.startRecording()
        isRecording = true

        recordingThread = thread(start = true) {
            val buffer = ByteArray(bufferSize)
            while (isRecording) {
                val readSize = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (readSize > 0) {
                    val readData = buffer.copyOf(readSize)
                    runOnUiThread {
                        eventSink?.success(readData)
                    }
                }
            }
        }
    }

    private fun stopInternalRecording() {
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        mediaProjection?.stop()
        mediaProjection = null
        
        val intent = Intent(this, InternalAudioCaptureService::class.java)
        stopService(intent)
    }
}
