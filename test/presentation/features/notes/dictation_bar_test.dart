import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/diagnostics/dictation_log.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/notes/widgets/dictation_bar.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

void main() {
  testWidgets('shows listening + mm:ss, silence warning, Lanjutkan', (t) async {
    final speech = FakeSpeechTranscriber();
    final audio = FakeDictationAudio();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          speechTranscriberProvider.overrideWithValue(speech),
          microphonePermissionProvider.overrideWithValue(
            FakeMicrophonePermission(),
          ),
          dictationAudioProvider.overrideWithValue(audio),
          dictationLogProvider.overrideWithValue(DictationLog.memory()),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) =>
                  ref.watch(dictationControllerProvider).isActive
                  ? DictationBar(onStop: () {}, onCancel: () {})
                  : TextButton(
                      onPressed: () => ref
                          .read(dictationControllerProvider.notifier)
                          .start(),
                      child: const Text('mulai'),
                    ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('mulai'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Mendengarkan…'), findsOneWidget);
    expect(find.textContaining('00:00'), findsOneWidget);

    await t.pump(const Duration(seconds: 65));
    expect(find.textContaining('01:05'), findsOneWidget);

    // A restart between sessions doesn't change the label (no blinking).
    speech.error(SpeechErrorKind.noMatch);
    await t.pump();
    expect(find.textContaining('Mendengarkan…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 50));

    await t.pump(const Duration(seconds: 55)); // 2 min without voice
    expect(
      find.text('Masih mendengarkan? Dikte berhenti dalam 10 dtk'),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 3));
    expect(find.textContaining('dalam 7 dtk'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dictation-keep')));
    await t.pump();
    expect(
      find.byKey(const ValueKey('dictation-silence-warning')),
      findsNothing,
    );
    expect(find.byType(DictationBar), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    expect(audio.calls, ['mute', 'unmute']);
  });
}
