import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/stt_speech_transcriber.dart';
import 'package:ghina/domain/services/services.dart';

/// SttSpeechTranscriber against a scripted "native" side of the
/// `speech_to_text` method channel (Android).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  var hasPermission = false;
  Future<void> Function()? onCancel;

  /// Native → Dart callback, like the plugin's `channel.invokeMethod`.
  Future<void> native(String method, Object? args) =>
      messenger.handlePlatformMessage(
        ch.name,
        ch.codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  /// resultType: 0 partial, 1 intermediate (partial with `final_result`),
  /// 2 final.
  String result(String words, int type) => jsonEncode({
    'alternates': [
      {'recognizedWords': words, 'confidence': 0.9},
    ],
    'resultType': type,
  });

  setUp(() {
    calls.clear();
    onCancel = null;
    messenger.setMockMethodCallHandler(ch, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'has_permission':
          return hasPermission;
        case 'initialize':
          return true;
        case 'listen':
          await native('notifyStatus', 'listening');
          return true;
        case 'cancel':
          await onCancel?.call();
          return true;
      }
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(ch, null));

  // Runs first: the plugin is a singleton that stays initialised.
  test('no mic permission → the plugin never asks by itself', () async {
    hasPermission = false;
    final t = SttSpeechTranscriber(useBluetooth: false);
    await expectLater(
      t.start(preferOffline: false),
      throwsA(
        isA<SpeechError>().having(
          (e) => e.kind,
          'kind',
          SpeechErrorKind.permission,
        ),
      ),
    );
    expect(calls, isNot(contains('initialize')));
    expect(calls, isNot(contains('listen')));
  });

  test(
    'segment end + late result of the cancelled session are tagged',
    () async {
      hasPermission = true;
      final t = SttSpeechTranscriber(useBluetooth: false);
      final got = <TranscriptUpdate>[];
      final sub = t.results.listen(got.add);

      await t.start(preferOffline: false);
      expect(calls, containsAllInOrder(['initialize', 'listen']));
      await native('textRecognition', result('satu dua', 0));
      await native('textRecognition', result('satu dua', 1));
      expect(got.map((r) => (r.text, r.segmentEnd, r.stale)), [
        ('satu dua', false, false),
        ('satu dua', true, false),
      ]);

      // Restart: the old session's final shows up while it is being closed.
      onCancel = () => native('textRecognition', result('satu dua tiga', 2));
      await t.start(preferOffline: false);
      await native('textRecognition', result('empat', 0));
      expect(got.skip(2).map((r) => (r.text, r.isFinal, r.stale)), [
        ('satu dua tiga', true, true),
        ('empat', false, false),
      ]);
      await sub.cancel();
    },
  );
}
