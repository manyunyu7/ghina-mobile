import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/services/dictation_audio.dart';
import '../../domain/services/speech_model_installer.dart';

/// [DictationAudio] over the `app/dictation_audio` channel (MainActivity.kt):
/// `mute` / `unmute`, both → `bool`. The native side remembers which streams
/// it muted (also across a crash) and restores only those.
final class ChannelDictationAudio implements DictationAudio {
  ChannelDictationAudio({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'app/dictation_audio';

  final MethodChannel _channel;

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<Object?>(method);
    } on MissingPluginException {
      // iOS / older build without the channel: nothing to silence.
    } on PlatformException {
      // A stream we may not touch (Do Not Disturb policy) — beeps stay.
    }
  }

  @override
  Future<void> mute() => _call('mute');

  @override
  Future<void> unmute() => _call('unmute');
}

/// [SpeechModelInstaller] over the `app/speech_model` channel (MainActivity.kt).
///
/// Dart → native: `download {locale}` → `'progress' | 'triggered' |
/// 'unsupported'`; `openSettings` → `'google_offline' | 'voice_input' |
/// 'language' | 'settings' | null`.
/// Native → Dart: `progress {percent}`, `success`, `scheduled`,
/// `error {code}`, `triggered` (no progress available → poll).
final class ChannelSpeechModelInstaller implements SpeechModelInstaller {
  ChannelSpeechModelInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onNative);
  }

  static const channelName = 'app/speech_model';

  final MethodChannel _channel;
  final _events = StreamController<SpeechModelEvent>.broadcast();

  Future<Object?> _onNative(MethodCall call) async {
    final args = call.arguments;
    int? arg(String key) =>
        args is Map && args[key] is num ? (args[key] as num).toInt() : null;
    final event = switch (call.method) {
      'progress' => SpeechModelEvent(
        SpeechModelEventKind.progress,
        percent: (arg('percent') ?? 0).clamp(0, 100),
      ),
      'success' => const SpeechModelEvent(SpeechModelEventKind.success),
      'scheduled' => const SpeechModelEvent(SpeechModelEventKind.scheduled),
      'triggered' => const SpeechModelEvent(SpeechModelEventKind.triggered),
      'error' => SpeechModelEvent(
        SpeechModelEventKind.error,
        errorCode: arg('code'),
      ),
      _ => null,
    };
    if (event != null && !_events.isClosed) _events.add(event);
    return null;
  }

  @override
  Stream<SpeechModelEvent> get events => _events.stream;

  @override
  Future<SpeechModelDownloadStart> download(String locale) async {
    try {
      final r = await _channel.invokeMethod<String>('download', {
        'locale': locale,
      });
      return switch (r) {
        'progress' => SpeechModelDownloadStart.progress,
        'triggered' => SpeechModelDownloadStart.triggered,
        _ => SpeechModelDownloadStart.unsupported,
      };
    } on MissingPluginException {
      return SpeechModelDownloadStart.unsupported;
    } on PlatformException {
      return SpeechModelDownloadStart.unsupported;
    }
  }

  @override
  Future<SpeechSettingsScreen?> openSettings() async {
    try {
      final r = await _channel.invokeMethod<String>('openSettings');
      return switch (r) {
        'google_offline' => SpeechSettingsScreen.googleOffline,
        'voice_input' => SpeechSettingsScreen.voiceInput,
        'language' => SpeechSettingsScreen.language,
        'settings' => SpeechSettingsScreen.settings,
        _ => null,
      };
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
