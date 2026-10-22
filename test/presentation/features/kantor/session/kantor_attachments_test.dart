import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_model.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_notifier.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploader.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploads.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_views.dart';
import 'package:ghina/presentation/features/kantor/session/chat_model.dart';

/// A tiny stand-in for the daemon's upload protocol.
class FakeDaemon implements HttpClientAdapter {
  FakeDaemon({this.chunk = 100});

  final int chunk;
  final received = <int>[];
  Map<String, dynamic>? opened;
  final puts = <int>[]; // offsets of every PUT that reached the server
  int opens = 0;

  /// Called before a PUT is handled; throw to simulate a drop. `n` counts PUTs.
  void Function(int n, RequestOptions o)? onPut;
  int _n = 0;
  int? statusOnPut;

  ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (options.method == 'POST' && path.endsWith('/uploads')) {
      opens++;
      opened = Map<String, dynamic>.from(options.data as Map);
      received.clear();
      return _json({'id': 'u1', 'offset': 0, 'chunk': chunk});
    }
    if (options.method == 'GET' && path == '/api/uploads/u1') {
      return _json({
        'offset': received.length,
        'size': opened?['size'],
        'done': received.length == opened?['size'],
      });
    }
    if (options.method == 'PUT' && path == '/api/uploads/u1') {
      onPut?.call(++_n, options);
      if (statusOnPut != null) {
        return _json({'error': 'Terlalu besar'}, statusOnPut!);
      }
      final offset = int.parse('${options.headers['Upload-Offset']}');
      final body = <int>[];
      if (requestStream != null) {
        await for (final c in requestStream) {
          body.addAll(c);
        }
      }
      if (offset != received.length) {
        return _json({'error': 'offset', 'offset': received.length}, 409);
      }
      puts.add(offset);
      received.addAll(body);
      return _json({
        'offset': received.length,
        'done': received.length == opened!['size'],
      });
    }
    return _json({'error': 'tidak ada'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

DioException drop(RequestOptions o) =>
    DioException(requestOptions: o, type: DioExceptionType.connectionError);

void main() {
  late Directory tmp;
  late File source;
  late FakeDaemon daemon;
  late KantorUploader uploader;
  final bytes = List<int>.generate(450, (i) => i % 251);

  UploadJob job({String? uploadId}) => UploadJob(
    id: 'j1',
    sid: 's1',
    agent: 'Rara',
    path: source.path,
    name: 'bukti.png',
    size: bytes.length,
    mime: 'image/png',
    caption: 'lihat ini',
    uploadId: uploadId,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('kantor_att_');
    source = File('${tmp.path}/src.bin')..writeAsBytesSync(bytes);
    daemon = FakeDaemon();
    uploader = KantorUploader(
      Dio(BaseOptions(baseUrl: 'http://daemon.test'))
        ..httpClientAdapter = daemon,
      backoff: (_) => Duration.zero,
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  group('KantorUploader', () {
    test('sends the file in chunks with name, mime and caption', () async {
      final progress = <int>[];
      final id = await uploader.upload(
        job(),
        onProgress: (s, t) => progress.add(s),
      );
      expect(id, 'u1');
      expect(daemon.received, bytes);
      expect(daemon.puts, [0, 100, 200, 300, 400]);
      expect(daemon.opened, {
        'name': 'bukti.png',
        'size': 450,
        'mime': 'image/png',
        'caption': 'lihat ini',
      });
      expect(progress.last, 450);
    });

    test(
      'a dropped connection resumes from the server offset, not from zero',
      () async {
        daemon.onPut = (n, o) {
          if (n == 3) throw drop(o); // third piece never reaches the server
        };
        await uploader.upload(job());
        expect(daemon.received, bytes);
        expect(daemon.opens, 1);
        // 0,100 landed; 200 failed once and was sent again
        expect(daemon.puts, [0, 100, 200, 300, 400]);
      },
    );

    test('resumes a saved upload id after the app was killed', () async {
      // the process "dies" on the third piece: no retries, the server keeps 200 bytes
      daemon.onPut = (n, o) {
        if (n == 3) throw drop(o);
      };
      final dying = KantorUploader(
        Dio(BaseOptions(baseUrl: 'http://daemon.test'))
          ..httpClientAdapter = daemon,
        maxTries: 0,
        backoff: (_) => Duration.zero,
      );
      await dying.upload(job()).then((_) {}, onError: (_) {});
      final partial = daemon.received.length;
      expect(partial, 200);

      final fresh = KantorUploader(
        Dio(BaseOptions(baseUrl: 'http://daemon.test'))
          ..httpClientAdapter = daemon,
        backoff: (_) => Duration.zero,
      );
      daemon.onPut = null;
      daemon.puts.clear();
      await fresh.upload(job(uploadId: 'u1'));
      expect(daemon.opens, 1, reason: 'no new upload opened');
      expect(daemon.puts.first, partial);
      expect(daemon.received, bytes);
    });

    test(
      'gives up after the retries run out, with a readable message',
      () async {
        daemon.onPut = (n, o) => throw drop(o);
        final u = KantorUploader(
          Dio(BaseOptions(baseUrl: 'http://daemon.test'))
            ..httpClientAdapter = daemon,
          maxTries: 2,
          backoff: (_) => Duration.zero,
        );
        await expectLater(
          u.upload(job()),
          throwsA(
            isA<UploadFailure>().having(
              (e) => uploadErrorText(e),
              'text',
              'Koneksi ke Kantor terputus.',
            ),
          ),
        );
      },
    );

    test('a refusal from the daemon fails at once with its message', () async {
      daemon.statusOnPut = 413;
      await expectLater(
        uploader.upload(job()),
        throwsA(
          isA<UploadFailure>().having(
            (e) => e.message,
            'message',
            'Terlalu besar',
          ),
        ),
      );
      expect(daemon.puts, isEmpty);
    });

    test('a missing source file fails without touching the network', () async {
      source.deleteSync();
      await expectLater(uploader.upload(job()), throwsA(isA<UploadFailure>()));
      expect(daemon.opens, 0);
    });

    test('an empty file still completes', () async {
      source.writeAsBytesSync(const []);
      final empty = UploadJob(
        id: 'e',
        sid: 's1',
        agent: 'Rara',
        path: source.path,
        name: 'k.txt',
        size: 0,
        mime: 'text/plain',
      );
      await uploader.upload(empty);
      expect(daemon.opens, 1);
      expect(daemon.received, isEmpty);
    });
  });

  group('queue (KantorUploads)', () {
    test(
      'runs jobs in order, copies the file into the outbox and lands as done',
      () async {
        final container = ProviderContainer(
          overrides: [
            kantorOutboxDirProvider.overrideWithValue(
              Future.value(Directory('${tmp.path}/outbox')..createSync()),
            ),
            kantorUploaderProvider.overrideWithValue(uploader),
            kantorUploadNotifierProvider.overrideWithValue(
              const NoUploadNotifier(),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen(kantorUploadsProvider, (_, _) {});
        final q = container.read(kantorUploadsProvider.notifier);
        final j = await q.enqueue(
          sid: 's1',
          agent: 'Rara',
          source: source,
          name: 'a.bin',
          mime: 'application/octet-stream',
        );
        expect(j.path, isNot(source.path));
        for (var i = 0; i < 100; i++) {
          if (container
              .read(kantorUploadsProvider)
              .any((x) => x.status == UploadStatus.done))
            break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(
          container.read(kantorUploadsProvider).single.status,
          UploadStatus.done,
        );
        expect(daemon.received, bytes);
        expect(
          File(j.path).existsSync(),
          isFalse,
          reason: 'outbox copy is cleaned up',
        );
      },
    );

    test(
      'a failed job stays for "Coba lagi" and finishes after retry',
      () async {
        var fail = true;
        daemon.statusOnPut = 500;
        final u = KantorUploader(
          Dio(BaseOptions(baseUrl: 'http://daemon.test'))
            ..httpClientAdapter = daemon,
          maxTries: 0,
          backoff: (_) => Duration.zero,
        );
        final container = ProviderContainer(
          overrides: [
            kantorOutboxDirProvider.overrideWithValue(
              Future.value(Directory('${tmp.path}/outbox2')..createSync()),
            ),
            kantorUploaderProvider.overrideWithValue(u),
            kantorUploadNotifierProvider.overrideWithValue(
              const NoUploadNotifier(),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen(kantorUploadsProvider, (_, _) {});
        final q = container.read(kantorUploadsProvider.notifier);
        final j = await q.enqueue(
          sid: 's1',
          agent: 'Rara',
          source: source,
          name: 'a.bin',
          mime: 'application/octet-stream',
        );
        Future<void> until(UploadStatus s) async {
          for (var i = 0; i < 150; i++) {
            if (container.read(kantorUploadsProvider).any((x) => x.status == s))
              return;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }

        await until(UploadStatus.failed);
        expect(
          container.read(kantorUploadsProvider).single.status,
          UploadStatus.failed,
        );
        fail = false;
        daemon.statusOnPut = null;
        q.retry(j.id);
        await until(UploadStatus.done);
        expect(
          container.read(kantorUploadsProvider).single.status,
          UploadStatus.done,
        );
        expect(daemon.received, bytes);
        expect(fail, isFalse);
      },
    );
  });

  group('attachments in the stream', () {
    test('parses the loose daemon shape', () {
      final list = parseAttachments({
        'items': [
          {
            'id': 'a1',
            'name': 'x.png',
            'mime': 'image/png',
            'size': 10,
            'dir': 'out',
            'agent': 'Rara',
            'at': '2026-10-21T10:00:00Z',
          },
          {
            'id': 'a2',
            'name': 'v.mp4',
            'mime': 'video/mp4',
            'from': 'owner',
            'created_at': 1790000000000,
          },
          {'id': 'a3', 'name': 'r.pdf', 'mime': 'application/pdf'},
        ],
      });
      expect(list.map((a) => a.kind), [
        AttachmentKind.image,
        AttachmentKind.video,
        AttachmentKind.file,
      ]);
      expect(list.map((a) => a.mine), [false, true, false]);
      expect(list[1].at, isNotEmpty);
      expect(list[0].thumbPath, '/api/attachments/a1/thumb');
      expect(
        parseAttachments([
          {'id': 'z', 'name': 'n'},
        ]),
        hasLength(1),
      );
      expect(parseAttachments(null), isEmpty);
    });

    test('interleaves by time with messages', () {
      final entries = <ChatEntry>[
        const UserEntry('satu', '2026-10-21T10:00:00Z'),
        const ClaudeEntry('dua', '2026-10-21T10:10:00Z'),
      ];
      KantorAttachment att(String id, String at) => KantorAttachment.fromJson({
        'id': id,
        'name': id,
        'mime': 'image/png',
        'at': at,
      });
      final out = mergeAttachments(entries, [
        att('late', '2026-10-21T10:20:00Z'),
        att('mid', '2026-10-21T10:05:00Z'),
        att('early', '2026-10-21T09:00:00Z'),
      ]);
      expect(
        out.map(
          (e) => switch (e) {
            AttachmentEntry() => e.item.id,
            UserEntry() => e.text,
            ClaudeEntry() => e.text,
            _ => '?',
          },
        ),
        ['early', 'satu', 'mid', 'dua', 'late'],
      );
    });

    testWidgets(
      'upload bubble shows progress and offers retry/cancel when failed',
      (t) async {
        var retried = 0, cancelled = 0;
        Widget host(UploadJob j) => MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: UploadBubble(
              job: j,
              onRetry: () => retried++,
              onCancel: () => cancelled++,
            ),
          ),
        );
        final j = UploadJob(
          id: 'x',
          sid: 's',
          agent: 'Rara',
          path: '/x',
          name: 'film.mp4',
          size: 1000,
          mime: 'video/mp4',
          sent: 450,
          status: UploadStatus.uploading,
        );
        await t.pumpWidget(host(j));
        expect(find.text('Mengunggah 45%'), findsOneWidget);
        expect(find.text('Coba lagi'), findsNothing);
        await t.pumpWidget(
          host(
            j.copyWith(
              status: UploadStatus.failed,
              error: 'Koneksi ke Kantor terputus.',
            ),
          ),
        );
        await t.tap(find.text('Coba lagi'));
        await t.tap(find.text('Buang'));
        expect((retried, cancelled), (1, 1));
      },
    );
  });
}
