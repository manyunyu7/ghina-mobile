import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/services.dart';
import 'platform_providers.dart';

enum SpeechModelStatus {
  /// Asking the recognizer what's installed.
  checking,

  /// The offline `id-ID` pack is installed — dictation works offline.
  ready,

  /// Not installed (downloadable, or the recognizer only knows it online).
  missing,

  /// The device can't tell (Android < 13 / recognizer without support query).
  unknown,

  /// Download running ([SpeechModelState.progress] when Android reports it).
  downloading,

  /// Android accepted the download but runs it later (waits for Wi-Fi /
  /// charging).
  scheduled,

  /// In-app download not possible or failed → system settings.
  failed,

  /// No speech recognition service on the device at all.
  noRecognizer,
}

final class SpeechModelState {
  const SpeechModelState({
    this.status = SpeechModelStatus.checking,
    this.progress,
    this.availability,
    this.errorCode,
    this.openedScreen,
  });

  final SpeechModelStatus status;

  /// 0..1 while downloading with progress (Android 14+); null = unknown.
  final double? progress;
  final SpeechAvailability? availability;

  /// `SpeechRecognizer.ERROR_*` of a failed download.
  final int? errorCode;

  /// The settings screen opened as fallback (for the right instructions).
  final SpeechSettingsScreen? openedScreen;

  bool get isReady => status == SpeechModelStatus.ready;

  /// The online recognizer is there ("Pakai online dulu" possible).
  bool get canUseOnline => availability?.recognizerAvailable ?? false;

  SpeechModelState copyWith({
    SpeechModelStatus? status,
    double? progress,
    bool clearProgress = false,
    SpeechAvailability? availability,
    int? errorCode,
    bool clearError = false,
    SpeechSettingsScreen? openedScreen,
  }) => SpeechModelState(
    status: status ?? this.status,
    progress: clearProgress ? null : (progress ?? this.progress),
    availability: availability ?? this.availability,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    openedScreen: openedScreen ?? this.openedScreen,
  );
}

/// Offline speech pack ("paket suara Indonesia"): check, in-app download with
/// progress, scheduled / failed states, fallback to the system settings. Kept
/// alive so a download keeps reporting while the sheet is closed (the
/// settings tile shows the same state).
class SpeechModelController extends Notifier<SpeechModelState> {
  /// Android 13 reports no progress: poll the availability meanwhile.
  static const pollEvery = Duration(seconds: 5);
  static const pollFor = Duration(minutes: 3);

  late SpeechModelInstaller _installer;
  StreamSubscription<SpeechModelEvent>? _sub;
  Timer? _poll;
  int _pollsLeft = 0;
  int _check = 0;

  @override
  SpeechModelState build() {
    _installer = ref.read(speechModelInstallerProvider);
    _sub = _installer.events.listen(_onEvent);
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _poll?.cancel();
    });
    return const SpeechModelState();
  }

  void _set(SpeechModelState s) {
    if (ref.mounted) state = s;
  }

  bool get _downloading =>
      state.status == SpeechModelStatus.downloading ||
      state.status == SpeechModelStatus.scheduled;

  /// Re-checks what's installed (on open, on return from settings, polling).
  Future<void> refresh() async {
    final check = ++_check;
    if (state.availability == null) {
      _set(state.copyWith(status: SpeechModelStatus.checking));
    }
    final a = await ref
        .read(speechTranscriberProvider)
        .availability(locale: ref.read(speechLocaleProvider));
    if (!ref.mounted || check != _check) return;
    final SpeechModelStatus status;
    if (!a.recognizerAvailable) {
      status = SpeechModelStatus.noRecognizer;
    } else if (a.offlineReady) {
      status = SpeechModelStatus.ready;
    } else if (_downloading || state.status == SpeechModelStatus.failed) {
      status = state.status; // not there yet — keep showing the download
    } else if (a.offline == OfflineSpeechSupport.unknown) {
      status = SpeechModelStatus.unknown;
    } else {
      status = SpeechModelStatus.missing;
    }
    if (status == SpeechModelStatus.ready) _stopPolling();
    _set(state.copyWith(status: status, availability: a));
    if (status == SpeechModelStatus.ready) {
      ref.invalidate(speechAvailabilityProvider);
    }
  }

  /// "Unduh sekarang".
  Future<SpeechModelDownloadStart> download() async {
    _set(
      state.copyWith(
        status: SpeechModelStatus.downloading,
        clearProgress: true,
        clearError: true,
      ),
    );
    final locale = ref.read(speechLocaleProvider);
    var r = await _installer.download(locale);
    if (r == SpeechModelDownloadStart.unsupported && ref.mounted) {
      // Older native side / other platforms: the bridge's plain
      // triggerModelDownload (no progress) is still worth a try.
      final ok = await ref
          .read(speechTranscriberProvider)
          .requestOfflineModel(locale: locale);
      if (ok) r = SpeechModelDownloadStart.triggered;
    }
    if (!ref.mounted) return r;
    switch (r) {
      case SpeechModelDownloadStart.progress:
        break; // events follow
      case SpeechModelDownloadStart.triggered:
        _startPolling();
      case SpeechModelDownloadStart.unsupported:
        if (state.status == SpeechModelStatus.downloading) {
          _set(state.copyWith(status: SpeechModelStatus.failed));
        }
    }
    return r;
  }

  /// Fallback: the system screen for offline speech packs.
  Future<SpeechSettingsScreen?> openSettings() async {
    final s = await _installer.openSettings();
    if (s != null) _set(state.copyWith(openedScreen: s));
    return s;
  }

  void _onEvent(SpeechModelEvent e) {
    switch (e.kind) {
      case SpeechModelEventKind.progress:
        _set(
          state.copyWith(
            status: SpeechModelStatus.downloading,
            progress: (e.percent ?? 0) / 100,
          ),
        );
      case SpeechModelEventKind.triggered:
        _set(
          state.copyWith(
            status: SpeechModelStatus.downloading,
            clearProgress: true,
          ),
        );
        _startPolling();
      case SpeechModelEventKind.scheduled:
        _set(state.copyWith(status: SpeechModelStatus.scheduled));
        _startPolling();
      case SpeechModelEventKind.success:
        _stopPolling();
        _set(state.copyWith(status: SpeechModelStatus.ready, progress: 1));
        ref.invalidate(speechAvailabilityProvider);
        unawaited(refresh());
      case SpeechModelEventKind.error:
        _stopPolling();
        _set(
          state.copyWith(
            status: SpeechModelStatus.failed,
            errorCode: e.errorCode,
            clearProgress: true,
          ),
        );
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _pollsLeft = pollFor.inSeconds ~/ pollEvery.inSeconds;
    _poll = Timer.periodic(pollEvery, (_) {
      if (--_pollsLeft <= 0) {
        _stopPolling();
        // Still not there: Android finishes it in the background.
        if (state.status == SpeechModelStatus.downloading) {
          _set(state.copyWith(status: SpeechModelStatus.scheduled));
        }
      }
      unawaited(refresh());
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }
}

final speechModelControllerProvider =
    NotifierProvider<SpeechModelController, SpeechModelState>(
      SpeechModelController.new,
    );
