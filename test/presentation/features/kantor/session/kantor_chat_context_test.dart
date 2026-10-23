import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_notifier.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploader.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploads.dart';
import 'package:ghina/presentation/features/kantor/session/chat_context.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QuietUploads extends KantorUploads {
  @override
  List<UploadJob> build() => [];
}

class _RecordingUploader extends KantorUploader {
  _RecordingUploader(String url)
    : super(
        Dio(
          BaseOptions(
            baseUrl: url,
            headers: {'Authorization': 'Bearer account'},
          ),
        ),
      );
  final sent = <UploadJob>[];
  Completer<void>? hold;
  @override
  Future<String> upload(
    UploadJob job, {
    void Function(String)? onOpened,
    void Function(int, int)? onProgress,
    CancelToken? cancel,
  }) async {
    sent.add(job);
    await hold?.future;
    return 'uploaded';
  }
}

void main() {
  const a = KantorConfig(baseUrl: 'https://a.test', token: 'account');
  const b = KantorConfig(baseUrl: 'https://b.test', token: 'account');

  test(
    'connection and conversation identities isolate server/account/office/session',
    () {
      expect(kantorConnectionKey(a), isNot(kantorConnectionKey(b)));
      expect(
        kantorConnectionKey(a),
        isNot(
          kantorConnectionKey(
            const KantorConfig(baseUrl: 'https://a.test', token: 'other'),
          ),
        ),
      );
      expect(
        kantorConnectionKey(a),
        kantorConnectionKey(
          const KantorConfig(baseUrl: 'https://a.test/', token: 'account'),
        ),
      );
      expect(kantorConnectionKey(a), isNot(contains('account')));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final memory = c.read(kantorChatMemoryProvider);
      final key = (
        connection: kantorConnectionKey(a),
        office: 'o',
        sid: 'same',
      );
      memory[key] = KantorChatMemory()
        ..draft = const TextEditingValue(text: 'draft')
        ..scrollOffset = 240;
      expect(c.read(kantorChatMemoryProvider)[key]!.scrollOffset, 240);
      expect(
        memory[(connection: kantorConnectionKey(b), office: 'o', sid: 'same')],
        isNull,
      );
      expect(
        memory[(connection: key.connection, office: 'other', sid: 'same')],
        isNull,
      );
    },
  );

  testWidgets(
    'draft follows its original complex even when office and sid match',
    (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var config = a;
      final c = ProviderContainer(
        overrides: [
          kantorApiProvider.overrideWith((ref) => KantorApi(config)),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
          kantorUploadsProvider.overrideWith(_QuietUploads.new),
        ],
      );
      addTearDown(c.dispose);
      final feed = KantorOfficeFeed('same-office', null)
        ..loading = false
        ..office = {
          'sessions': [
            {'sid': 'same', 'status': 'idle', 'tmux': 't'},
          ],
        };
      addTearDown(feed.dispose);
      Future<void> show(KantorConfig next) async {
        config = next;
        c.invalidate(kantorApiProvider);
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: GhinaTheme.light(),
              home: Scaffold(
                body: KantorChatTab(
                  key: ValueKey(kantorConnectionKey(next)),
                  feed: feed,
                  sid: 'same',
                ),
              ),
            ),
          ),
        );
        await t.pump();
      }

      await show(a);
      await t.enterText(find.byType(EditableText), 'pesan kompleks A');
      await show(b);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      await t.enterText(find.byType(EditableText), 'pesan kompleks B');
      await show(a);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        'pesan kompleks A',
      );
      await show(b);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        'pesan kompleks B',
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  test(
    'queued files stay with their origin while a previous upload is running',
    () async {
      final tmp = await Directory.systemTemp.createTemp('ghina_complex_queue_');
      addTearDown(() async => tmp.delete(recursive: true));
      final source = File('${tmp.path}/source.txt')..writeAsStringSync('hello');
      final first = _RecordingUploader(a.baseUrl)..hold = Completer<void>();
      final second = _RecordingUploader(b.baseUrl);
      KantorUploader current = first;
      final c = ProviderContainer(
        overrides: [
          kantorOutboxDirProvider.overrideWithValue(Future.value(tmp)),
          kantorUploaderProvider.overrideWith((ref) => current),
          kantorUploadNotifierProvider.overrideWithValue(
            const NoUploadNotifier(),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(kantorUploadsProvider, (_, _) {});
      final queue = c.read(kantorUploadsProvider.notifier);
      Future<UploadJob> enqueue(String name, {String? connection}) =>
          queue.enqueue(
            sid: 'same',
            agent: 'Sari',
            source: source,
            name: name,
            mime: 'text/plain',
            connection: connection,
            office: 'same-office',
          );
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(done(), isTrue);
      }

      await enqueue('a1.txt');
      await until(() => first.sent.length == 1);
      final pendingA = await enqueue('a2.txt');
      current = second;
      c.invalidate(kantorUploaderProvider);
      await c.pump();
      await expectLater(
        enqueue('stale-picker.txt', connection: kantorConnectionKey(a)),
        throwsA(isA<UploadFailure>()),
      );
      await enqueue('b1.txt');
      first.hold!.complete();
      await until(() => second.sent.length == 1);
      expect(first.sent.map((j) => j.name), ['a1.txt']);
      expect(second.sent.map((j) => j.name), ['b1.txt']);
      expect(
        c
            .read(kantorUploadsProvider)
            .firstWhere((j) => j.id == pendingA.id)
            .status,
        UploadStatus.queued,
      );
      current = first;
      c.invalidate(kantorUploaderProvider);
      await c.pump();
      await until(() => first.sent.length == 2);
      expect(first.sent.last.name, 'a2.txt');
      final json = pendingA.toJson();
      expect(json.toString(), isNot(contains('account')));
      expect(UploadJob.fromJson(json).connection, kantorConnectionKey(a));
    },
  );
}
