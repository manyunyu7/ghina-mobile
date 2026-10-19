// Statement import ("Impor mutasi", `/api/mobile/statements`): JSON parsing
// against the contract shapes, request bodies and error mapping over a fake
// Dio adapter. Names and numbers below are made up.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/statement_wire.dart';
import 'package:ghina/data/repositories/statement_repository_impl.dart';
import 'package:ghina/domain/entities/entities.dart';

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

class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);

  final Map<String, (int, Object?)> routes;
  final requests = <RequestOptions>[];
  DioExceptionType? failWith;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    if (failWith != null) {
      throw DioException(requestOptions: o, type: failWith!);
    }
    final key = '${o.method} ${o.path}';
    final (status, body) = routes[key] ?? (404, {'error': 'not found: $key'});
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _base = '/api/mobile/statements';

({ApiStatementRepository repo, _Adapter adapter}) _repo(
  Map<String, (int, Object?)> routes,
) {
  final adapter = _Adapter(routes);
  final client = ApiClient(baseUrl: 'https://x.test', tokens: _Tokens());
  client.dio.httpClientAdapter = adapter;
  return (repo: ApiStatementRepository(client), adapter: adapter);
}

Map<String, Object?> importJson({
  String id = 'i1',
  String status = 'ready',
  String? error,
}) => {
  'id': id,
  'fileName': 'mutasi-oktober.pdf',
  'status': status,
  'error': error,
  'walletId': 'w1',
  'wallet': 'Rekening Utama',
  'bank': 'BCA',
  'accountLast4': '1234',
  'periodFrom': '2026-10-01',
  'periodTo': '2026-10-31',
  'summary': '3 transaksi, 1 mungkin dobel.',
  'createdAt': '2026-10-19T01:00:00.000Z',
  'updatedAt': '2026-10-19T01:02:00.000Z',
  'counts': {
    'total': 3,
    'new': 1,
    'duplicate': 1,
    'uncertain': 1,
    'pending': 3,
    'approved': 0,
    'ignored': 0,
  },
};

Map<String, Object?> rowJson(
  String id, {
  String verdict = 'new',
  String type = 'expense',
  String status = 'pending',
  Map<String, Object?>? duplicateOf,
  String? toWalletId,
}) => {
  'id': id,
  'importId': 'i1',
  'idx': 0,
  'date': '2026-10-05T05:00:00.000Z',
  'type': type,
  'amount': 45000,
  'description': 'KARTU DEBIT WARUNG MAKAN',
  'note': 'Makan siang',
  'walletId': 'w1',
  'toWalletId': toWalletId,
  'categoryId': 'c1',
  'verdict': verdict,
  'duplicateOfId': duplicateOf?['id'],
  'reason': verdict == 'new' ? null : 'Nominal dan tanggal sama',
  'status': status,
  'transactionId': null,
  'wallet': 'Rekening Utama',
  'toWallet': toWalletId == null ? null : 'Dompet Tunai',
  'category': 'Makan',
  'duplicateOf': duplicateOf,
};

TypeMatcher<StatementException> _kind(StatementErrorKind k) =>
    isA<StatementException>().having((e) => e.kind, 'kind', k);

