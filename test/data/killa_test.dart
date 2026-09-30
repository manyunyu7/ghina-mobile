// Killa (docs/killa.md "Mobile API"): JSON parsing, error mapping, the
// repository over a fake Dio adapter and the pure chat helpers.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/killa_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/killa_wire.dart';
import 'package:ghina/data/platform/killa_media_picker_impl.dart'
    show killaCompressTarget;
import 'package:ghina/data/repositories/killa_repository_impl.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

class _Tokens implements TokenStore {
  @override
  Future<String?> readToken() async => 'tok';
  @override
  Future<void> writeToken(String? token) async {}
  @override
  Future<String?> readUser() async => null;
  @override
  Future<void> writeUser(String? userJson) async {}
  @override
  Future<void> clear() async {}
}

/// Answers requests from a route table; records what was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);

  final Map<String, (int, Object?)> Function(RequestOptions o) routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    final key = '${o.method} ${o.path}';
    final (status, body) =
        routes(o)[key] ?? (404, {'error': 'not found: $key'});
    if (body is Uint8List) {
      return ResponseBody.fromBytes(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _msg(
  String id, {
  String role = 'assistant',
  String body = 'Halo',
  String createdAt = '2026-10-01T02:00:00.000Z',
  String channel = 'app',
  List<Object?> attachments = const [],
  String? model = 'sonnet',
}) => {
  'id': id,
  'role': role,
  'body': body,
  'model': model,
  'createdAt': createdAt,
  'channel': channel,
  'attachments': attachments,
};

({RemoteKillaRepository repo, _Adapter adapter}) _repo(
  Map<String, (int, Object?)> Function(RequestOptions o) routes,
) {
  final adapter = _Adapter(routes);
  final client = ApiClient(baseUrl: 'https://x.test', tokens: _Tokens());
  client.dio.httpClientAdapter = adapter;
  return (repo: RemoteKillaRepository(DioKillaApi(client)), adapter: adapter);
}

void main() {
  group('wire', () {
    test('messages: roles, WA channel, attachments by source', () {
      final page = killaChatPageFromWire({
        'messages': [
          _msg(
            '1',
            role: 'user',
            body: 'lihat ini',
            attachments: [
              {
                'path': '/uploads/a.jpg',
                'name': 'a.jpg',
                'kind': 'image',
                'source': 'upload',
              },
            ],
          ),
          _msg(
            '2',
            channel: 'wa',
            attachments: [
              {
                'path': 'out/report.pdf',
                'name': 'report.pdf',
                'kind': 'file',
                'source': 'engine',
              },
            ],
          ),
          _msg('3', role: 'system', body: '', model: null),
          {'role': 'user'}, // no id → skipped
        ],
        'nextBefore': 'cursor-1',
      });
      expect(page.nextBefore, 'cursor-1');
      expect(page.messages.map((m) => m.id), ['1', '2', '3']);
      final user = page.messages[0];
      expect(user.role, KillaRole.user);
      expect(user.attachments.single.isImage, isTrue);
      expect(user.attachments.single.fromEngine, isFalse);
      final reply = page.messages[1];
      expect(reply.channel, KillaChannel.wa);
      expect(reply.model, 'sonnet');
      expect(reply.attachments.single.fromEngine, isTrue);
      expect(reply.attachments.single.isPdf, isTrue);
      expect(page.messages[2].role, KillaRole.system);
      expect(page.messages[2].model, isNull);
      expect(page.messages[0].createdAt.toUtc(), DateTime.utc(2026, 10, 1, 2));
    });

    test('nextBefore null = start reached; garbage is tolerated', () {
      expect(killaChatPageFromWire({'messages': []}).nextBefore, isNull);
      expect(killaChatPageFromWire(null).messages, isEmpty);
      expect(killaChatPageFromWire('oops').messages, isEmpty);
    });

    test('reminders: nextAt epoch ms, numeric ids, soonest first', () {
      final list = killaRemindersFromWire({
        'reminders': [
          {
            'id': 7,
            'spec': 'daily 20:00',
            'text': 'Obat',
            'nextAt': 1790000000000,
          },
          {'id': 3, 'spec': 'once', 'text': 'Telepon', 'nextAt': 1780000000000},
        ],
      });
      expect(list.map((r) => r.id), ['3', '7']);
      expect(
        list.first.nextAt,
        DateTime.fromMillisecondsSinceEpoch(1780000000000),
      );
      expect(list.last.spec, 'daily 20:00');
    });

    test('files: dirs first then files by name; commits; file', () {
      final dir = killaDirFromWire({
        'path': 'notes',
        'entries': [
          {'name': 'b.md', 'type': 'file', 'size': 12},
          {'name': 'Zeta', 'type': 'dir', 'size': 0},
          {'name': 'a.txt', 'type': 'file', 'size': 3},
          {'name': 'alpha', 'type': 'dir'},
        ],
      });
      expect(dir.path, 'notes');
      expect(dir.entries.map((e) => e.name), [
        'alpha',
        'Zeta',
        'a.txt',
        'b.md',
      ]);
      expect(dir.entries.last.size, 12);
      final f = killaFileFromWire({'path': 'notes/b.md', 'content': '# Hi'});
      expect(f.isMarkdown, isTrue);
      final commits = killaCommitsFromWire({
        'commits': [
          {
            'hash': 'abcdef1234567',
            'date': '2026-10-01T01:00:00Z',
            'author': 'Killa',
            'subject': 'Update notes',
          },
        ],
      });
      expect(commits.single.shortHash, 'abcdef1');
      expect(commits.single.author, 'Killa');
    });

    test('usage: days sorted, per-model totals, cost estimate', () {
      final u = killaUsageFromWire({
        'since': '2026-09-02',
        'days': [
          {
            'date': '2026-10-01',
            'turns': 3,
            'inputTokens': 100,
            'outputTokens': 50,
            'cacheReadTokens': 1000,
            'cacheCreationTokens': 10,
            'costUsd': 0.42,
          },
          {'date': '2026-09-30', 'turns': 1, 'costUsd': 0.1},
        ],
        'byModel': {
          'sonnet': {'turns': 4, 'costUsd': 0.52, 'inputTokens': 100},
        },
        'total': {'turns': 4, 'costUsd': 0.52, 'outputTokens': 50},
      });
      expect(u.days.map((d) => d.date), ['2026-09-30', '2026-10-01']);
      expect(u.days.last.totals.totalTokens, 1160);
      expect(u.byModel['sonnet']!.costUsd, 0.52);
      expect(u.total.turns, 4);
    });

    test('outgoing media is base64 JSON', () {
      final j = killaMediaToWire(
        KillaOutgoingMedia(
          name: 'a.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(j, {
        'name': 'a.jpg',
        'mimeType': 'image/jpeg',
        'dataBase64': 'AQID',
      });
    });
  });

  group('errors', () {
    KillaException status(int code, [Object? body]) => mapKillaError(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: code,
          data: body ?? {'error': 'e$code'},
        ),
      ),
    );

    test('status codes map to kinds', () {
      expect(
        status(403, {'error': 'forbidden'}).kind,
        KillaErrorKind.forbidden,
      );
      expect(status(503).kind, KillaErrorKind.engineOff);
      expect(status(504).kind, KillaErrorKind.timeout);
      expect(status(502).kind, KillaErrorKind.engineError);
      expect(status(413).kind, KillaErrorKind.tooLarge);
      expect(status(415).kind, KillaErrorKind.unsupported);
      expect(status(400, {'error': 'text too long'}).message, 'text too long');
      expect(status(401).kind, KillaErrorKind.unauthorized);
      expect(status(500).kind, KillaErrorKind.unknown);
    });

    test('client timeouts and offline', () {
      KillaException of(DioExceptionType t) => mapKillaError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: t,
        ),
      );
      expect(of(DioExceptionType.receiveTimeout).kind, KillaErrorKind.timeout);
      expect(of(DioExceptionType.connectionError).kind, KillaErrorKind.network);
      expect(of(DioExceptionType.unknown).kind, KillaErrorKind.network);
    });
  });

  group('repository', () {
    test('chat: query params, bearer token, parsed page', () async {
      final r = _repo(
        (o) => {
          'GET /api/mobile/killa/chat': (
            200,
            {
              'messages': [_msg('m1')],
              'nextBefore': null,
            },
          ),
        },
      );
      final page = await r.repo.chat(before: 'c9', limit: 50);
      expect(page.messages.single.id, 'm1');
      final req = r.adapter.requests.single;
      expect(req.queryParameters, {'limit': 50, 'before': 'c9'});
      expect(req.headers['Authorization'], 'Bearer tok');
    });

    test('send: body shape and a long receive timeout', () async {
      final r = _repo(
        (o) => {
          'POST /api/mobile/killa/chat': (
            200,
            {
              'userMessage': _msg('u', role: 'user', body: 'hai'),
              'reply': _msg('a', body: '**Halo**'),
            },
          ),
        },
      );
      final res = await r.repo.send(
        text: 'hai',
        model: KillaModel.opus,
        media: [
          KillaOutgoingMedia(
            name: 'x.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([37, 80, 68, 70]),
          ),
        ],
      );
      expect(res.reply.body, '**Halo**');
      final req = r.adapter.requests.single;
      final data = req.data as Map;
      expect(data['text'], 'hai');
      expect(data['model'], 'opus');
      expect((data['media'] as List).single['dataBase64'], 'JVBERg==');
      expect(
        req.receiveTimeout,
        greaterThanOrEqualTo(const Duration(minutes: 6)),
      );
    });

    test('403 → forbidden KillaException', () async {
      final r = _repo(
        (o) => {
          'GET /api/mobile/killa/usage': (403, {'error': 'forbidden'}),
        },
      );
      await expectLater(
        r.repo.usage(),
        throwsA(
          isA<KillaException>().having(
            (e) => e.kind,
            'kind',
            KillaErrorKind.forbidden,
          ),
        ),
      );
    });

    test('file 413 / 415 are friendly kinds', () async {
      final r = _repo(
        (o) => {
          'GET /api/mobile/killa/file': o.queryParameters['path'] == 'big.bin'
              ? (413, {'error': 'too large'})
              : (415, {'error': 'not text'}),
        },
      );
      await expectLater(
        r.repo.readFile('big.bin'),
        throwsA(
          isA<KillaException>().having(
            (e) => e.kind,
            'kind',
            KillaErrorKind.tooLarge,
          ),
        ),
      );
      await expectLater(
        r.repo.readFile('img.png'),
        throwsA(
          isA<KillaException>().having(
            (e) => e.kind,
            'kind',
            KillaErrorKind.unsupported,
          ),
        ),
      );
    });

    test(
      'write, commit (hash / nothing), cancel reminder (numeric id)',
      () async {
        String? hash = 'abc1234';
        final r = _repo(
          (o) => {
            'PUT /api/mobile/killa/file': (200, {'ok': true, 'path': 'a.md'}),
            'POST /api/mobile/killa/commit': (200, {'ok': true, 'hash': hash}),
            'POST /api/mobile/killa/reminders/cancel': (200, {'ok': false}),
            'POST /api/mobile/killa/chat/new': (
              200,
              {
                'divider': _msg(
                  'd',
                  role: 'system',
                  body: 'Sesi baru',
                  model: null,
                ),
              },
            ),
          },
        );
        await r.repo.writeFile('a.md', '# x');
        expect(r.adapter.requests.last.data, {
          'path': 'a.md',
          'content': '# x',
        });
        expect(await r.repo.commit(message: 'pesan'), 'abc1234');
        expect(r.adapter.requests.last.data, {'message': 'pesan'});
        hash = null; // nothing to commit
        expect(await r.repo.commit(), isNull);
        expect(await r.repo.cancelReminder('12'), isFalse);
        expect(r.adapter.requests.last.data, {'id': 12});
        final divider = await r.repo.newSession();
        expect(divider.role, KillaRole.system);
      },
    );

    test('media: raw bytes + content type', () async {
      final png = Uint8List.fromList([137, 80, 78, 71]);
      final r = _repo((o) => {'GET /api/mobile/killa/media': (200, png)});
      final f = await r.repo.media('out/chart.png');
      expect(f.bytes, png);
      expect(f.isImage, isTrue);
      expect(r.adapter.requests.single.queryParameters, {
        'path': 'out/chart.png',
      });
    });
  });

  group('use cases & helpers', () {
    KillaMessage m(String id, DateTime at, [String body = '']) =>
        KillaMessage(id: id, role: KillaRole.user, body: body, createdAt: at);

    test('mergeKillaMessages: dedupe by id, oldest first, incoming wins', () {
      final t = DateTime(2026, 10, 1, 9);
      final merged = mergeKillaMessages(
        [m('b', t.add(const Duration(minutes: 1))), m('a', t, 'old')],
        [m('a', t, 'new'), m('c', t.add(const Duration(minutes: 2)))],
      );
      expect(merged.map((x) => x.id), ['a', 'b', 'c']);
      expect(merged.first.body, 'new');
    });

    test('SendKillaMessage validates before calling the API', () {
      final r = _repo((o) => {});
      final send = SendKillaMessage(r.repo);
      expect(
        () => send(text: '   '),
        throwsA(
          isA<KillaException>().having(
            (e) => e.kind,
            'kind',
            KillaErrorKind.invalid,
          ),
        ),
      );
      expect(
        () => send(text: 'x' * (killaTextMax + 1)),
        throwsA(isA<KillaException>()),
      );
      final four = List.generate(
        4,
        (i) => KillaOutgoingMedia(
          name: '$i.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List(1),
        ),
      );
      expect(
        () => send(text: 'hi', media: four),
        throwsA(isA<KillaException>()),
      );
      expect(r.adapter.requests, isEmpty);
    });

    test('photo compress target puts the long side at ≤ 2048', () {
      // Equal min width/height = scaled short side → long side lands on 2048.
      expect(killaCompressTarget(4000, 3000), 1536);
      expect(killaCompressTarget(3000, 4000), 1536);
      expect(killaCompressTarget(1200, 800), 800); // already small: no scaling
      expect(killaCompressTarget(8000, 2000), 512);
    });
  });
}
