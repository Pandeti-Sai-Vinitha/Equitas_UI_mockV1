package com.example.mock2

import android.media.AudioManager
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val soundChannel = "com.example.mock2/transaction_sound"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            soundChannel,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "playSuccess" -> {
                        playDefaultSound(
                            RingtoneManager.TYPE_NOTIFICATION,
                            ToneGenerator.TONE_PROP_ACK,
                        )
                        result.success(null)
                    }
                    "playCardLock" -> {
                        playCardUnlockSound()
                        result.success(null)
                    }
                    "playCardUnlock" -> {
                        playCardUnlockSound()
                        result.success(null)
                    }
                    "playCardLimit" -> {
                        playCardLimitSound()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: RuntimeException) {
                result.error("SOUND_UNAVAILABLE", error.message, null)
            }
        }
    }

    private fun playDefaultSound(type: Int, fallbackTone: Int) {
        val notificationUri =
            RingtoneManager.getDefaultUri(type)
        val notification = notificationUri?.let {
            RingtoneManager.getRingtone(this, it)
        }
        if (notification != null) {
            notification.play()
            Handler(Looper.getMainLooper()).postDelayed(
                { notification.stop() },
                1_500,
            )
            return
        }

        val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 85)
        try {
            check(tone.startTone(fallbackTone, 220)) {
                "Android could not start the transaction success tone."
            }
            Handler(Looper.getMainLooper()).postDelayed(
                { tone.release() },
                280,
            )
        } catch (error: RuntimeException) {
            tone.release()
            throw error
        }
    }

    private fun playCardUnlockSound() {
        val sampleRate = 44_100
        val pcm = createCardSound(
            sampleRate,
            listOf(SoundSweep(1_100.0, 1_580.0, 145, 0.3)),
        )
        val track = AudioTrack(
            AudioManager.STREAM_MUSIC,
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            pcm.size * 2,
            AudioTrack.MODE_STATIC,
        )
        try {
            check(track.write(pcm, 0, pcm.size) == pcm.size) {
                "Android could not load the card action sound."
            }
            track.setVolume(0.45f)
            track.play()
            Handler(Looper.getMainLooper()).postDelayed(
                { track.release() },
                pcm.size * 1_000L / sampleRate + 100L,
            )
        } catch (error: RuntimeException) {
            track.release()
            throw error
        }
    }

    private data class SoundSweep(
        val startFrequency: Double,
        val endFrequency: Double,
        val durationMs: Int,
        val volume: Double,
    )

    private fun createCardSound(sampleRate: Int, sweeps: List<SoundSweep>): ShortArray {
        val samples = ArrayList<Short>()
        var phase = 0.0
        for ((sweepIndex, sweep) in sweeps.withIndex()) {
            val count = sampleRate * sweep.durationMs / 1_000
            for (index in 0 until count) {
                val progress = index.toDouble() / count
                val frequency =
                    sweep.startFrequency +
                        (sweep.endFrequency - sweep.startFrequency) * progress
                phase += 2.0 * Math.PI * frequency / sampleRate
                val attack = (progress / 0.12).coerceIn(0.0, 1.0)
                val decay = ((1.0 - progress) / 0.58).coerceIn(0.0, 1.0)
                val envelope = minOf(attack, decay)
                val fundamental = kotlin.math.sin(phase)
                val sample =
                    fundamental *
                        envelope *
                        sweep.volume *
                        Short.MAX_VALUE
                samples.add(sample.toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort())
            }
            if (sweepIndex < sweeps.lastIndex) {
                repeat(sampleRate * 18 / 1_000) { samples.add(0) }
            }
        }
        return ShortArray(samples.size) { samples[it] }
    }

    private fun playCardLimitSound() {
        val generator = ToneGenerator(AudioManager.STREAM_MUSIC, 85)
        try {
            check(generator.startTone(ToneGenerator.TONE_PROP_ACK, 180)) {
                "Android could not start the card limit sound."
            }
            Handler(Looper.getMainLooper()).postDelayed(
                { generator.release() },
                220,
            )
        } catch (error: RuntimeException) {
            generator.release()
            throw error
        }
    }
}