void main() {
  group('wire parsing', () {
    test('ImportSummary with counts', () {
      final i = statementImportFromWire(importJson())!;
      expect(i.id, 'i1');
      expect(i.status, StatementStatus.ready);
      expect(i.bank, 'BCA');
      expect(i.accountLast4, '1234');
      expect(i.wallet, 'Rekening Utama');
      expect(i.periodFrom, DateTime(2026, 10, 1));
      expect(i.periodTo, DateTime(2026, 10, 31));
      expect(i.summary, contains('mungkin dobel'));
      expect(i.counts.total, 3);
      expect(i.counts.newRows, 1);
      expect(i.counts.uncertain, 1);
      expect(i.counts.pending, 3);
    });

    test('unknown status falls back to failed; missing id drops the item', () {
      expect(
        statementImportFromWire(importJson(status: 'weird'))!.status,
        StatementStatus.failed,
      );
      expect(statementImportFromWire({'fileName': 'x.pdf'}), isNull);
      expect(
        statementImportsFromWire({
          'imports': [importJson(), 'oops', <String, Object?>{}],
        }),
        hasLength(1),
      );
    });

    test('row with the matching transaction', () {
      final r = statementRowFromWire(
        rowJson(
          'r1',
          verdict: 'uncertain',
          duplicateOf: {
            'id': 't1',
            'date': '2026-10-05T04:00:00.000Z',
            'type': 'expense',
            'amount': 45000,
            'note': 'Makan',
            'wallet': 'Rekening Utama',
          },
        ),
      )!;
      expect(r.verdict, StatementVerdict.uncertain);
      expect(r.type, TxType.expense);
      expect(r.amount, 45000);
      expect(r.title, 'Makan siang');
      expect(r.reason, 'Nominal dan tanggal sama');
      expect(r.duplicateOf!.id, 't1');
      expect(r.duplicateOf!.note, 'Makan');
      expect(r.pending, isTrue);
    });

    test('transfer row and a vanished duplicate', () {
      final r = statementRowFromWire(
        rowJson('r2', type: 'transfer', toWalletId: 'w2', verdict: 'duplicate'),
      )!;
      expect(r.type, TxType.transfer);
      expect(r.toWallet, 'Dompet Tunai');
      expect(r.duplicateOf, isNull);
    });

    test('title falls back to the statement line; bad rows are dropped', () {
      final j = rowJson('r3')..['note'] = null;
      expect(statementRowFromWire(j)!.title, 'KARTU DEBIT WARUNG MAKAN');
      expect(statementRowFromWire({'id': 'x'}), isNull);
      final d = statementDetailFromWire({
        'import': importJson(),
        'rows': [
          rowJson('r1'),
          {'nope': 1},
        ],
      })!;
      expect(d.rows, hasLength(1));
      expect(statementDetailFromWire({'rows': []}), isNull);
    });

    test('upload body carries the password only when given', () {
      final withPw = statementUploadToWire(
        const StatementUpload(
          name: 'a.pdf',
          bytes: [1, 2, 3],
          walletId: 'w1',
          password: 'rahasia',
        ),
      );
      expect(withPw['name'], 'a.pdf');
      expect(withPw['dataBase64'], base64Encode([1, 2, 3]));
      expect(withPw['walletId'], 'w1');
      expect(withPw['password'], 'rahasia');
      final plain = statementUploadToWire(
        const StatementUpload(name: 'a.pdf', bytes: [1]),
      );
      expect(plain.containsKey('password'), isFalse);
      expect(plain.containsKey('walletId'), isFalse);
    });

    test('row patch sends only changed fields; clearCategory sends null', () {
      final w = statementRowPatchToWire(
        StatementRowPatch(
          date: DateTime.utc(2026, 10, 6, 5),
          amount: 50000,
          note: 'Kopi',
        ),
      );
      expect(w, {
        'date': '2026-10-06T05:00:00.000Z',
        'amount': 50000.0,
        'note': 'Kopi',
      });
      final c = statementRowPatchToWire(
        const StatementRowPatch(type: TxType.transfer, clearCategory: true),
      );
      expect(c, {'type': 'transfer', 'categoryId': null});
    });
  });

  group('repository', () {
    test('list and detail', () async {
      final r = _repo({
        'GET $_base': (
          200,
          {
            'imports': [importJson(), importJson(id: 'i2', status: 'parsing')],
          },
        ),
        'GET $_base/i1': (
          200,
          {
            'import': importJson(),
            'rows': [rowJson('r1'), rowJson('r2', verdict: 'duplicate')],
          },
        ),
      });
      final list = await r.repo.list();
      expect(list.map((i) => i.status), [
        StatementStatus.ready,
        StatementStatus.parsing,
      ]);
      final d = await r.repo.detail('i1');
      expect(d.rows.map((x) => x.id), ['r1', 'r2']);
      expect(r.adapter.requests.first.headers['Authorization'], 'Bearer tok');
    });

    test('upload posts the base64 body with long timeouts', () async {
      final r = _repo({
        'POST $_base': (201, {'import': importJson(status: 'parsing')}),
      });
      final created = await r.repo.upload(
        const StatementUpload(name: 'a.pdf', bytes: [37, 80, 68, 70]),
      );
      expect(created.status, StatementStatus.parsing);
      final req = r.adapter.requests.single;
      expect((req.data as Map)['dataBase64'], base64Encode([37, 80, 68, 70]));
      expect(req.sendTimeout, const Duration(minutes: 2));
      expect(req.receiveTimeout, const Duration(minutes: 2));
    });

    test('upload over 10 MB is refused before sending', () async {
      final r = _repo({});
      await expectLater(
        r.repo.upload(
          StatementUpload(
            name: 'besar.pdf',
            bytes: Uint8List(statementMaxBytes + 1),
          ),
        ),
        throwsA(_kind(StatementErrorKind.tooLarge)),
      );
      expect(r.adapter.requests, isEmpty);
    });

    test('password_required / password_wrong are told apart', () async {
      final r = _repo({
        'POST $_base': (422, {'error': 'password_required'}),
      });
      const up = StatementUpload(name: 'a.pdf', bytes: [1]);
      await expectLater(
        r.repo.upload(up),
        throwsA(_kind(StatementErrorKind.passwordRequired)),
      );
      final w = _repo({
        'POST $_base': (422, {'error': 'password_wrong'}),
      });
      await expectLater(
        w.repo.upload(up),
        throwsA(_kind(StatementErrorKind.passwordWrong)),
      );
      final other = _repo({
        'POST $_base': (422, {'error': 'bukan_pdf'}),
      });
      await expectLater(
        other.repo.upload(up),
        throwsA(_kind(StatementErrorKind.invalid)),
      );
    });

    test('403 killa_forbidden, 404, 409, 401, 500, offline', () async {
      Future<Object?> status(int code, [Object? body]) async {
        final r = _repo({'GET $_base': (code, body)});
        try {
          await r.repo.list();
        } catch (e) {
          return e;
        }
        return null;
      }

      expect(
        await status(403, {'error': 'killa_forbidden'}),
        _kind(StatementErrorKind.forbidden),
      );
      expect(await status(404), _kind(StatementErrorKind.notFound));
      expect(await status(409), _kind(StatementErrorKind.conflict));
      expect(await status(401), _kind(StatementErrorKind.unauthorized));
      expect(await status(500), _kind(StatementErrorKind.unknown));

      final off = _repo({})
        ..adapter.failWith = DioExceptionType.connectionError;
      await expectLater(
        off.repo.list(),
        throwsA(_kind(StatementErrorKind.network)),
      );
    });

    test('retry 409 while a run is in progress', () async {
      final r = _repo({
        'POST $_base/i1/retry': (409, {'error': 'in_progress'}),
      });
      await expectLater(
        r.repo.retry('i1'),
        throwsA(_kind(StatementErrorKind.conflict)),
      );
    });

    test('editRow, approve, ignore, delete', () async {
      final r = _repo({
        'PATCH $_base/rows/r1': (200, {'row': rowJson('r1')}),
        'POST $_base/i1/approve': (
          200,
          {
            'created': 2,
            'transactionIds': ['t1', 't2'],
            'import': importJson(),
          },
        ),
        'POST $_base/i1/ignore': (200, {'import': importJson()}),
        'DELETE $_base/i1': (200, {'ok': true}),
      });
      final row = await r.repo.editRow(
        'r1',
        const StatementRowPatch(amount: 1000),
      );
      expect(row.id, 'r1');
      expect(await r.repo.approve('i1', ['r1', 'r2']), 2);
      await r.repo.ignore('i1', ['r3']);
      await r.repo.delete('i1');
      final bodies = {
        for (final q in r.adapter.requests) '${q.method} ${q.path}': q.data,
      };
      expect(bodies['PATCH $_base/rows/r1'], {'amount': 1000.0});
      expect(bodies['POST $_base/i1/approve'], {
        'rowIds': ['r1', 'r2'],
      });
      expect(bodies['POST $_base/i1/ignore'], {
        'rowIds': ['r3'],
      });
    });

    test('editing a row that is no longer pending → conflict', () async {
      final r = _repo({
        'PATCH $_base/rows/r1': (409, {'error': 'not_pending'}),
      });
      await expectLater(
        r.repo.editRow('r1', const StatementRowPatch(amount: 1)),
        throwsA(_kind(StatementErrorKind.conflict)),
      );
    });

    test('an unreadable answer is an unknown error, not a crash', () async {
      final r = _repo({
        'GET $_base/i1': (200, {'oops': true}),
      });
      await expectLater(
        r.repo.detail('i1'),
        throwsA(_kind(StatementErrorKind.unknown)),
      );
    });
  });
}
