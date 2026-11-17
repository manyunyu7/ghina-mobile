import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/dictation_channels.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/notes/widgets/speech_model_sheet.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

const _missing = SpeechAvailability(
  recognizerAvailable: true,
  offline: OfflineSpeechSupport.downloadable,
);
const _installed = SpeechAvailability(
  recognizerAvailable: true,
  offline: OfflineSpeechSupport.installed,
);

void main() {
  late FakeSpeechTranscriber speech;
  late List<MethodCall> calls;
  late String downloadAnswer;
  const channel = MethodChannel(ChannelSpeechModelInstaller.channelName);

  setUp(() {
    speech = FakeSpeechTranscriber(available: _missing);
    calls = [];
    downloadAnswer = 'progress';
  });

  Future<ProviderContainer> pump(WidgetTester t, Widget child) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'download' => downloadAnswer,
        'openSettings' => 'google_offline',
        _ => null,
      };
    });
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await t.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          speechTranscriberProvider.overrideWithValue(speech),
          speechModelInstallerProvider.overrideWith(
            (ref) => ChannelSpeechModelInstaller(),
          ),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    return ProviderScope.containerOf(t.element(find.byType(Scaffold)));
  }

  /// The native side calling into Dart (ModelDownloadListener callbacks).
  Future<void> native(WidgetTester t, String method, [Object? args]) async {
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      ChannelSpeechModelInstaller.channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    await t.pump();
    await t.pump();
  }

  Future<void> resume(WidgetTester t) async {
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
    await t.pump();
    await t.pump();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pump();
    await t.pump();
  }

  testWidgets('missing → download → progress → ready', (t) async {
    await pump(t, const SpeechModelPanel());
    expect(
      find.text('Paket suara Indonesia belum ada di HP ini'),
      findsOneWidget,
    );
    expect(find.textContaining('50–80 MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('speech-model-online')), findsOneWidget);

    await tapKey(t, 'dictation-download');
    expect(calls.single.method, 'download');
    expect(calls.single.arguments, {'locale': 'id-ID'});
    expect(find.byKey(const ValueKey('speech-model-progress')), findsOneWidget);

    await native(t, 'progress', {'percent': 42});
    expect(find.textContaining('42%'), findsOneWidget);
    final bar = t.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('speech-model-progress')),
    );
    expect(bar.value, closeTo(0.42, 0.001));

    speech.available = _installed;
    await native(t, 'success');
    expect(find.text('Siap dipakai offline ✓'), findsOneWidget);
    expect(find.byKey(const ValueKey('speech-model-start')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('scheduled (waiting for Wi-Fi) is explained', (t) async {
    await pump(t, const SpeechModelPanel());
    await tapKey(t, 'dictation-download');
    await native(t, 'scheduled');
    expect(find.text('Unduhan dijadwalkan'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsWidgets);
    expect(find.byKey(const ValueKey('speech-model-online')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('error → settings fallback with steps; back → ready', (t) async {
    await pump(t, const SpeechModelPanel());
    await tapKey(t, 'dictation-download');
    await native(t, 'error', {'code': 5});
    expect(find.text('Unduh dari app belum bisa'), findsOneWidget);
    expect(find.byKey(const ValueKey('speech-model-steps')), findsOneWidget);

    await tapKey(t, 'speech-model-settings');
    expect(calls.map((c) => c.method), ['download', 'openSettings']);
    expect(find.textContaining('Buka tab "Semua"'), findsOneWidget);

    // The user downloads it there and comes back.
    speech.available = _installed;
    await resume(t);
    expect(find.text('Siap dipakai offline ✓'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Android 13 (no progress) polls until installed', (t) async {
    downloadAnswer = 'triggered';
    await pump(t, const SpeechModelPanel());
    await tapKey(t, 'dictation-download');
    expect(find.textContaining('Meminta Android'), findsOneWidget);
    speech.available = _installed;
    await t.pump(SpeechModelController.pollEvery);
    await t.pump();
    expect(find.text('Siap dipakai offline ✓'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"Pakai online dulu" allows the online recognizer', (t) async {
    bool? result;
    final c = await pump(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showSpeechModelSheet(context),
          child: const Text('buka'),
        ),
      ),
    );
    expect(c.read(dictationAllowsNetworkProvider), isFalse);
    await t.tap(find.text('buka'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await tapKey(t, 'speech-model-online');
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(result, isTrue);
    expect(c.read(dictationAllowsNetworkProvider), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('settings tile: Belum diunduh — Unduh / Siap', (t) async {
    await pump(t, const DictationOfflineTile());
    expect(find.textContaining('Belum diunduh'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dictation-offline-download')),
      findsOneWidget,
    );
    speech.available = _installed;
    await resume(t); // nothing listens here: refresh by reopening
    await t.pumpWidget(const SizedBox());
    await pump(t, const DictationOfflineTile());
    expect(find.textContaining('Siap ✓'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dictation-offline-download')),
      findsNothing,
    );
    await t.pumpWidget(const SizedBox());
  });
}
