/// Downloads the offline speech-recognition model ("paket suara") for a
/// locale from inside the app — Android 13+ `triggerModelDownload`, with
/// progress on Android 14+ — and opens the right system screen when that is
/// not possible.
library;

/// How [SpeechModelInstaller.download] went.
enum SpeechModelDownloadStart {
  /// Download requested; progress arrives on [SpeechModelInstaller.events]
  /// (Android 14+).
  progress,

  /// Download requested, but Android reports no progress (Android 13): poll
  /// the availability until the model shows up.
  triggered,

  /// Not possible from the app (Android < 13, no on-device recognizer, the
  /// request failed) — send the user to the system settings.
  unsupported,
}

enum SpeechModelEventKind {
  progress,
  success,
  scheduled,
  error,

  /// Requested, but the service can't report progress → poll.
  triggered,
}

final class SpeechModelEvent {
  const SpeechModelEvent(this.kind, {this.percent, this.errorCode});

  final SpeechModelEventKind kind;

  /// 0..100 for [SpeechModelEventKind.progress].
  final int? percent;

  /// `SpeechRecognizer.ERROR_*` for [SpeechModelEventKind.error].
  final int? errorCode;

  @override
  String toString() => 'SpeechModelEvent($kind, $percent, $errorCode)';
}

/// Which system screen [SpeechModelInstaller.openSettings] opened.
enum SpeechSettingsScreen {
  /// Google app › offline speech recognition (language packs).
  googleOffline,

  /// Android › voice input / on-device recognition.
  voiceInput,

  /// Android › languages.
  language,

  /// Android settings home.
  settings,
}

abstract interface class SpeechModelInstaller {
  Future<SpeechModelDownloadStart> download(String locale);

  /// Download progress / outcome (broadcast).
  Stream<SpeechModelEvent> get events;

  /// Opens the most specific system screen for offline speech packs; null
  /// when none could be opened.
  Future<SpeechSettingsScreen?> openSettings();
}
