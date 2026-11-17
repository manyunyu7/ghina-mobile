/// Device services for notes (voice, dictation, share target) as overridable
/// providers. Production implementations on Android/iOS, no-ops elsewhere and
/// under `flutter test` — tests override with the fakes from
/// `lib/data/platform/fakes.dart`:
///
/// ```dart
/// ProviderContainer(overrides: [
///   voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
///   microphonePermissionProvider.overrideWithValue(FakeMicrophonePermission()),
/// ]);
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/diagnostics/dictation_log.dart';
import '../../../data/platform/platform.dart';
import '../../../domain/services/services.dart';

final microphonePermissionProvider = Provider<MicrophonePermission>(
  (ref) => createMicrophonePermission(),
);

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final r = createVoiceRecorder();
  ref.onDispose(r.dispose);
  return r;
});

final audioPlaybackProvider = Provider<AudioPlayback>((ref) {
  final p = createAudioPlayback();
  ref.onDispose(p.dispose);
  return p;
});

final speechTranscriberProvider = Provider<SpeechTranscriber>((ref) {
  final t = createSpeechTranscriber();
  ref.onDispose(t.dispose);
  return t;
});

/// Mutes the recognizer beeps while dictation runs.
final dictationAudioProvider = Provider<DictationAudio>(
  (ref) => createDictationAudio(),
);

/// In-app download of the offline `id-ID` speech pack.
final speechModelInstallerProvider = Provider<SpeechModelInstaller>(
  (ref) => createSpeechModelInstaller(),
);

/// Dictation session events for Diagnostik (persisted on devices only, so
/// tests never touch the disk or leave a save timer behind).
final dictationLogProvider = Provider<DictationLog>(
  (ref) => isMobileDevice ? DictationLog.instance : DictationLog.memory(),
);

final shareIntakeProvider = Provider<ShareIntake>((ref) {
  final s = createShareIntake();
  ref.onDispose(s.dispose);
  return s;
});

/// Launcher shortcuts (long-press the app icon). See
/// `features/shell/app_shortcut_listener.dart`.
final appShortcutsProvider = Provider<AppShortcuts>((ref) {
  final s = createAppShortcuts();
  ref.onDispose(s.dispose);
  return s;
});

// --- policy -------------------------------------------------------------------

/// Max length of one voice clip (spec: 10 min). Tests override it.
final maxVoiceDurationProvider = Provider<Duration>(
  (ref) => kMaxVoiceNoteDuration,
);

/// Dictation language.
final speechLocaleProvider = Provider<String>((ref) => kDefaultSpeechLocale);

/// Whether dictation may use the recognizer's network mode when no offline
/// `id-ID` model is known to be installed. Spec: no cloud transcription by
/// default → false, until the user picks "Pakai online dulu" in the speech
/// pack sheet ([dictationOnlineOptInProvider], this app run only).
/// ([OfflineSpeechSupport.unknown] is still allowed, best effort.)
final dictationAllowsNetworkProvider = Provider<bool>(
  (ref) => ref.watch(dictationOnlineOptInProvider),
);

/// "Pakai online dulu": the user accepted the online recognizer while the
/// offline pack is missing. Not persisted — next app start asks again.
final dictationOnlineOptInProvider =
    NotifierProvider<DictationOnlineOptIn, bool>(DictationOnlineOptIn.new);

class DictationOnlineOptIn extends Notifier<bool> {
  @override
  bool build() => false;

  void allow() => state = true;
}

/// Offline speech readiness for [speechLocaleProvider] — drives the "Dikte"
/// button state and the hint text. `ref.invalidate` it after the user comes
/// back from downloading a language pack.
final speechAvailabilityProvider =
    FutureProvider.autoDispose<SpeechAvailability>(
      (ref) => ref
          .watch(speechTranscriberProvider)
          .availability(locale: ref.watch(speechLocaleProvider)),
    );
