import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/diagnostics/dictation_log.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/chat_dictation.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

/// Kotak ketik chat + tombol mic + ChatDictation, disambungkan seperti di
/// ChatTab (Kirim mengirim isi kotak ketik).
class _Composer extends ConsumerStatefulWidget {
  const _Composer(this.input, this.sent);

  final TextEditingController input;
  final List<String> sent;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  late final ChatDictation d = ChatDictation(
    ref: ref,
    context: () => context,
    text: widget.input,
    onSend: () async => widget.sent.add(widget.input.text),
  );

  @override
  void dispose() {
    d.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dictationControllerProvider.select((s) => s.isActive));
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextField(key: const ValueKey('field'), controller: widget.input),
        IconButton(
          key: const ValueKey('kantor-mic'),
          onPressed: d.toggle,
          icon: const Icon(Icons.mic_rounded),
        ),
      ],
    );
  }
}

/// Fold 8 Ultra posisi meja (disederhanakan): engsel mendatar di y 370..380.
const _hinge = DisplayFeature(
  bounds: Rect.fromLTWH(0, 370, 830, 10),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

void main() {
  late FakeSpeechTranscriber speech;
  late FakeMicrophonePermission mic;
  late DictationLog log;
  late TextEditingController input;
  late List<String> sent;

  Future<void> pump(
    WidgetTester t, {
    String text = '',
    List<DisplayFeature> features = const [],
  }) async {
    speech = FakeSpeechTranscriber();
    log = DictationLog.memory();
    sent = [];
    input = TextEditingController(text: text);
    addTearDown(input.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          speechTranscriberProvider.overrideWithValue(speech),
          microphonePermissionProvider.overrideWithValue(mic),
          dictationAudioProvider.overrideWithValue(FakeDictationAudio()),
          dictationLogProvider.overrideWithValue(log),
          dictationAllowsNetworkProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(displayFeatures: features),
            child: child!,
          ),
          home: Scaffold(body: _Composer(input, sent)),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey(key)));
    await settle(t);
  }

  String status(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('dict-status'))).data!;

  String live(WidgetTester t) => t
      .widget<Text>(find.byKey(const ValueKey('dict-text')))
      .textSpan!
      .toPlainText();

  /// Partial kumulatif kata demi kata (satu segmen).
  void say(String words) {
    final w = words.split(' ');
    for (var i = 1; i <= w.length; i++) {
      speech.partial(w.take(i).join(' '));
    }
  }

  Future<void> restart(WidgetTester t) =>
      t.pump(DictationController.restartDelay * 2);

  final sheet = find.byKey(const ValueKey('dict-sheet'));

  setUp(() => mic = FakeMicrophonePermission());

  group('pop-up dikte', () {
    const awal = 'aku udah ngomong panjang lebar soal kartu';
    const tengah = 'terus tombolnya harus dipindah ke atas';
    const akhir = 'jenisnya yang diklik tadi';
    const semua = '$awal $tengah $akhir lalu kirim ke tim makasih';

    /// Dikte 4 sesi dengan urutan event realistis (lihat
    /// dictation_controller_test: bug "bagian akhirnya doang").
    Future<void> dictate(WidgetTester t, {bool saidFirst = false}) async {
      // sesi 1: partial mulai ulang per segmen, final hanya segmen terakhir
      if (!saidFirst) say(awal);
      say(tengah);
      speech.finalResult(tengah);
      await restart(t);
      // sesi 2: final sesi 1 terlambat, final kosong, done ganda
      speech.staleResult(tengah, isFinal: true);
      say(akhir);
      speech.finalResult('');
      speech.endSession();
      speech.emitStatus(SpeechSessionStatus.done);
      await restart(t);
      // sesi 3: partial kumulatif, final hanya kata terakhir
      say('lalu kirim ke tim');
      speech.finalResult('ke tim');
      await restart(t);
      // sesi 4: masih bicara saat Selesai / Kirim
      say('makasih');
      await t.pump();
    }

    testWidgets('teks live (committed + partial) lalu Selesai: SEMUA kata '
        'masuk ke kotak ketik, teks lama tetap', (t) async {
      await pump(t, text: 'Catatan:');
      await tapKey(t, 'kantor-mic');
      expect(sheet, findsOneWidget);
      expect(status(t), 'Mendengarkan…');
      expect(speech.starts, 1);

      say(awal);
      await t.pump();
      expect(live(t), awal); // masih partial
      await dictate(t, saidFirst: true);
      expect(speech.starts, 4);
      expect(live(t), semua);
      expect(input.text, 'Catatan:'); // belum masuk selama pop-up terbuka

      await tapKey(t, 'dict-done');
      expect(sheet, findsNothing);
      expect(input.text, 'Catatan: $semua');
      expect(sent, isEmpty);
      final line = log.entries.firstWhere((e) => e.event == 'kotak ketik');
      expect(line.detail, 'selesai · 22 kata masuk · kotak 23 kata');
    });

    testWidgets('Kirim memasukkan lalu langsung mengirim', (t) async {
      await pump(t);
      await tapKey(t, 'kantor-mic');
      await dictate(t);
      await tapKey(t, 'dict-send');
      expect(sheet, findsNothing);
      expect(sent, [semua]);
    });

    testWidgets('Batal tidak mengubah kotak ketik', (t) async {
      await pump(t, text: 'draf');
      await tapKey(t, 'kantor-mic');
      await dictate(t);
      await tapKey(t, 'dict-cancel');
      expect(sheet, findsNothing);
      expect(input.text, 'draf');
      expect(speech.calls, contains('cancel'));
    });

    testWidgets('tombol kembali dengan teks → konfirmasi singkat', (t) async {
      await pump(t, text: 'draf');
      await tapKey(t, 'kantor-mic');
      say(awal);
      await t.pump();
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('Buang teks dikte?'), findsOneWidget);
      await t.tap(find.text('LANJUT DIKTE'));
      await settle(t);
      expect(sheet, findsOneWidget);
      expect(status(t), 'Mendengarkan…');

      await t.binding.handlePopRoute();
      await settle(t);
      await t.tap(find.text('BUANG'));
      await settle(t);
      expect(sheet, findsNothing);
      expect(input.text, 'draf');
    });

    testWidgets('Selesai menyisipkan di posisi kursor', (t) async {
      await pump(t);
      input.value = const TextEditingValue(
        text: 'tolong cek ya',
        selection: TextSelection.collapsed(offset: 10),
      );
      await tapKey(t, 'kantor-mic');
      say('kartu yang tadi');
      speech.finalResult('kartu yang tadi');
      await t.pump();
      await tapKey(t, 'dict-done');
      expect(input.text, 'tolong cek kartu yang tadi ya');
    });

    testWidgets('restart sesi singkat tanpa "Menyambung…"; diam → Jeda', (
      t,
    ) async {
      await pump(t);
      await tapKey(t, 'kantor-mic');
      speech.finalResult('halo');
      await t.pump();
      expect(status(t), isNot('Menyambung…'));
      await restart(t);
      expect(status(t), 'Mendengarkan…');
      await t.pump(const Duration(seconds: 5));
      expect(status(t), 'Jeda — lanjut bicara');
      say('lanjut lagi');
      await t.pump();
      expect(status(t), 'Mendengarkan…');
    });
  });

  group('izin mikrofon di dalam pop-up', () {
    testWidgets('pertama kali: penjelasan → izin sistem → langsung dengar', (
      t,
    ) async {
      mic
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.granted;
      await pump(t);
      await tapKey(t, 'kantor-mic');
      expect(sheet, findsOneWidget);
      expect(status(t), 'Izinkan mikrofon dulu');
      expect(speech.starts, 0);
      await tapKey(t, 'mic-allow');
      expect(mic.requests, 1);
      expect(speech.starts, 1); // tanpa ketuk mic lagi
      expect(status(t), 'Mendengarkan…');
      expect(find.byType(ChunkyDialog), findsNothing); // tanpa dialog lain
    });

    testWidgets('ditolak → pesan + Coba lagi → diizinkan → mulai', (t) async {
      mic
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.denied;
      await pump(t);
      await tapKey(t, 'kantor-mic');
      await tapKey(t, 'mic-allow');
      expect(status(t), 'Mikrofon belum diizinkan');
      expect(find.byKey(const ValueKey('mic-retry')), findsOneWidget);
      expect(mic.requests, 1);
      expect(speech.starts, 0);
      mic.afterRequest = MicPermissionStatus.granted;
      await tapKey(t, 'mic-retry');
      expect(mic.requests, 2);
      expect(speech.starts, 1);
      expect(status(t), 'Mendengarkan…');
    });

    testWidgets('ditolak permanen → Buka pengaturan app → kembali → mulai', (
      t,
    ) async {
      mic.current = MicPermissionStatus.permanentlyDenied;
      await pump(t);
      await tapKey(t, 'kantor-mic');
      expect(status(t), 'Mikrofon masih diblokir');
      expect(mic.requests, 0); // percuma: sistem tidak menampilkan apa pun
      await tapKey(t, 'mic-settings');
      expect(mic.settingsOpened, 1);
      expect(speech.starts, 0);

      mic.current = MicPermissionStatus.granted; // diizinkan di Pengaturan
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await settle(t);
      expect(speech.starts, 1);
      expect(mic.requests, 0);
      expect(status(t), 'Mendengarkan…');
    });

    testWidgets('kembali dari Pengaturan masih diblokir → pesan jelas', (
      t,
    ) async {
      mic.current = MicPermissionStatus.permanentlyDenied;
      await pump(t);
      await tapKey(t, 'kantor-mic');
      await tapKey(t, 'mic-settings');
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await settle(t);
      expect(speech.starts, 0);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('dict-permit'))).data,
        contains('masih belum diizinkan'),
      );
      expect(find.byKey(const ValueKey('mic-settings')), findsOneWidget);
    });

    testWidgets('"jangan tanya lagi" di dialog sistem → tombol pengaturan', (
      t,
    ) async {
      mic
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.permanentlyDenied;
      await pump(t);
      await tapKey(t, 'kantor-mic');
      await tapKey(t, 'mic-allow');
      expect(status(t), 'Mikrofon masih diblokir');
      expect(find.byKey(const ValueKey('mic-settings')), findsOneWidget);
      expect(mic.requests, 1);
    });

    testWidgets('"Hanya kali ini" habis → dicek ulang saat dibuka lagi', (
      t,
    ) async {
      await pump(t);
      await tapKey(t, 'kantor-mic');
      await tapKey(t, 'dict-cancel');
      expect(speech.starts, 1);
      mic
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.granted;
      await tapKey(t, 'kantor-mic');
      expect(status(t), 'Izinkan mikrofon dulu');
      await tapKey(t, 'mic-allow');
      expect(speech.starts, 2);
    });

    testWidgets('paket suara offline belum ada → sheet unduh dari pop-up', (
      t,
    ) async {
      await pump(t);
      speech.available = const SpeechAvailability(
        recognizerAvailable: true,
        offline: OfflineSpeechSupport.downloadable,
      );
      await tapKey(t, 'kantor-mic');
      expect(find.byKey(const ValueKey('dictation-download')), findsOneWidget);
      expect(speech.starts, 0);
    });
  });

  group('tata letak', () {
    Future<void> longDictation(WidgetTester t) async {
      await tapKey(t, 'kantor-mic');
      for (var i = 0; i < 12; i++) {
        say('kalimat panjang nomor $i untuk menguji gulir teks dikte');
        speech.finalResult('kalimat panjang nomor $i untuk menguji gulir');
        await restart(t);
      }
      say('masih bicara');
      await settle(t);
      expect(t.takeException(), isNull);
      expect(t.getSize(sheet).width, lessThanOrEqualTo(560));
      expect(live(t), endsWith('masih bicara'));
    }

    testWidgets('mode meja Fold (engsel mendatar) tanpa overflow', (t) async {
      t.view.physicalSize = const Size(830, 750);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pump(t, features: const [_hinge]);
      await longDictation(t);
      await tapKey(t, 'dict-done');
      expect(input.text, contains('nomor 11'));
    });

    testWidgets('layar lebar / dua panel tanpa overflow', (t) async {
      t.view.physicalSize = const Size(1600, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pump(t);
      await longDictation(t);
    });

    testWidgets('layar sempit (layar luar) tanpa overflow', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pump(t);
      await longDictation(t);
    });
  });
}
