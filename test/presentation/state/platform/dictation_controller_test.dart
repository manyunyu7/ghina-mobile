import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/diagnostics/dictation_log.dart';
import 'package:ghina/data/platform/dictation_channels.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

void main() {
  late FakeSpeechTranscriber speech;
  late FakeMicrophonePermission permission;
  late FakeVoiceRecorder recorder;
  late FakeDictationAudio audio;
  late DictationLog log;

  ProviderContainer makeContainer({
    bool allowNetwork = false,
    DictationAudio? audioOverride,
  }) {
    speech = FakeSpeechTranscriber();
    permission = FakeMicrophonePermission();
    recorder = FakeVoiceRecorder();
    audio = FakeDictationAudio();
    log = DictationLog.memory();
    final c = ProviderContainer(
      overrides: [
        speechTranscriberProvider.overrideWithValue(speech),
        microphonePermissionProvider.overrideWithValue(permission),
        voiceRecorderProvider.overrideWithValue(recorder),
        dictationAllowsNetworkProvider.overrideWithValue(allowNetwork),
        dictationAudioProvider.overrideWithValue(audioOverride ?? audio),
        dictationLogProvider.overrideWithValue(log),
      ],
    );
    c.listen(dictationControllerProvider, (_, _) {});
    return c;
  }

  DictationState st(ProviderContainer c) => c.read(dictationControllerProvider);
  DictationController ctl(ProviderContainer c) =>
      c.read(dictationControllerProvider.notifier);

  test('joinTranscript', () {
    expect(joinTranscript('', ''), '');
    expect(joinTranscript(' a ', ''), 'a');
    expect(joinTranscript('', 'b'), 'b');
    expect(joinTranscript('a', ' b'), 'a b');
  });

  test('partials replace each other; final is committed', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.listening);
      expect(speech.calls, ['start:id-ID']);

      speech.partial('beli');
      expect(st(c).partial, 'beli');
      speech.partial('beli susu');
      expect(st(c).partial, 'beli susu');
      expect(st(c).text, 'beli susu');
      speech.finalResult('beli susu dan roti');
      expect(st(c).committed, 'beli susu dan roti');
      expect(st(c).partial, '');
      c.dispose();
    });
  });

  test(
    'restarts after Android ends the session; accumulates across sessions',
    () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();

        speech.partial('satu');
        speech.finalResult('satu');
        speech.endSession(); // silence timeout
        expect(st(c).phase, DictationPhase.restarting);
        fa.elapse(DictationController.restartDelay);
        expect(speech.starts, 2);
        expect(st(c).phase, DictationPhase.listening);

        speech.partial('dua');
        // Session ends without a final result → partial is committed.
        speech.endSession();
        expect(st(c).committed, 'satu dua');
        fa.elapse(DictationController.restartDelay);
        expect(speech.starts, 3);

        // The new session's result counts.
        speech.finalResult('tiga');
        expect(st(c).text, 'satu dua tiga');
        c.dispose();
      });
    },
  );

  test('late duplicate final after the session ended is ignored', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.finalResult('halo');
      speech.finalResult('halo'); // plugin's finalTimeout duplicate
      expect(st(c).committed, 'halo');
      c.dispose();
    });
  });

  test('stop waits for the final result and returns the full text', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.finalResult('pertama');
      speech.endSession();
      fa.elapse(DictationController.restartDelay);
      speech.partial('kedua ya');

      String? out;
      ctl(c).stop().then((t) => out = t);
      fa.flushMicrotasks();
      // FakeSpeechTranscriber.stop ends the session (no final) → partial kept.
      expect(out, 'pertama kedua ya');
      expect(st(c).phase, DictationPhase.idle);
      expect(fa.pendingTimers, isEmpty);

      expect(ctl(c).takeText(), 'pertama kedua ya');
      expect(st(c).text, '');
      c.dispose();
    });
  });

  test('stop times out when the recognizer never answers', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.partial('menggantung');
      speech.listening = false; // stop() will not emit anything
      String? out;
      ctl(c).stop().then((t) => out = t);
      fa.flushMicrotasks();
      expect(out, isNull);
      expect(st(c).phase, DictationPhase.stopping);
      fa.elapse(DictationController.finalizeTimeout);
      expect(out, 'menggantung');
      expect(st(c).phase, DictationPhase.idle);
      c.dispose();
    });
  });

  test('silent sessions restart forever (no silent-session limit)', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      for (var i = 0; i < 10; i++) {
        speech.error(SpeechErrorKind.noMatch);
        speech.endSession(); // error + done for the same session → one restart
        fa.elapse(DictationController.restartDelay);
      }
      speech.error(SpeechErrorKind.speechTimeout);
      fa.elapse(DictationController.restartDelay);
      expect(speech.starts, 12);
      expect(st(c).phase, DictationPhase.listening);
      c.dispose();
    });
  });

  test('words reset the silent-session counter', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      for (var round = 0; round < 3; round++) {
        speech.error(SpeechErrorKind.noMatch);
        fa.elapse(DictationController.restartDelay);
        speech.error(SpeechErrorKind.noMatch);
        fa.elapse(DictationController.restartDelay);
        speech.finalResult('kata $round');
        speech.endSession();
        fa.elapse(DictationController.restartDelay);
      }
      expect(st(c).phase, DictationPhase.listening);
      expect(st(c).committed, 'kata 0 kata 1 kata 2');
      c.dispose();
    });
  });

  test('fatal error stops with error and keeps the text', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.partial('sebagian');
      speech.error(SpeechErrorKind.languageUnavailable, permanent: true);
      expect(st(c).phase, DictationPhase.error);
      expect(st(c).error!.kind, SpeechErrorKind.languageUnavailable);
      expect(st(c).committed, 'sebagian');
      fa.elapse(const Duration(seconds: 5));
      expect(speech.starts, 1);
      c.dispose();
    });
  });

  test(
    'offline model missing and network not allowed → unavailable + hint',
    () {
      fakeAsync((fa) {
        final c = makeContainer();
        speech.available = const SpeechAvailability(
          recognizerAvailable: true,
          offline: OfflineSpeechSupport.downloadable,
        );
        bool? ok;
        ctl(c).start().then((v) => ok = v);
        fa.flushMicrotasks();
        expect(ok, isFalse);
        expect(st(c).phase, DictationPhase.unavailable);
        expect(st(c).hint, contains('Unduh'));
        expect(speech.starts, 0);

        ctl(c).downloadOfflineModel();
        fa.flushMicrotasks();
        expect(speech.calls, contains('download:id-ID'));
        c.dispose();
      });
    },
  );

  test('network allowed → dictation may start without offline model', () {
    fakeAsync((fa) {
      final c = makeContainer(allowNetwork: true);
      speech.available = const SpeechAvailability(
        recognizerAvailable: true,
        offline: OfflineSpeechSupport.unsupported,
      );
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.listening);
      c.dispose();
    });
  });

  test('permission denied → error, recognizer not started', () {
    fakeAsync((fa) {
      final c = makeContainer();
      permission
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.denied;
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.error);
      expect(st(c).error!.kind, SpeechErrorKind.permission);
      expect(st(c).permission, MicPermissionStatus.denied);
      expect(speech.starts, 0);
      c.dispose();
    });
  });

  test('start failure from the recognizer → error', () {
    fakeAsync((fa) {
      final c = makeContainer();
      speech.startError = const SpeechError(
        SpeechErrorKind.languageUnavailable,
        permanent: true,
      );
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.error);
      expect(st(c).error!.kind, SpeechErrorKind.languageUnavailable);
      c.dispose();
    });
  });

  test('cancel drops the live partial and keeps committed text', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.finalResult('simpan');
      speech.endSession();
      fa.elapse(DictationController.restartDelay);
      speech.partial('buang');
      ctl(c).cancel();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.idle);
      expect(st(c).text, 'simpan');
      fa.elapse(const Duration(seconds: 5));
      expect(fa.pendingTimers, isEmpty);
      c.dispose();
    });
  });

  test('dictation stops an active voice recording first', () {
    fakeAsync((fa) {
      final c = makeContainer();
      c.listen(voiceRecorderControllerProvider, (_, _) {});
      c.read(voiceRecorderControllerProvider.notifier).start();
      fa.flushMicrotasks();
      expect(c.read(voiceRecorderControllerProvider).isRecording, isTrue);

      ctl(c).start();
      fa.flushMicrotasks();
      expect(recorder.calls, ['start', 'stop']);
      expect(c.read(voiceRecorderControllerProvider).isRecording, isFalse);
      expect(st(c).phase, DictationPhase.listening);
      c.dispose();
    });
  });

  group('long silence', () {
    test('many empty sessions never stop dictation before 2 minutes', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        // Android closes a session every ~6 s of silence.
        for (var i = 0; i < 19; i++) {
          fa.elapse(const Duration(seconds: 6));
          speech.error(SpeechErrorKind.noMatch);
          speech.endSession();
        }
        fa.elapse(const Duration(seconds: 5)); // 119 s
        expect(st(c).isActive, isTrue);
        expect(st(c).stopIn, isNull);
        expect(speech.starts, 20);
        expect(st(c).elapsed, const Duration(seconds: 119));
        c.dispose();
      });
    });

    test('warning after 2 min without voice, stop 10 s later', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        speech.finalResult('catatan');
        fa.elapse(DictationController.silenceTimeout);
        expect(st(c).stopIn, 10);
        expect(st(c).isActive, isTrue);
        fa.elapse(const Duration(seconds: 9));
        expect(st(c).stopIn, 1);
        expect(st(c).isActive, isTrue);
        fa.elapse(const Duration(seconds: 1));
        expect(st(c).phase, DictationPhase.idle);
        expect(st(c).text, 'catatan');
        expect(audio.calls, ['mute', 'unmute']);
        expect(
          log.entries.map((e) => e.event),
          containsAll(['peringatan', 'selesai']),
        );
        expect(log.entries.first.detail, contains('diam 2 menit'));
        fa.elapse(const Duration(seconds: 30));
        expect(fa.pendingTimers, isEmpty);
        c.dispose();
      });
    });

    test('speaking, a loud level or a tap cancels the warning', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        fa.elapse(DictationController.silenceTimeout);
        expect(st(c).stopIn, 10);
        speech.partial('masih di sini');
        expect(st(c).stopIn, isNull);

        fa.elapse(DictationController.silenceTimeout);
        expect(st(c).stopIn, 10);
        speech.level(0.2); // background noise doesn't count
        expect(st(c).stopIn, 10);
        speech.level(0.9);
        expect(st(c).stopIn, isNull);

        fa.elapse(DictationController.silenceTimeout);
        expect(st(c).stopIn, 10);
        fa.elapse(const Duration(seconds: 5));
        ctl(c).keepListening();
        expect(st(c).stopIn, isNull);
        fa.elapse(const Duration(seconds: 60));
        expect(st(c).isActive, isTrue);
        c.dispose();
      });
    });
  });

  group('restart', () {
    test('next session starts right after the final (no wait for done)', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        speech.partial('satu dua');
        speech.finalResult('satu dua tiga');
        expect(st(c).committed, 'satu dua tiga');
        expect(st(c).phase, DictationPhase.restarting);
        // The plugin would only report the session end seconds later.
        fa.elapse(DictationController.restartDelay);
        expect(speech.starts, 2);
        expect(st(c).phase, DictationPhase.listening);
        expect(DictationController.restartDelay.inMilliseconds, lessThan(60));
        speech.finalResult('empat');
        expect(st(c).committed, 'satu dua tiga empat');
        c.dispose();
      });
    });

    test(
      'words of a session without final are kept; late final not doubled',
      () {
        fakeAsync((fa) {
          final c = makeContainer();
          ctl(c).start();
          fa.flushMicrotasks();
          speech.partial('kirim pesan');
          speech.endSession(); // ended without a final
          expect(st(c).committed, 'kirim pesan');
          fa.elapse(DictationController.restartDelay);
          expect(speech.starts, 2);
          // The old session's final shows up late, a bit longer.
          speech.finalResult('kirim pesan ke ibu');
          expect(st(c).committed, 'kirim pesan ke ibu');
          // …and again (duplicate) → ignored.
          speech.finalResult('kirim pesan ke ibu');
          expect(st(c).committed, 'kirim pesan ke ibu');
          // The new session works normally.
          speech.partial('besok');
          speech.finalResult('besok pagi');
          expect(st(c).committed, 'kirim pesan ke ibu besok pagi');
          c.dispose();
        });
      },
    );

    test('late final that only differs slightly is not added twice', () {
      expect(lateFinalExtra('beli susu', 'beli susu'), '');
      expect(lateFinalExtra('beli susu', 'Beli susu dan roti'), 'dan roti');
      expect(lateFinalExtra('beli susu cokelat', 'beli susu coklat'), '');
      expect(lateFinalExtra('beli susu', 'rapat jam tiga'), 'rapat jam tiga');
      expect(lateFinalExtra('', 'halo'), 'halo');
    });

    test('empty final commits the last partial', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        speech.partial('jangan hilang');
        speech.finalResult('');
        expect(st(c).committed, 'jangan hilang');
        expect(st(c).partial, '');
        c.dispose();
      });
    });
  });

  group('errors', () {
    test('busy / client → retry with backoff, then continue', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        speech.partial('halo');
        speech.error(SpeechErrorKind.busy);
        expect(st(c).phase, DictationPhase.restarting);
        expect(st(c).committed, 'halo');
        fa.elapse(const Duration(milliseconds: 199));
        expect(speech.starts, 1);
        fa.elapse(const Duration(milliseconds: 1));
        expect(speech.starts, 2);

        speech.error(SpeechErrorKind.client);
        fa.elapse(const Duration(milliseconds: 499));
        expect(speech.starts, 2);
        fa.elapse(const Duration(milliseconds: 1));
        expect(speech.starts, 3);
        expect(st(c).phase, DictationPhase.listening);

        // Words reset the backoff.
        speech.partial('lanjut');
        speech.error(SpeechErrorKind.server);
        fa.elapse(const Duration(milliseconds: 200));
        expect(speech.starts, 4);
        expect(st(c).committed, 'halo lanjut');
        expect(st(c).error, isNull);
        expect(log.entries.where((e) => e.event == 'ulang'), hasLength(3));
        c.dispose();
      });
    });

    test('a start that fails with busy is retried', () {
      fakeAsync((fa) {
        final c = makeContainer();
        speech.startError = const SpeechError(
          SpeechErrorKind.busy,
          raw: 'error_busy',
        );
        bool? ok;
        ctl(c).start().then((v) => ok = v);
        fa.flushMicrotasks();
        expect(ok, isTrue);
        expect(st(c).phase, DictationPhase.restarting);
        speech.startError = null;
        fa.elapse(const Duration(milliseconds: 200));
        expect(speech.starts, 2);
        expect(st(c).phase, DictationPhase.listening);
        c.dispose();
      });
    });

    test('too many light errors in a row → error', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        for (var i = 0; i < DictationController.maxRetries; i++) {
          speech.error(SpeechErrorKind.network);
          fa.elapse(const Duration(seconds: 3));
          expect(st(c).isActive, isTrue);
        }
        speech.error(SpeechErrorKind.network);
        expect(st(c).phase, DictationPhase.error);
        expect(st(c).error!.kind, SpeechErrorKind.network);
        expect(audio.muted, isFalse);
        c.dispose();
      });
    });

    test('permission error → fails at once with a clear message', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        speech.error(SpeechErrorKind.permission);
        expect(st(c).phase, DictationPhase.error);
        expect(st(c).error!.kind.message, contains('Izin mikrofon'));
        fa.elapse(const Duration(seconds: 5));
        expect(speech.starts, 1);
        expect(audio.calls, ['mute', 'unmute']);
        expect(log.entries.first.event, 'selesai');
        expect(log.entries.map((e) => e.event), contains('gagal'));
        c.dispose();
      });
    });
  });

  test('committed text only grows; only the live partial moves', () {
    fakeAsync((fa) {
      final c = makeContainer();
      final committed = <String>[];
      final partials = <String>[];
      c.listen(dictationControllerProvider, (_, n) {
        committed.add(n.committed);
        partials.add(n.partial);
      });
      ctl(c).start();
      fa.flushMicrotasks();
      speech.partial('saya');
      speech.partial('saya mau');
      speech.partial(''); // recognizer hiccup → ignored, no blank flash
      speech.partial('saya mau pesan');
      speech.finalResult('saya mau pesan kopi');
      speech.endSession();
      fa.elapse(DictationController.restartDelay);
      speech.partial('dua');
      speech.partial('dua gelas');
      speech.endSession(); // no final
      fa.elapse(DictationController.restartDelay);
      speech.finalResult('dua gelas'); // late duplicate
      ctl(c).stop();
      fa.flushMicrotasks();

      for (var i = 1; i < committed.length; i++) {
        expect(
          committed[i].startsWith(committed[i - 1]),
          isTrue,
          reason: '"${committed[i - 1]}" → "${committed[i]}"',
        );
      }
      expect(
        partials.where((p) => p.isEmpty).length,
        lessThan(partials.length),
      );
      // The live line never blanks between two partials of one utterance.
      final i = partials.indexOf('saya mau');
      expect(partials[i + 1], anyOf('saya mau', 'saya mau pesan'));
      expect(st(c).text, 'saya mau pesan kopi dua gelas');
      c.dispose();
    });
  });

  group('beep mute', () {
    test(
      'mute / unmute in pairs: stop, cancel, error, dispose, background',
      () {
        fakeAsync((fa) {
          final c = makeContainer();
          ctl(c).start();
          fa.flushMicrotasks();
          expect(audio.calls, ['mute']);
          // Restarts don't toggle it.
          speech.finalResult('a');
          fa.elapse(DictationController.restartDelay);
          expect(audio.calls, ['mute']);
          ctl(c).stop();
          fa.flushMicrotasks();
          expect(audio.calls, ['mute', 'unmute']);

          ctl(c).start();
          fa.flushMicrotasks();
          ctl(c).cancel();
          fa.flushMicrotasks();
          expect(audio.calls, ['mute', 'unmute', 'mute', 'unmute']);

          ctl(c).start();
          fa.flushMicrotasks();
          ctl(c).onAppLifecycle(AppLifecycleState.paused);
          fa.flushMicrotasks();
          expect(audio.calls.sublist(4), ['mute', 'unmute']);
          expect(st(c).isActive, isFalse);
          expect(log.entries.first.detail, contains('background'));

          ctl(c).start();
          fa.flushMicrotasks();
          expect(audio.calls.last, 'mute');
          c.dispose();
          expect(audio.calls.last, 'unmute');
          expect(audio.calls.where((x) => x == 'mute').length, 4);
          expect(audio.calls.where((x) => x == 'unmute').length, 4);
        });
      },
    );

    testWidgets('over the app/dictation_audio channel, also on background', (
      tester,
    ) async {
      final calls = <String>[];
      const channel = MethodChannel(ChannelDictationAudio.channelName);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final c = makeContainer(audioOverride: ChannelDictationAudio());
      unawaited(ctl(c).start());
      await tester.pump();
      expect(calls, ['mute']);
      expect(st(c).phase, DictationPhase.listening);

      // Home button: inactive → hidden → paused.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls, ['mute', 'unmute']);
      expect(st(c).isActive, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      unawaited(ctl(c).start());
      await tester.pump();
      c.dispose(); // editor closed mid-dictation
      await tester.pump();
      expect(calls, ['mute', 'unmute', 'mute', 'unmute']);
    });
  });

  test('diagnostic log: start, sessions (silence folded), summary', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      for (var i = 0; i < 5; i++) {
        speech.error(SpeechErrorKind.noMatch, permanent: true);
        fa.elapse(DictationController.restartDelay);
      }
      speech.partial('halo semua');
      speech.finalResult('halo semua');
      fa.elapse(DictationController.restartDelay);
      ctl(c).stop();
      fa.flushMicrotasks();
      final events = log.entries.reversed.toList(); // oldest first
      expect(events.first.event, 'mulai');
      expect(events.first.detail, contains('id-ID'));
      final silent = events.firstWhere((e) => e.detail.startsWith('kosong'));
      expect(silent.count, 5);
      expect(
        events.any((e) => e.event == 'sesi' && e.detail.contains('2 kata')),
        isTrue,
      );
      expect(events.last.event, 'selesai');
      expect(events.last.detail, contains('2 kata'));
      expect(events.last.detail, contains('7 sesi'));
      expect(log.entries.length, lessThan(10));
      expect(log.toText(), contains('mulai'));
      c.dispose();
    });
  });

  // --- bug "yang diambil malah bagian akhirnya doang" (Ravel 1.18.0, Fold) ---
  //
  // Urutan event realistis: on-device recognizer Google/Samsung memecah
  // ucapan panjang jadi segmen; setelah satu segmen partial mulai lagi dari
  // kata baru, dan final bisa hanya berisi segmen terakhir.

  group('ucapan panjang: tidak ada kata yang hilang', () {
    const awal = 'aku udah ngomong panjang lebar soal kartu';
    const tengah = 'terus tombolnya harus dipindah ke atas';
    const akhir = 'jenisnya yang diklik tadi';

    void say(String words) {
      // partial kumulatif per segmen: kata demi kata
      final w = words.split(' ');
      for (var i = 1; i <= w.length; i++) {
        speech.partial(w.take(i).join(' '));
      }
    }

    test('partial mulai ulang per segmen, final hanya segmen terakhir', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        say(awal);
        say(tengah); // partial mulai ulang tanpa tanda apa pun
        say(akhir);
        speech.finalResult(akhir);
        expect(st(c).committed, '$awal $tengah $akhir');
        c.dispose();
      });
    });

    test('segmen bertanda final_result (intermediate), lalu stop', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        say(awal);
        speech.segment(awal);
        say(tengah);
        speech.segment(tengah);
        say(akhir);
        String? out;
        ctl(c).stop().then((t) => out = t);
        speech.finalResult(akhir); // final sesudah stop: hanya segmen akhir
        fa.flushMicrotasks();
        fa.elapse(DictationController.finalizeTimeout);
        expect(out, '$awal $tengah $akhir');
        c.dispose();
      });
    });

    test('segmen bertanda tapi partial tetap kumulatif → tidak dobel', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        say(awal);
        speech.segment(awal);
        speech.partial('$awal terus');
        speech.partial('$awal $tengah');
        speech.finalResult('$awal $tengah $akhir');
        expect(st(c).committed, '$awal $tengah $akhir');
        c.dispose();
      });
    });

    test('partial kumulatif tapi final hanya segmen terakhir', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        say('$awal $tengah $akhir');
        speech.finalResult(akhir);
        expect(st(c).committed, '$awal $tengah $akhir');
        c.dispose();
      });
    });

    test('final memperbaiki kata partial (revisi biasa) tetap satu kali', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        speech.partial('di');
        speech.partial('disana');
        speech.partial('di sana ada');
        speech.partial('Di sana ada kepasar');
        speech.finalResult('Di sana ada ke pasar.');
        expect(st(c).committed, 'Di sana ada ke pasar.');
        c.dispose();
      });
    });

    test('3+ sesi dengan event terlambat, final kosong, done ganda', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        // sesi 1: final normal
        say(awal);
        speech.finalResult(awal);
        expect(st(c).phase, DictationPhase.restarting);
        fa.elapse(DictationController.restartDelay); // cancel → listen baru
        // final sesi 1 dikirim ulang saat sesi lama ditutup
        speech.staleResult(awal, isFinal: true);
        speech.staleResult(awal);
        // sesi 2: partial mulai ulang di tengah sesi, final kosong
        say(tengah);
        say(akhir);
        speech.finalResult('');
        speech.endSession(); // done ganda sesi 2
        speech.emitStatus(SpeechSessionStatus.done);
        fa.elapse(DictationController.restartDelay);
        // sesi 3: berakhir tanpa final, final terlambat datang sesudahnya
        say('lalu kirim');
        speech.endSession();
        speech.finalResult('lalu kirim ya');
        fa.elapse(DictationController.restartDelay);
        // sesi 4: partial lama (sesi 3) terlambat lalu kata baru
        speech.staleResult('lalu kirim ya');
        say('oke');
        String? out;
        ctl(c).stop().then((t) => out = t);
        fa.flushMicrotasks();
        fa.elapse(DictationController.finalizeTimeout);
        expect(out, '$awal $tengah $akhir lalu kirim ya oke');
        expect(st(c).committed, out);
        c.dispose();
      });
    });

    test('committed tidak pernah menyusut selama dikte', () {
      fakeAsync((fa) {
        final c = makeContainer();
        var longest = 0;
        c.listen(dictationControllerProvider, (_, n) {
          expect(n.committed.length, greaterThanOrEqualTo(longest));
          longest = n.committed.length;
        });
        ctl(c).start();
        fa.flushMicrotasks();
        for (var i = 0; i < 3; i++) {
          say(awal);
          say(akhir);
          speech.finalResult(akhir);
          speech.endSession();
          fa.elapse(DictationController.restartDelay);
          speech.staleResult('$awal $akhir', isFinal: true);
        }
        ctl(c).stop();
        fa.flushMicrotasks();
        fa.elapse(DictationController.finalizeTimeout);
        expect(st(c).committed, '$awal $akhir $awal $akhir $awal $akhir');
        expect(
          RegExp('jenisnya').allMatches(st(c).committed).length,
          3,
          reason: st(c).committed,
        );
        c.dispose();
      });
    });

    test('log dikte: panjang committed per sesi, segmen, event basi', () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();
        say(awal);
        say(akhir);
        speech.finalResult(akhir);
        fa.elapse(DictationController.restartDelay);
        speech.staleResult(akhir, isFinal: true);
        ctl(c).stop();
        fa.flushMicrotasks();
        fa.elapse(DictationController.finalizeTimeout);
        final text = log.toText();
        expect(text, contains('segmen'));
        expect(text, contains('total 0→11 kata'));
        expect(text, contains('abaikan'));
        // privasi: tidak ada kata ucapan di log
        expect(text, isNot(contains('jenisnya')));
        c.dispose();
      });
    });
  });

  group('transcript helpers', () {
    test('transcriptContinues', () {
      expect(transcriptContinues('', 'apa saja'), isTrue);
      expect(transcriptContinues('beli susu', 'Beli susu dan roti'), isTrue);
      expect(transcriptContinues('ke', 'kemarin aku'), isTrue);
      expect(transcriptContinues('di sana ada', 'Disana ada banyak'), isTrue);
      expect(
        transcriptContinues('aku mau ke pasar', 'aku mau ke pasar dan beli'),
        isTrue,
      );
      expect(
        transcriptContinues('saya mau ke pasar', 'Aku mau ke pasar'),
        isTrue,
      );
      expect(transcriptContinues('oke', 'jenisnya'), isFalse);
      expect(
        transcriptContinues('aku mau ke pasar beli sayur', 'aku juga'),
        isFalse,
      );
      expect(
        transcriptContinues(
          'aku mau ke pasar beli sayur',
          'aku juga mau beli ikan',
        ),
        isFalse,
      );
    });

    test('transcriptTail', () {
      expect(transcriptTail('', 'a b'), 'a b');
      expect(transcriptTail('satu dua', 'Satu dua, tiga empat'), 'tiga empat');
      expect(transcriptTail('satu dua tiga', 'dua tiga empat'), 'empat');
      expect(transcriptTail('satu dua', 'tiga'), 'tiga');
      expect(transcriptTail('halo', 'halo apa kabar'), 'apa kabar');
      expect(transcriptTail('satu dua', 'satu dua'), '');
      // satu kata kebetulan sama bukan tumpang tindih
      expect(transcriptTail('aku pergi dan', 'dan pulang'), 'dan pulang');
    });
  });
}
