/// Quiets the recognizer's start/stop beeps while dictation runs.
///
/// Android's `SpeechRecognizer` (Google / Samsung) plays an earcon at every
/// session start and end. Continuous dictation restarts sessions all the
/// time, so without this the phone beeps every few seconds. [mute] silences
/// the streams those earcons use; [unmute] restores only the streams that
/// [mute] silenced (a stream the user had muted stays muted). Both are
/// idempotent and never throw.
abstract interface class DictationAudio {
  Future<void> mute();
  Future<void> unmute();
}
