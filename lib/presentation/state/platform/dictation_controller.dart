import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/diagnostics/dictation_log.dart';
import '../../../domain/services/services.dart';
import 'platform_providers.dart';
import 'voice_recorder_controller.dart';

enum DictationPhase {
  idle,

  /// Checking availability / permission, opening the recognizer.
  starting,
  listening,

  /// Between two recognizer sessions (Android ends one after ~silence; we
  /// start the next one right away, or after a short backoff on an error).
  restarting,

  /// User pressed stop; waiting for the final result.
  stopping,

  /// Dictation not possible here — show [DictationState.hint].
  unavailable,

  /// Failed — see [DictationState.error].
  error,
}

final class DictationState {
  const DictationState({
    this.phase = DictationPhase.idle,
    this.committed = '',
    this.partial = '',
    this.level = 0,
    this.availability,
    this.error,
    this.permission,
    this.elapsed = Duration.zero,
    this.stopIn,
  });

  final DictationPhase phase;

  /// Finalised text of all sessions so far.
  final String committed;

  /// Live (not yet final) text of the current utterance — show it greyed.
  final String partial;

  /// Mic level 0..1.
  final double level;

  final SpeechAvailability? availability;
  final SpeechError? error;
  final MicPermissionStatus? permission;

  /// How long this dictation has been running (ticks every second).
  final Duration elapsed;

  /// Seconds until dictation stops by itself after a long silence ("Masih
  /// mendengarkan?"); null = no warning. Speaking or
  /// [DictationController.keepListening] clears it.
  final int? stopIn;

  /// Everything recognised so far (committed + live partial).
  String get text => joinTranscript(committed, partial);

  bool get isActive =>
      phase == DictationPhase.starting ||
      phase == DictationPhase.listening ||
      phase == DictationPhase.restarting ||
      phase == DictationPhase.stopping;

  /// Indonesian hint for [DictationPhase.unavailable] (offline pack missing…).
  String? get hint => availability?.hint;

  DictationState copyWith({
    DictationPhase? phase,
    String? committed,
    String? partial,
    double? level,
    SpeechAvailability? availability,
    SpeechError? error,
    bool clearError = false,
    MicPermissionStatus? permission,
    Duration? elapsed,
    int? stopIn,
    bool clearStopIn = false,
  }) => DictationState(
    phase: phase ?? this.phase,
    committed: committed ?? this.committed,
    partial: partial ?? this.partial,
    level: level ?? this.level,
    availability: availability ?? this.availability,
    error: clearError ? null : (error ?? this.error),
    permission: permission ?? this.permission,
    elapsed: elapsed ?? this.elapsed,
    stopIn: clearStopIn ? null : (stopIn ?? this.stopIn),
  );
}

/// Joins transcript pieces with a single space (no leading/trailing spaces).
String joinTranscript(String a, String b) {
  final x = a.trim(), y = b.trim();
  if (x.isEmpty) return y;
  if (y.isEmpty) return x;
  return '$x $y';
}

/// `mm:ss` (or `h:mm:ss`) for the dictation timer.
String formatDictationElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

int _wordCount(String s) {
  final t = s.trim();
  return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
}

List<String> _words(String s) =>
    s.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// What a late final (arriving after its session was already closed with the
