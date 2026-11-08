package com.controlpc.app.controlpc

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var grabando = false
    private var audioRecord: AudioRecord? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // PCM16 del micrófono llega a Dart por este canal de eventos
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "controlpc/micro"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        // métodos iniciar / parar
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "controlpc/micro_ctrl"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "iniciar" -> {
                    try {
                        iniciar()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("mic", e.message, null)
                    }
                }
                "parar" -> {
                    try {
                        parar()
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // graba PCM16 (mono, 48 kHz) y manda trozos a Dart por el eventSink
    private fun iniciar() {
        if (grabando) return
        val sr = 48000
        val minimo = AudioRecord.getMinBufferSize(
            sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val grabadora = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sr,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minimo, 16384)
        )
        try {
            grabadora.startRecording()
        } catch (e: Exception) {
            try {
                grabadora.release()
            } catch (_: Exception) {
            }
            throw e
        }
        audioRecord = grabadora
        grabando = true
        val buffer = ByteArray(4096)
        Thread {
            while (grabando) {
                val leidos = try {
                    grabadora.read(buffer, 0, buffer.size)
                } catch (_: Exception) {
                    -1
                }
                if (leidos > 0) {
                    val paquete = buffer.copyOf(leidos)
                    mainHandler.post {
                        try {
                            eventSink?.success(paquete)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        }.start()
    }

    private fun parar() {
        if (!grabando) return
        grabando = false
        val grabadora = audioRecord ?: return
        audioRecord = null
        try {
            grabadora.stop()
        } catch (_: Exception) {
        }
        try {
            grabadora.release()
        } catch (_: Exception) {
        }
    }
}
