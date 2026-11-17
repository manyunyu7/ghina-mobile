package com.henryaugusta.ghina

import android.content.Context
import android.media.AudioManager
import android.os.Build

/**
 * Silences the speech recognizer's start/stop beeps while dictation runs
 * (channel "app/dictation_audio", lib/data/platform/dictation_channels.dart).
 *
 * Continuous dictation restarts a SpeechRecognizer session every few seconds and
 * Google's / Samsung's recognizer plays an earcon at every start and end. Which
 * stream carries it differs per recognizer version: Samsung plays it on the
 * notification / system streams, the Google app on newer versions on the media
 * stream. Ring and alarm streams are never touched (calls and alarms stay audible).
 *
 * Only streams that were audible are muted, and exactly those are restored: a
 * stream the user had muted stays muted. The set of streams we muted is written to
 * SharedPreferences with commit(), so a crash or a killed process mid-dictation is
 * repaired at the next start (MainActivity calls [unmute] when the engine is
 * configured) as well as on onStop / onDestroy.
 */
object DictationAudioMuter {
    private const val PREFS = "dictation_audio"
    private const val KEY_MUTED = "muted_streams"

    private val STREAMS = intArrayOf(
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_SYSTEM,
        AudioManager.STREAM_MUSIC,
    )

    /** Mutes the beep streams; true when at least one stream is muted by us. */
    fun mute(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val muted = HashSet(prefs.getStringSet(KEY_MUTED, null) ?: emptySet())
        for (stream in STREAMS) {
            val key = stream.toString()
            if (muted.contains(key)) continue
            // Already silent (muted by the user, vibrate mode): leave it alone and
            // never "restore" it later.
            val silent = runCatching { am.isStreamMute(stream) }.getOrDefault(true)
            if (silent) continue
            val ok = runCatching {
                am.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, 0)
                true
            }.getOrDefault(false) // Do Not Disturb policy may refuse it
            if (ok) muted.add(key)
        }
        prefs.edit().putStringSet(KEY_MUTED, muted).commit()
        return muted.isNotEmpty()
    }

    /** Restores the streams [mute] silenced (no-op when nothing is recorded). */
    fun unmute(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val muted = prefs.getStringSet(KEY_MUTED, null)
        if (muted.isNullOrEmpty()) return false
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (am != null) {
            for (key in muted) {
                val stream = key.toIntOrNull() ?: continue
                runCatching { am.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0) }
            }
        }
        prefs.edit().remove(KEY_MUTED).commit()
        return true
    }
}
