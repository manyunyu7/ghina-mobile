import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/attach_picker.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_notifier.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_tray.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploader.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploads.dart';

/// Daemon stand-in with several uploads: each `POST …/uploads` opens `uN`
/// whose attachment is `attN`. Files whose name starts with `rusak` are refused.
class _Daemon implements HttpClientAdapter {
  final opened = <Map<String, dynamic>>[];
  final delivered = <Map<String, dynamic>>[];
  var _n = 0;
  final _names = <String, String>{};
  bool deliverOk = true;

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
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.path;
    if (o.method == 'POST' && path.endsWith('/uploads')) {
      final d = Map<String, dynamic>.from(o.data as Map);
      if ('${d['name']}'.startsWith('rusak')) {
        return _json({'error': 'Ditolak'}, 400);
      }
      opened.add(d);
      final id = 'u${++_n}';
      _names[id] = '${d['name']}';
      return _json({'id': id, 'offset': 0, 'chunk': 1 << 20});
    }
    if (o.method == 'PUT' && path.startsWith('/api/uploads/')) {
      if (body != null) {
        await for (final _ in body) {}
      }
      final id = path.split('/').last;
      // the last chunk carries the attachment id, like the real daemon
      return _json({
        'offset': 4,
        'done': true,
        'attachment': {'id': 'att${id.substring(1)}'},
      });
    }
    if (o.method == 'GET' && path.startsWith('/api/uploads/')) {
      final id = path.split('/').last;
      return _json({
        'offset': 4,
        'done': true,
        'attachment': {'id': 'att${id.substring(1)}'},
      });
    }
    if (o.method == 'POST' && path.endsWith('/attachments/deliver')) {
      delivered.add(Map<String, dynamic>.from(o.data as Map));
      return _json({'delivered': deliverOk, 'text': 'x'});
    }
    return _json({'error': 'tidak ada'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;
  late _Daemon daemon;
  late KantorUploader uploader;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('kantor_batch_');
    daemon = _Daemon();
    uploader = KantorUploader(
      Dio(BaseOptions(baseUrl: 'http://daemon.test'))
        ..httpClientAdapter = daemon,
      backoff: (_) => Duration.zero,
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  PickedAttachment file(String name) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync([1, 2, 3, 4]);
    return PickedAttachment(f, name, 'text/plain');
  }

  ProviderContainer container() {
    final c = ProviderContainer(
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
    addTearDown(c.dispose);
    c.listen(kantorUploadsProvider, (_, _) {});
    return c;
  }

  group('held upload and delivery', () {
    test(
      'defer is sent when opening, and the attachment id is read back',
      () async {
        final f = File('${tmp.path}/a.txt')..writeAsBytesSync([1, 2, 3, 4]);
        final job = UploadJob(
          id: 'j',
          sid: 's1',
          agent: 'Rara',
          path: f.path,
          name: 'a.txt',
          size: 4,
          mime: 'text/plain',
          defer: true,
        );
        final id = await uploader.upload(job);
        expect(daemon.opened.single['defer'], isTrue);
        expect(await uploader.attachmentIdOf(id), 'att1');
      },
    );

    test('a normal upload does not ask the daemon to hold it', () async {
      final f = File('${tmp.path}/a.txt')..writeAsBytesSync([1, 2, 3, 4]);
      await uploader.upload(
        UploadJob(
          id: 'j',
          sid: 's1',
          agent: 'Rara',
          path: f.path,
          name: 'a.txt',
          size: 4,
          mime: 'text/plain',
        ),
      );
      expect(daemon.opened.single.containsKey('defer'), isFalse);
    });

    test('job JSON keeps defer and attachment id across a restart', () {
      final j = UploadJob(
        id: 'j',
        sid: 's',
        agent: 'a',
        path: '/p',
        name: 'n',
        size: 1,
        mime: 'x/y',
        defer: true,
        attachmentId: 'att9',
      );
      final back = UploadJob.fromJson(j.toJson());
      expect(back.defer, isTrue);
      expect(back.attachmentId, 'att9');
      expect(
        UploadJob.fromJson({...j.toJson()}..remove('defer')).defer,
        isFalse,
      );
    });

    test(
      'sendBatch uploads every file held, then delivers ONE message',
      () async {
        final q = container().read(kantorUploadsProvider.notifier);
        final r = await q.sendBatch(
          sid: 's1',
          agent: 'Rara',
          files: [file('a.txt'), file('b.txt')],
          text: 'Tolong cek dua file ini',
        );
        expect(r.sent, 2);
        expect(r.failed, 0);
        expect(r.delivered, isTrue);
        expect(daemon.opened.every((d) => d['defer'] == true), isTrue);
        expect(daemon.delivered, hasLength(1));
        expect(daemon.delivered.single, {
          'ids': ['att1', 'att2'],
          'text': 'Tolong cek dua file ini',
        });
      },
    );

    test('a refused file is left out, the rest still goes', () async {
      final q = container().read(kantorUploadsProvider.notifier);
      final r = await q.sendBatch(
        sid: 's1',
        agent: 'Rara',
        files: [file('rusak.txt'), file('b.txt')],
        text: 'catatan',
      );
      expect(r.sent, 1);
      expect(r.failed, 1);
      expect(daemon.delivered.single['ids'], ['att1']);
    });

    test('when nothing arrives nothing is delivered', () async {
      final q = container().read(kantorUploadsProvider.notifier);
      final r = await q.sendBatch(
        sid: 's1',
        agent: 'Rara',
        files: [file('rusak.txt')],
        text: 'catatan',
      );
      expect(r.sent, 0);
      expect(r.delivered, isFalse);
      expect(daemon.delivered, isEmpty);
    });

    test('the daemon could not type it: delivered false, files stay', () async {
      daemon.deliverOk = false;
      final q = container().read(kantorUploadsProvider.notifier);
      final r = await q.sendBatch(
        sid: 's1',
        agent: 'Rara',
        files: [file('a.txt')],
        text: '',
      );
      expect(r.sent, 1);
      expect(r.delivered, isFalse);
    });
  });

  group('tray', () {
    Future<void> pumpTray(
      WidgetTester t,
      List<StagedFile> items,
      void Function(StagedFile) onRemove,
    ) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                const Spacer(),
                AttachmentTray(items: items, onRemove: onRemove),
              ],
            ),
          ),
        ),
      );
    }

    StagedFile staged(int i, {String mime = 'text/plain'}) => StagedFile(
      'f$i',
      PickedAttachment(File('/tmp/tidak-ada-$i.txt'), 'berkas-$i.txt', mime),
    );

    testWidgets('empty tray draws nothing', (t) async {
      await pumpTray(t, const [], (_) {});
      expect(find.byKey(const ValueKey('attachment-tray')), findsNothing);
    });

    testWidgets('shows each file with its name and a count line', (t) async {
      await pumpTray(t, [staged(1), staged(2), staged(3)], (_) {});
      expect(find.text('3 file · tulis konteksnya lalu Kirim'), findsOneWidget);
      expect(find.text('berkas-1.txt'), findsOneWidget);
      expect(find.text('TXT'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('tray-remove-f2')), findsOneWidget);
    });

    testWidgets('the remove button takes one file out', (t) async {
      final items = [staged(1), staged(2)];
      late List<StagedFile> now;
      now = items;
      void remove(StagedFile f) => now = [
        for (final x in now)
          if (x != f) x,
      ];
      await pumpTray(t, items, remove);
      await t.tap(find.byKey(const ValueKey('tray-remove-f1')));
      expect([for (final f in now) f.key], ['f2']);
    });

    testWidgets('20 files fit 360dp: the tray scrolls sideways, no overflow', (
      t,
    ) async {
      await pumpTray(t, [
        for (var i = 0; i < maxStagedFiles; i++) staged(i),
      ], (_) {});
      expect(
        find.text('20 file · tulis konteksnya lalu Kirim'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('an image that cannot be read shows an icon, not a crash', (
      t,
    ) async {
      await pumpTray(t, [staged(1, mime: 'image/png')], (_) {});
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