/// live partial committed) adds to the transcript: nothing when it's the same
/// words (or a slight variant), only the extra words when it extends them,
/// all of it when it's unrelated. Keeps the committed text append-only.
String lateFinalExtra(String committedTail, String finalText) {
  final tail = _words(committedTail), fin = _words(finalText);
  if (fin.isEmpty) return '';
  if (tail.isEmpty) return finalText.trim();
  var i = 0;
  while (i < tail.length && i < fin.length && tail[i] == fin[i]) {
    i++;
  }
  if (i == tail.length) {
    // The final repeats the tail and goes on: keep only what's new.
    return finalText.trim().split(RegExp(r'\s+')).skip(i).join(' ');
  }
  final shared = fin.toSet().intersection(tail.toSet()).length;
  if (shared * 2 >= math.min(tail.length, fin.length)) return ''; // variant
  return finalText.trim();
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Lowercased words without punctuation (for comparing transcripts).
List<String> _norm(String s) => [
  for (final w in s.toLowerCase().split(RegExp(r'\s+')))
    if (w.replaceAll(_nonWord, '').isNotEmpty) w.replaceAll(_nonWord, ''),
];

bool _sameWord(String a, String b) =>
    a == b ||
    (a.length >= 2 && b.length >= 2 && (a.startsWith(b) || b.startsWith(a)));

/// Whether the partial [next] is a revision / extension of the partial
/// [prev] of the same recognizer session (cumulative partials), rather than
/// the start of a new segment (on-device recognizers of Google / Samsung
/// start the partials over after a segment of a long utterance).
bool transcriptContinues(String prev, String next) {
  final p = _norm(prev), n = _norm(next);
  if (p.isEmpty || n.isEmpty) return true;
  // Character level, so "di sana" → "disana" / "kepasar" → "ke pasar" count.
  final pj = p.join(), nj = n.join();
  var cp = 0;
  while (cp < pj.length && cp < nj.length && pj[cp] == nj[cp]) {
    cp++;
  }
  if (cp > 0 && cp * 2 >= pj.length) return true;
  // The first words were revised ("saya mau ke pasar" → "Aku mau ke pasar").
  if (n.length >= p.length) {
    final rest = [...n];
    var shared = 0;
    for (final w in p) {
      if (rest.remove(w)) shared++;
    }
    if (shared >= (p.length * 0.6).ceil()) return true;
  }
  return false;
}

/// The part of [next] that [covered] doesn't hold yet: drops the words at
/// the start of [next] that repeat the end of [covered] (a cumulative result
/// that still includes words committed before, or only overlaps their end).
/// All of [next] when it's a fresh segment. Never touches [covered].
String transcriptTail(String covered, String next) {
  final raw = next.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final rawWords = raw.toList();
  final c = _norm(covered);
  if (c.isEmpty || rawWords.isEmpty) return next.trim();
  // Keep raw and normalised words aligned (punctuation-only words drop out).
  final keep = [
    for (var i = 0; i < rawWords.length; i++)
      if (rawWords[i].replaceAll(_nonWord, '').isNotEmpty) i,
  ];
  final n = [
    for (final i in keep) rawWords[i].toLowerCase().replaceAll(_nonWord, ''),
  ];
  String after(int k) => k >= n.length ? '' : rawWords.skip(keep[k]).join(' ');
  if (n.isEmpty) return next.trim();

  // 1. Exact overlap: the end of covered == the start of next (≥ 2 words, or
  //    all of covered — one shared word alone may be a coincidence).
  for (var k = math.min(c.length, n.length); k >= 1; k--) {
    if (k < 2 && k != c.length) break;
    var ok = true;
    for (var i = 0; i < k; i++) {
      if (c[c.length - k + i] != n[i]) {
        ok = false;
        break;
      }
    }
    if (ok) return after(k);
  }
  // 2. next spells covered out with other word breaks ("kepasar" → "ke
  //    pasar") or a longer last word, then goes on.
  final cj = c.join();
  var seen = '';
  for (var k = 0; k < n.length; k++) {
    seen += n[k];
    if (seen.length >= cj.length) {
      if (seen.startsWith(cj)) return after(k + 1);
      break;
    }
  }
  // 3. Cumulative with a revision in the middle: same start, and covered's
  //    last words show up again further on → keep what follows them.
  if (_sameWord(c.first, n.first)) {
    final tail = c.length >= 2 ? c.sublist(c.length - 2) : c;
    for (var j = n.length - tail.length; j >= 1; j--) {
      var ok = true;
      for (var i = 0; i < tail.length; i++) {
        if (n[j + i] != tail[i]) {
          ok = false;
          break;
        }
      }
      if (ok) return after(j + tail.length);
    }
  }
  return next.trim();
}

/// Continuous dictation ("Dikte"): live speech-to-text into a text field.
///
/// * Partial results replace [DictationState.partial]; a final result is
///   appended to [DictationState.committed]. Committed text is append-only
///   (the UI inserts its growth into the field); only the live partial at
///   the end moves. Partials are usually cumulative per recognizer session,
///   but on-device recognizers (Google / Samsung) split a long utterance into
///   segments and start the partials over after each one, and their final
///   may hold only the last segment: a partial that doesn't continue the
///   previous one ([transcriptContinues]) or is marked as a segment end
///   commits the live text first, and a final only adds what the session
///   hasn't committed yet ([transcriptTail]). Results of a session that was
///   closed for a restart ([TranscriptUpdate.stale]) never replace anything.
/// * Android ends a session after a few seconds of silence. While the user
///   hasn't pressed stop a new session starts right away ([restartDelay]):
///   as soon as the final result is in, without waiting for the plugin's own
///   end-of-session timer. Words of a session that ended without a final are
///   committed from the last partial; a final that still shows up later is
///   de-duplicated ([lateFinalExtra]).
/// * Dictation runs until stop — silence alone never ends it. Only after
///   [silenceTimeout] without any voice or words a warning shows
///   ([DictationState.stopIn]) and [silenceGrace] later it stops.
/// * Light errors (busy, client, server, network, audio…) restart with a
///   backoff ([retryBackoff]); only permission / language / no recognizer, or
///   too many errors in a row, end it with an error.
/// * Mutes the recognizer beeps while active ([DictationAudio]), always
///   restored on stop, error, app background and dispose.
/// * Session events go to [DictationLog] (Diagnostik › Log dikte).
/// * Starting dictation cancels a running voice recording (one mic owner).
///
/// ```dart
/// final d = ref.watch(dictationControllerProvider);
/// await ref.read(dictationControllerProvider.notifier).start();
/// final text = await ref.read(dictationControllerProvider.notifier).stop();
/// insertIntoBody(text);   // then .clear()
/// ```
class DictationController extends Notifier<DictationState> {
  /// Pause between the end of one recognizer session and the next.
  static const restartDelay = Duration(milliseconds: 30);

  /// Waits before restarting after consecutive light errors.
  static const retryBackoff = [
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
  ];

  /// Consecutive light errors (without any words in between) before giving up.
  static int get maxRetries => retryBackoff.length;

  /// How long to wait for the final result after stop.
  static const finalizeTimeout = Duration(seconds: 2);

  /// A started session that never reports `listening` counts as busy.
  static const startTimeout = Duration(seconds: 3);

  /// No voice / words this long → "Masih mendengarkan?" warning…
  static const silenceTimeout = Duration(minutes: 2);

  /// …and this much later dictation stops.
  static const silenceGrace = Duration(seconds: 10);

  /// Mic level (0..1) that counts as voice for the silence guard.
  static const voiceLevel = 0.6;

  late SpeechTranscriber _t;
  late DictationAudio _audio;
  late DictationLog _logSink;

  /// Last state set (readable in onDispose, where `state` isn't).
  DictationState _last = const DictationState();
  final _subs = <StreamSubscription<Object?>>[];
  bool _want = false;

  /// A recognizer session is running (started and not ended yet).
  bool _sessionOpen = false;

  /// The running session reported `listening` (statuses before that are
  /// leftovers of the previous session).
  bool _live = false;
  bool _sessionHasPartial = false;
  int _session = 0;

  /// Everything this session recognised so far (committed segments + live).
  String _sessionText = '';
  DateTime _sessionStartedAt = DateTime.now();

  /// Segments of the running session already moved into committed (the
  /// recognizer started its partials over after them).
  String _sessionCommitted = '';

  /// Last raw partial of the running session (to spot a segment restart).
  String _lastRaw = '';

  /// Words in committed when the running session started (log).
  int _wordsAtSession = 0;

  /// Text of the last session that recognised something — late results of
  /// it are de-duplicated against this.
  String _prevSessionText = '';

  /// Whole text of a session that ended without a final (committed from its
  /// partials); a final that still arrives is de-duplicated against it.
  String _autoTail = '';
  String _lastFinal = '';
  int _errorStreak = 0;

  int _quietSeconds = 0;
  int _elapsedSeconds = 0;
  int _sessions = 0;
  int _retries = 0;
  int _wordsAtStart = 0;
  String _endReason = 'stop';

  bool _muted = false;
  AppLifecycleListener? _lifecycle;

  Timer? _restartTimer;
  Timer? _finalizeTimer;
  Timer? _startWatchdog;
  Timer? _ticker;
  Completer<String>? _stopCompleter;

  @override
  DictationState build() {
    final t = _t = ref.read(speechTranscriberProvider);
    _audio = ref.read(dictationAudioProvider);
    _logSink = ref.read(dictationLogProvider);
    ref.onDispose(() {
      final wasActive = _want || _sessionOpen;
      _want = false;
      _sessionOpen = false;
      _cancelTimers();
      for (final s in _subs) {
        unawaited(s.cancel());
      }
      _subs.clear();
      _lifecycle?.dispose();
      _lifecycle = null;
      _setMuted(false);
      if (wasActive) _logSummary('tutup');
      if (t.isListening) unawaited(t.cancel());
    });
    return const DictationState();
  }

  void _set(DictationState s) {
    if (!ref.mounted) return;
    state = _last = s;
  }

  void _subscribe() {
    if (_subs.isNotEmpty) return;
    _subs
      ..add(_t.results.listen(_onResult))
      ..add(_t.status.listen(_onStatus))
      ..add(_t.errors.listen(_onError))
      ..add(_t.levels.listen(_onLevel));
  }

  void _log(String event, [String detail = '']) {
    try {
      _logSink.record(event, detail);
    } catch (_) {}
  }

  void _setMuted(bool on) {
    if (_muted == on) return;
    _muted = on;
    try {
      unawaited(on ? _audio.mute() : _audio.unmute());
    } catch (_) {}
  }

  void _watchLifecycle() {
    if (_lifecycle != null) return;
    try {
      _lifecycle = AppLifecycleListener(onStateChange: onAppLifecycle);
    } catch (_) {
      // No widgets binding (plain unit tests).
    }
  }

  /// App went to the background: the mic can't keep listening there — stop
  /// (keeping the words) and give the beeps back at once.
  @visibleForTesting
  void onAppLifecycle(AppLifecycleState s) {
    if (s != AppLifecycleState.paused && s != AppLifecycleState.detached) {
      return;
    }
    _setMuted(false);
    if (state.isActive) unawaited(stop(reason: 'background'));
  }

  void _cancelTimers() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    _startWatchdog?.cancel();
    _startWatchdog = null;
    _ticker?.cancel();
    _ticker = null;
  }

  /// Starts dictating (keeps previously committed text — call [clear] first
  /// for a fresh transcript). Returns false when not possible (state tells
  /// why: `unavailable` + hint, or `error` + permission).
  Future<bool> start() async {
    if (state.isActive) return false;
    _set(
      state.copyWith(
        phase: DictationPhase.starting,
        partial: '',
        clearError: true,
        clearStopIn: true,
        elapsed: Duration.zero,
      ),
    );

    if (ref.exists(voiceRecorderControllerProvider)) {
      final rec = ref.read(voiceRecorderControllerProvider.notifier);
      if (ref.read(voiceRecorderControllerProvider).isBusy) {
        await rec.stop();
      }
    }

    final locale = ref.read(speechLocaleProvider);
    final availability = await _t.availability(locale: locale);
    // Cancelled / stopped while starting → stay idle.
    if (!ref.mounted || state.phase != DictationPhase.starting) return false;
    final allowNetwork = ref.read(dictationAllowsNetworkProvider);
    if (!availability.canDictate(allowNetwork: allowNetwork)) {
      _log('tidak tersedia', '$locale · ${availability.offline.name}');
      _set(
        state.copyWith(
          phase: DictationPhase.unavailable,
          availability: availability,
        ),
      );
      return false;
    }

    final perm = ref.read(microphonePermissionProvider);
    var status = await perm.status();
    if (!status.isGranted && status != MicPermissionStatus.unsupported) {
      status = await perm.request();
    }
    if (!ref.mounted || state.phase != DictationPhase.starting) return false;
    if (!status.isGranted) {
      _log('gagal', 'izin mikrofon: ${status.name}');
      _set(
        state.copyWith(
          phase: DictationPhase.error,
          availability: availability,
          permission: status,
          error: const SpeechError(SpeechErrorKind.permission, permanent: true),
        ),
      );
      return false;
    }

    _subscribe();
    _want = true;
    _errorStreak = 0;
    _quietSeconds = 0;
    _elapsedSeconds = 0;
    _sessions = 0;
    _retries = 0;
    _autoTail = '';
    _lastFinal = '';
    _prevSessionText = '';
    _endReason = 'stop';
    _wordsAtStart = _wordCount(state.committed);
    _set(state.copyWith(availability: availability, permission: status));
    _log(
      'mulai',
      '$locale · ${allowNetwork ? 'online boleh' : 'offline'} · '
          'paket ${availability.offline.name}',
    );
    _setMuted(true);
    _watchLifecycle();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
    return _listen();
  }

  Future<bool> _listen() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    _finalizeTimer?.cancel(); // stale timer of a previous session
    _finalizeTimer = null;
    _startWatchdog?.cancel();
    final session = ++_session;
    _sessions++;
    _sessionOpen = true;
    _live = false;
    _sessionHasPartial = false;
    _sessionText = '';
    _sessionCommitted = '';
    _lastRaw = '';
    _wordsAtSession = _wordCount(state.committed);
    _sessionStartedAt = DateTime.now();
    try {
      await _t.start(
        locale: ref.read(speechLocaleProvider),
        preferOffline: !ref.read(dictationAllowsNetworkProvider),
      );
    } on SpeechError catch (e) {
      if (!ref.mounted || session != _session) return false;
      _sessionOpen = false;
      if (!_want) return false;
      if (e.kind.isFatal) {
        _fail(e);
        return false;
      }
      _retryAfter(e);
      return _want;
    }
    if (!ref.mounted || !_want) {
      // Disposed (editor closed) or stopped/cancelled while the recognizer
      // was opening: release the mic now — nobody will stop it later.
      unawaited(_t.cancel());
      return false;
    }
    if (session != _session) return true;
    if (state.phase != DictationPhase.stopping) {
      _set(state.copyWith(phase: DictationPhase.listening));
    }
    if (!_live) {
      _startWatchdog = Timer(startTimeout, () {
        if (session != _session || !_sessionOpen || _live || !_want) return;
        const e = SpeechError(SpeechErrorKind.busy, raw: 'listen_not_started');
        _endSession(e.raw!);
        _retryAfter(e);
      });
    }
    return true;
  }

  // --- events ------------------------------------------------------------------

  /// Voice or words: the silence guard starts over (and its warning goes).
  void _heard() {
    _quietSeconds = 0;
    if (state.stopIn != null) {
      _log('lanjut', 'ada suara');
      _set(state.copyWith(clearStopIn: true));
    }
  }

  void _onLevel(double l) {
    _set(state.copyWith(level: l));
    if (l >= voiceLevel) _heard();
  }

  void _onResult(TranscriptUpdate r) {
    if (!_want && state.phase != DictationPhase.stopping) return;
    final text = r.text.trim();
    if (r.stale) {
      // The previous session, closed for a restart: its partial is old news
      // (its words were committed when it ended); a final may add words.
      if (!r.isFinal || text.isEmpty) {
        _log('abaikan', 'partial sesi lama · ${_wordCount(text)} kata');
        return;
      }
      _addLateFinal(_prevSessionText, text, 'final sesi lama');
      return;
    }
    if (!r.isFinal) {
      // A partial after its session ended is a leftover; an empty partial
      // would blank the live line for a moment (flicker) — keep the last one.
      if (text.isEmpty) return;
      if (!_sessionOpen) {
        _log('abaikan', 'partial di luar sesi · ${_wordCount(text)} kata');
        return;
      }
      _sessionHasPartial = true;
      _autoTail = '';
      _errorStreak = 0;
      _heard();
      if (_lastRaw.isNotEmpty && !transcriptContinues(_lastRaw, text)) {
        // The recognizer started over (new segment of a long utterance):
        // the live words so far are final — never let them be replaced.
        _commitSegment('mulai ulang');
      }
      _lastRaw = text;
      final live = transcriptTail(_sessionCommitted, text);
      _sessionText = joinTranscript(_sessionCommitted, live);
      if (live != state.partial) _set(state.copyWith(partial: live));
      if (r.segmentEnd) _commitSegment('final_result');
      return;
    }

    // Final result.
    final ownSession =
        _sessionOpen && (_sessionHasPartial || _autoTail.isEmpty);
    if (!ownSession) {
      // Late final of a session that already ended (its words were committed
      // from the last partial), or a duplicate.
      _addLateFinal(
        _autoTail.isNotEmpty ? _autoTail : _prevSessionText,
        text,
        'final terlambat',
      );
      _autoTail = '';
      return;
    }
    // The live words of the current segment, and what the final adds to the
    // segments this session already committed. Some recognizers end with an
    // empty final (the last partial is the text), some with only the last
    // segment, some with the whole session.
    final live = state.partial;
    final fresh = transcriptTail(_sessionCommitted, text);
    final String words;
    if (fresh.isEmpty) {
      words = live;
    } else if (live.isEmpty || transcriptContinues(live, fresh)) {
      words = fresh; // the final's wording wins
    } else {
      // The final covers only the end of the live words: keep them all.
      words = joinTranscript(live, transcriptTail(live, fresh));
    }
    if (!_sessionHasPartial && words.isNotEmpty && words == _lastFinal) {
      _log('abaikan', 'final ganda · ${_wordCount(words)} kata');
      return; // plugin re-sent the previous session's final
    }
    if (words.isNotEmpty) {
      _lastFinal = words;
      _errorStreak = 0;
      _heard();
    }
    _sessionText = joinTranscript(_sessionCommitted, words);
    // One update: final into committed, live line cleared → no flicker.
    _set(
      state.copyWith(
        committed: joinTranscript(state.committed, words),
        partial: '',
      ),
    );
    _endSession('final', hadFinal: true);
  }

  /// Moves the live words of the running session into committed (end of a
  /// segment).
  void _commitSegment(String reason) {
    final live = state.partial;
    if (live.isEmpty) return;
    _sessionCommitted = joinTranscript(_sessionCommitted, live);
    _set(
      state.copyWith(
        committed: joinTranscript(state.committed, live),
        partial: '',
      ),
    );
    _log('segmen', '#$_sessions · ${_wordCount(live)} kata · $reason');
  }

  /// A final of a session that is over: only the words not committed yet.
  void _addLateFinal(String known, String text, String what) {
    final extra = lateFinalExtra(known, text);
    if (text.isNotEmpty) _lastFinal = text;
    if (extra.isEmpty) {
      if (text.isNotEmpty) {
        _log('abaikan', '$what · ${_wordCount(text)} kata sudah ada');
      }
      return;
    }
    _heard();
    _prevSessionText = joinTranscript(known, extra);
    _set(state.copyWith(committed: joinTranscript(state.committed, extra)));
    _log('susulan', '$what · +${_wordCount(extra)} kata');
  }

  void _onStatus(SpeechSessionStatus s) {
    if (s == SpeechSessionStatus.listening) {
      if (_sessionOpen) {
        _live = true;
        _startWatchdog?.cancel();
        _startWatchdog = null;
      }
      return;
    }
    if (state.phase == DictationPhase.stopping) {
      if (s == SpeechSessionStatus.done) {
        _endSession('stop');
      } else {
        // Wait for the final result (`done` follows it).
        _finalizeTimer ??= Timer(finalizeTimeout, () => _finalize());
      }
      return;
    }
    // Leftover of the previous session, or the session already ended (final).
    if (!_sessionOpen || !_live) return;
    _endSession('akhir sesi');
  }

  void _onError(SpeechError e) {
    if (!_want && state.phase != DictationPhase.stopping) return;
    if (e.kind.isFatal) {
      _fail(e);
      return;
    }
    final code = e.raw ?? e.kind.name;
    if (state.phase == DictationPhase.stopping) {
      _endSession(code);
      return;
    }
    if (e.kind.isSilence) {
      _errorStreak = 0;
      _endSession(code); // no-op when the session already ended
      return;
    }
    _endSession(code);
    _retryAfter(e);
  }

  /// A recognizer session is over: commit leftovers, then restart or finish.
  void _endSession(String reason, {bool hadFinal = false}) {
    if (!_sessionOpen) {
      if (state.phase == DictationPhase.stopping) _finalize();
      return;
    }
    _sessionOpen = false;
    _live = false;
    _startWatchdog?.cancel();
    _startWatchdog = null;
    if (!hadFinal) {
      // No final for this session (yet): its last partial is the text. A
      // final that still arrives later is de-duplicated against the whole
      // session (it may repeat the segments committed before, too).
      _autoTail = joinTranscript(_sessionCommitted, state.partial);
      if (state.partial.isNotEmpty) {
        _set(
          state.copyWith(
            committed: joinTranscript(state.committed, state.partial),
            partial: '',
          ),
        );
      }
    }
    if (_sessionText.isNotEmpty) _prevSessionText = _sessionText;
    _logSession(reason);
    if (!ref.mounted) return;
    if (state.phase == DictationPhase.stopping || !_want) {
      _finalize();
      return;
    }
    _scheduleRestart(restartDelay);
  }

  void _scheduleRestart(Duration wait) {
    _restartTimer?.cancel();
    if (state.phase != DictationPhase.restarting) {
      _set(state.copyWith(phase: DictationPhase.restarting, level: 0));
    }
    _restartTimer = Timer(wait, () {
      _restartTimer = null;
      if (_want && ref.mounted) unawaited(_listen());
    });
  }

  /// Light error: try again after a growing pause; give up after
  /// [maxRetries] in a row.
  void _retryAfter(SpeechError e) {
    if (_errorStreak >= maxRetries) {
      _fail(e);
      return;
    }
    final wait = retryBackoff[_errorStreak];
    _errorStreak++;
    _retries++;
    _log(
      'ulang',
      '${e.raw ?? e.kind.name} · coba $_errorStreak/$maxRetries · '
          'tunggu ${wait.inMilliseconds} ms',
    );
    _scheduleRestart(wait);
  }

  void _tick(Timer _) {
    if (!ref.mounted || !_want) return;
    _elapsedSeconds++;
    _quietSeconds++;
    var stopIn = state.stopIn;
    if (stopIn != null) {
      stopIn--;
      if (stopIn <= 0) {
        _set(
          state.copyWith(
            elapsed: Duration(seconds: _elapsedSeconds),
            clearStopIn: true,
          ),
        );
        unawaited(stop(reason: 'diam ${silenceTimeout.inMinutes} menit'));
        return;
      }
    } else if (_quietSeconds >= silenceTimeout.inSeconds) {
      stopIn = silenceGrace.inSeconds;
      _log('peringatan', 'tidak ada suara ${silenceTimeout.inMinutes} menit');
    }
    _set(
      state.copyWith(
        elapsed: Duration(seconds: _elapsedSeconds),
        stopIn: stopIn,
      ),
    );
  }

  /// "Lanjutkan": the user is still there — dismiss the silence warning.
  void keepListening() {
    if (!state.isActive) return;
    _quietSeconds = 0;
    if (state.stopIn != null) {
      _log('lanjut', 'ketuk');
      _set(state.copyWith(clearStopIn: true));
    }
  }

  // --- end -----------------------------------------------------------------------

  void _logSession(String reason) {
    final words = _wordCount(_sessionText);
    if (words == 0) {
      // Silent sessions fold into one line (x12) instead of flooding the log.
      _log('sesi', 'kosong · $reason');
      return;
    }
    final ms = DateTime.now().difference(_sessionStartedAt).inMilliseconds;
    _log(
      'sesi',
      '#$_sessions · ${(ms / 1000).toStringAsFixed(1)} dtk · '
          '$words kata · $reason · '
          'total $_wordsAtSession→${_wordCount(state.committed)} kata',
    );
  }

  void _logSummary(String reason) {
    final words = math.max(0, _wordCount(_last.text) - _wordsAtStart);
    _log(
      'selesai',
      '${formatDictationElapsed(Duration(seconds: _elapsedSeconds))} · '
          '$words kata · $_sessions sesi · $_retries ulang · $reason',
    );
  }

  void _fail(SpeechError e) {
    _want = false;
    _sessionOpen = false;
    _cancelTimers();
    _setMuted(false);
    _log('gagal', '${e.kind.name} · ${e.raw ?? '-'}');
    _set(
      state.copyWith(
        phase: DictationPhase.error,
        committed: joinTranscript(state.committed, state.partial),
        partial: '',
        error: e,
        level: 0,
        clearStopIn: true,
      ),
    );
    _logSummary('error');
    if (_t.isListening) unawaited(_t.cancel());
    _completeStop();
  }

  void _finalize() {
    final wasActive = _want || state.isActive;
    _want = false;
    _sessionOpen = false;
    _cancelTimers();
    _setMuted(false);
    _set(
      state.copyWith(
        phase: DictationPhase.idle,
        committed: joinTranscript(state.committed, state.partial),
        partial: '',
        level: 0,
        clearStopIn: true,
      ),
    );
    if (wasActive) _logSummary(_endReason);
    _completeStop();
  }

  void _completeStop() {
    final c = _stopCompleter;
    _stopCompleter = null;
    if (c != null && !c.isCompleted) c.complete(state.text);
  }

  /// Stops listening; completes with the full transcript once the final
  /// result arrived (or after [finalizeTimeout]).
  Future<String> stop({String reason = 'stop'}) async {
    if (!state.isActive) return state.text;
    _want = false;
    _endReason = reason;
    _restartTimer?.cancel();
    _restartTimer = null;
    _setMuted(false);
    if (state.phase == DictationPhase.restarting ||
        state.phase == DictationPhase.starting ||
        !_sessionOpen) {
      _finalize();
      if (_t.isListening) await _t.cancel();
      return state.text;
    }
    final c = _stopCompleter ??= Completer<String>();
    _set(state.copyWith(phase: DictationPhase.stopping));
    _finalizeTimer ??= Timer(finalizeTimeout, _finalize);
    await _t.stop();
    return c.future;
  }

  /// Aborts listening; keeps text committed so far, drops the live partial.
  Future<void> cancel() async {
    if (!state.isActive) return;
    _want = false;
    _sessionOpen = false;
    _cancelTimers();
    _setMuted(false);
    _set(
      state.copyWith(
        phase: DictationPhase.idle,
        partial: '',
        level: 0,
        clearStopIn: true,
      ),
    );
    _logSummary('batal');
    _completeStop();
    await _t.cancel();
  }

  /// Returns the transcript and resets it (after inserting into the body).
  String takeText() {
    final t = state.text;
    clear();
    return t;
  }

  void clear() {
    if (state.isActive) return;
    _autoTail = '';
    _prevSessionText = '';
    _set(
      DictationState(
        phase: state.phase == DictationPhase.unavailable
            ? DictationPhase.unavailable
            : DictationPhase.idle,
        availability: state.availability,
      ),
    );
  }

  /// Android 13+: asks the OS to download the offline `id-ID` model.
  Future<bool> downloadOfflineModel() async {
    final ok = await _t.requestOfflineModel(
      locale: ref.read(speechLocaleProvider),
    );
    ref.invalidate(speechAvailabilityProvider);
    return ok;
  }

  Future<bool> openSettings() =>
      ref.read(microphonePermissionProvider).openAppSettings();
}

/// Auto-disposed: leaving the editor stops dictation and releases the mic.
final dictationControllerProvider =
    NotifierProvider.autoDispose<DictationController, DictationState>(
      DictationController.new,
    );
