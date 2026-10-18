// Email (Gmail read-only, `/api/mobile/email`): JSON parsing against the
// contract shapes, error mapping, the repository over a fake Dio adapter and
// the use cases' local checks.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/repositories/email_repository_impl.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/gmail_authorizer.dart';
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

const _base = '/api/mobile/email';

Map<String, Object?> _account({
  String id = 'acc1',
  String status = 'active',
  int pending = 2,
}) => {
  'id': id,
  'email': 'ghina@gmail.com',
  'status': status,
  'lastSyncAt': '2026-10-18T01:00:00.000Z',
  'lastError': null,
  'counts': {'messages': 40, 'pending': pending},
};

Map<String, Object?> suggestionJson({
  String id = 's1',
  String kind = 'expense',
  String source = 'rule',
  String? walletId = 'w1',
  Map<String, Object?>? duplicateOf,
  String status = 'pending',
}) => {
  'id': id,
  'accountEmail': 'ghina@gmail.com',
  'messageId': 'm1',
  'gmailUrl': 'https://mail.google.com/mail/u/0/#all/m1',
  'from': 'BCA <bca@bca.co.id>',
  'subject': 'Transaksi Kartu Kredit',
  'receivedAt': '2026-10-17T03:00:00.000Z',
  'kind': kind,
  'amount': 125000,
  'originalAmount': null,
  'originalCurrency': null,
  'merchant': 'Tokopedia',
  'note': 'Tokopedia',
  'occurredAt': '2026-10-17T02:58:00.000Z',
  'method': 'Kartu Kredit BCA •5736',
  'walletId': walletId,
  'categoryId': null,
  'source': source,
  'parser': source == 'ai' ? 'ai' : 'bca_cc',
  'duplicateOf': duplicateOf,
  'status': status,
  'transactionId': null,
};

({ApiEmailRepository repo, _Adapter adapter}) _repo(
  Map<String, (int, Object?)> routes,
) {
  final adapter = _Adapter(routes);
  final client = ApiClient(baseUrl: 'https://x.test', tokens: _Tokens());
  client.dio.httpClientAdapter = adapter;
  return (repo: ApiEmailRepository(client), adapter: adapter);
}

class _Authorizer implements GmailAuthorizer {
  _Authorizer(this.code, {this.available = true});
  final String? code;
  @override
  final bool available;
  @override
  Future<String?> requestServerAuthCode() async => code;
}

TypeMatcher<EmailException> _kind(EmailErrorKind k) =>
    isA<EmailException>().having((e) => e.kind, 'kind', k);

void main() {
  test(
    'overview: enabled, since as a local day, accounts with counts',
    () async {
      final r = _repo({
        'GET $_base/accounts': (
          200,
          {
            'enabled': true,
            'since': '2026-10-01',
            'accounts': [
              _account(),
              _account(id: 'acc2', status: 'revoked', pending: 1),
              {'email': 'no-id@x.id'},
            ],
          },
        ),
      });
      final o = await r.repo.overview();
      expect(o.enabled, isTrue);
      expect(o.since, DateTime(2026, 10, 1));
      expect(o.accounts.map((a) => a.id), ['acc1', 'acc2']);
      expect(o.accounts.first.status, EmailAccountStatus.active);
      expect(o.accounts.first.messageCount, 40);
      expect(
        o.accounts.first.lastSyncAt,
        DateTime.utc(2026, 10, 18, 1).toLocal(),
      );
      expect(o.accounts.last.status, EmailAccountStatus.revoked);
      expect(o.pendingCount, 3);
      expect(r.adapter.requests.single.headers['Authorization'], 'Bearer tok');
    },
  );

  test('overview: disabled feature is not an error', () async {
    final r = _repo({
      'GET $_base/accounts': (200, {'enabled': false, 'accounts': <Object>[]}),
    });
    final o = await r.repo.overview();
    expect(o.enabled, isFalse);
    expect(o.accounts, isEmpty);
  });

  test('connect posts the server auth code', () async {
    final r = _repo({
      'POST $_base/accounts/connect': (201, {'account': _account()}),
    });
    final a = await r.repo.connect('4/abc');
    expect(a.email, 'ghina@gmail.com');
    expect(r.adapter.requests.single.data, {'serverAuthCode': '4/abc'});
  });

  test('403 email_not_enabled → notEnabled', () async {
    final r = _repo({
      'POST $_base/accounts/connect': (403, {'error': 'email_not_enabled'}),
    });
    await expectLater(
      r.repo.connect('x'),
      throwsA(_kind(EmailErrorKind.notEnabled)),
    );
  });

  test('error mapping: 409, 502, 400, offline', () async {
    final r = _repo({
      'POST $_base/suggestions/s1/approve': (409, {'error': 'already decided'}),
      'POST $_base/sync': (502, {'error': 'google'}),
      'POST $_base/suggestions/s2/approve': (
        400,
        {'error': 'walletId required'},
      ),
    });
    await expectLater(
      r.repo.approve('s1', const EmailApproval(walletId: 'w1')),
      throwsA(_kind(EmailErrorKind.conflict)),
    );
    await expectLater(r.repo.sync(), throwsA(_kind(EmailErrorKind.google)));
    await expectLater(
      r.repo.approve('s2', const EmailApproval()),
      throwsA(
        _kind(
          EmailErrorKind.invalid,
        ).having((e) => e.message, 'message', 'walletId required'),
      ),
    );
    r.adapter.failWith = DioExceptionType.connectionError;
    await expectLater(
      r.repo.overview(),
      throwsA(_kind(EmailErrorKind.network)),
    );
  });

  test('disconnect, ignore, restore hit their routes', () async {
    final r = _repo({
      'DELETE $_base/accounts/acc1': (204, null),
      'POST $_base/suggestions/s1/ignore': (204, null),
      'POST $_base/suggestions/s1/restore': (200, {'ok': true}),
    });
    await r.repo.disconnect('acc1');
    await r.repo.ignore('s1');
    await r.repo.restore('s1');
    expect(r.adapter.requests.map((o) => '${o.method} ${o.path}'), [
      'DELETE $_base/accounts/acc1',
      'POST $_base/suggestions/s1/ignore',
      'POST $_base/suggestions/s1/restore',
    ]);
  });

  test('sync: per-account results; accountId only when given', () async {
    final r = _repo({
      'POST $_base/sync': (
        200,
        {
          'accounts': [
            {
              'id': 'acc1',
              'fetched': 12,
              'newMessages': 5,
              'suggested': 3,
              'error': null,
            },
            {
              'id': 'acc2',
              'fetched': 0,
              'newMessages': 0,
              'suggested': 0,
              'error': 'invalid_grant',
            },
          ],
        },
      ),
    });
    final res = await r.repo.sync();
    expect(res.map((x) => (x.accountId, x.suggested, x.error)), [
      ('acc1', 3, null),
      ('acc2', 0, 'invalid_grant'),
    ]);
    expect(r.adapter.requests.last.data, <String, Object?>{});
    await r.repo.sync(accountId: 'acc1');
    expect(r.adapter.requests.last.data, {'accountId': 'acc1'});
  });

  test('suggestions: status query, every contract field', () async {
    final r = _repo({
      'GET $_base/suggestions': (
        200,
        {
          'items': [
            suggestionJson(
              duplicateOf: {
                'transactionId': 't9',
                'amount': 125000,
                'date': '2026-10-17T00:00:00.000Z',
                'note': 'Tokped',
              },
            ),
            suggestionJson(
              id: 's2',
              kind: 'income',
              source: 'ai',
              walletId: null,
            )..addAll({'originalAmount': 12.5, 'originalCurrency': 'USD'}),
            {'id': 'bad'},
          ],
          'total': 7,
        },
      ),
    });
    final page = await r.repo.suggestions(EmailSuggestionStatus.pending);
    expect(r.adapter.requests.single.queryParameters, {
      'status': 'pending',
      'limit': 50,
      'offset': 0,
    });
    expect(page.total, 7);
    expect(page.items, hasLength(2));
    final a = page.items.first;
    expect(a.title, 'Tokopedia');
    expect(a.kind, EmailSuggestionKind.expense);
    expect(a.amount, 125000);
    expect(a.method, 'Kartu Kredit BCA •5736');
    expect(a.walletId, 'w1');
    expect(a.source, EmailSuggestionSource.rule);
    expect(a.parser, 'bca_cc');
    expect(a.gmailUrl, startsWith('https://mail.google.com/'));
    expect(a.occurredAt, DateTime.utc(2026, 10, 17, 2, 58).toLocal());
    expect(a.duplicateOf?.transactionId, 't9');
    expect(a.duplicateOf?.note, 'Tokped');
    final b = page.items.last;
    expect(b.kind, EmailSuggestionKind.income);
    expect(b.source, EmailSuggestionSource.ai);
    expect(b.walletId, isNull);
    expect(b.duplicateOf, isNull);
    expect((b.originalAmount, b.originalCurrency), (12.5, 'USD'));
  });

  test('approve sends only what changed and returns the transaction', () async {
    final r = _repo({
      'POST $_base/suggestions/s1/approve': (200, {'transactionId': 'tx1'}),
    });
    final tx = await r.repo.approve(
      's1',
      EmailApproval(
        walletId: 'w2',
        amount: 99000,
        occurredAt: DateTime.utc(2026, 10, 16, 5),
      ),
    );
    expect(tx, 'tx1');
    expect(r.adapter.requests.single.data, {
      'amount': 99000.0,
      'walletId': 'w2',
      'occurredAt': '2026-10-16T05:00:00.000Z',
    });
  });

  group('Killa Inbox', () {
    Map<String, Object?> inboxJson({
      String id = 'm1',
      String importance = 'urgent',
      bool read = false,
    }) => {
      'id': id,
      'accountEmail': 'ghina@gmail.com',
      'from': 'Korlantas <etle@korlantas.polri.go.id>',
      'subject': 'Denda ETLE',
      'receivedAt': '2026-10-17T03:00:00.000Z',
      'importance': importance,
      'summary': 'Pelanggaran 12 Okt, Rp500.000, bayar sebelum 25 Okt.',
      'action': 'Konfirmasi/bayar via BRIVA.',
      'replyDraft': null,
      'gmailUrl': 'https://mail.google.com/mail/u/0/#all/m1',
      'notifiedAt': '2026-10-17T03:05:00.000Z',
      'read': read,
    };

    test('accounts carry triage and counts.inboxUnread', () async {
      final r = _repo({
        'GET $_base/accounts': (
          200,
          {
            'enabled': true,
            'accounts': [
              {
                ..._account(),
                'triage': true,
                'counts': {'messages': 40, 'pending': 2, 'inboxUnread': 4},
              },
              _account(id: 'acc2'), // an older server: no triage keys
            ],
          },
        ),
      });
      final o = await r.repo.overview();
      expect(o.accounts.first.triage, isTrue);
      expect(o.accounts.first.inboxUnread, 4);
      expect(o.accounts.last.triage, isFalse);
      expect(o.accounts.last.inboxUnread, 0);
      expect(o.inboxUnread, 4);
      expect(o.triageOn, isTrue);
    });

    test('PATCH accounts/{id} {triage} → the account', () async {
      final r = _repo({
        'PATCH $_base/accounts/acc1': (
          200,
          {
            'account': {..._account(), 'triage': true},
          },
        ),
      });
      final a = await r.repo.setTriage('acc1', true);
      expect(a.triage, isTrue);
      expect(r.adapter.requests.single.data, {'triage': true});
    });

    test('inbox: query, every contract field, bad rows dropped', () async {
      final r = _repo({
        'GET $_base/inbox': (
          200,
          {
            'items': [
              inboxJson(),
              inboxJson(id: 'm2', importance: 'weird', read: true)..addAll({
                'from': 'plain@x.id',
                'action': null,
                'replyDraft': 'Baik, terima kasih.',
                'notifiedAt': null,
              }),
              {'importance': 'urgent'},
              'nope',
            ],
            'total': 9,
            'unread': 5,
          },
        ),
      });
      final page = await r.repo.inbox();
      expect(r.adapter.requests.single.queryParameters, {
        'importance': 'urgent,important,info',
        'limit': 50,
        'offset': 0,
      });
      expect((page.total, page.unread), (9, 5));
      expect(page.items.map((i) => i.id), ['m1', 'm2']);
      final a = page.items.first;
      expect(a.importance, EmailImportance.urgent);
      expect(a.sender, 'Korlantas');
      expect(a.subject, 'Denda ETLE');
      expect(a.summary, startsWith('Pelanggaran 12 Okt'));
      expect(a.action, 'Konfirmasi/bayar via BRIVA.');
      expect(a.replyDraft, isNull);
      expect(a.gmailUrl, startsWith('https://mail.google.com/'));
      expect(a.receivedAt, DateTime.utc(2026, 10, 17, 3).toLocal());
      expect(a.notifiedAt, DateTime.utc(2026, 10, 17, 3, 5).toLocal());
      expect(a.read, isFalse);
      final b = page.items.last;
      expect(b.importance, EmailImportance.info, reason: 'unknown → info');
      expect(b.sender, 'plain@x.id');
      expect(b.action, isNull);
      expect(b.replyDraft, 'Baik, terima kasih.');
      expect(b.notifiedAt, isNull);
      expect(b.read, isTrue);

      await r.repo.inbox(
        importance: {EmailImportance.info, EmailImportance.urgent},
        limit: 30,
        offset: 30,
      );
      expect(r.adapter.requests.last.queryParameters, {
        'importance': 'urgent,info',
        'limit': 30,
        'offset': 30,
      });
    });

    test('inbox: missing totals fall back to the rows', () async {
      final r = _repo({
        'GET $_base/inbox': (
          200,
          {
            'items': [inboxJson(), inboxJson(id: 'm2', read: true)],
          },
        ),
      });
      final page = await r.repo.inbox();
      expect((page.total, page.unread), (2, 1));
    });

    test('mark read, delete rule hit their routes', () async {
      final r = _repo({
        'POST $_base/inbox/m1/read': (204, null),
        'DELETE $_base/inbox/rules/r1': (204, null),
      });
      await r.repo.markRead('m1');
      await r.repo.deleteRule('r1');
      expect(r.adapter.requests.map((o) => '${o.method} ${o.path}'), [
        'POST $_base/inbox/m1/read',
        'DELETE $_base/inbox/rules/r1',
      ]);
    });

    test('rules: list (items / rules / bare), invalid rows dropped', () async {
      final rule = {
        'id': 'r1',
        'kind': 'always',
        'match': 'sender',
        'pattern': 'kampus.ac.id',
        'note': 'dosen',
        'createdAt': '2026-10-17T03:00:00.000Z',
      };
      final rows = [
        rule,
        {...rule, 'id': 'r2', 'kind': 'never', 'match': 'keyword'},
        {...rule, 'id': 'r3', 'kind': 'maybe'},
        {...rule, 'id': 'r4', 'pattern': ''},
        {...rule, 'id': null},
      ];
      for (final body in <Object>[
        {'items': rows},
        {'rules': rows},
        rows,
      ]) {
        final r = _repo({'GET $_base/inbox/rules': (200, body)});
        final list = await r.repo.rules();
        expect(list.map((x) => x.id), ['r1', 'r2']);
        expect(list.first.kind, EmailRuleKind.always);
        expect(list.first.match, EmailRuleMatch.sender);
        expect(list.first.note, 'dosen');
        expect(list.first.createdAt, DateTime.utc(2026, 10, 17, 3).toLocal());
        expect(list.last.kind, EmailRuleKind.never);
        expect(list.last.match, EmailRuleMatch.keyword);
      }
    });

    test('add rule: body; {rule} or the bare rule back', () async {
      final back = {
        'id': 'r9',
        'kind': 'never',
        'match': 'sender',
        'pattern': 'newsletter@x.id',
      };
      for (final body in <Object>[
        {'rule': back},
        back,
      ]) {
        final r = _repo({'POST $_base/inbox/rules': (201, body)});
        final rule = await r.repo.addRule(
          const EmailRuleInput(
            kind: EmailRuleKind.never,
            match: EmailRuleMatch.sender,
            pattern: ' newsletter@x.id ',
            note: '  ',
          ),
        );
        expect(rule.id, 'r9');
        expect(rule.note, isNull);
        expect(r.adapter.requests.single.data, {
          'kind': 'never',
          'match': 'sender',
          'pattern': 'newsletter@x.id',
        });
      }
    });

    test('AddEmailRule: empty / too long patterns stay local', () async {
      final r = _repo({});
      final add = AddEmailRule(r.repo);
      expect(
        () => add(
          const EmailRuleInput(
            kind: EmailRuleKind.always,
            match: EmailRuleMatch.keyword,
            pattern: '   ',
          ),
        ),
        throwsA(_kind(EmailErrorKind.invalid)),
      );
      expect(
        () => add(
          EmailRuleInput(
            kind: EmailRuleKind.always,
            match: EmailRuleMatch.keyword,
            pattern: 'x' * 201,
          ),
        ),
        throwsA(_kind(EmailErrorKind.invalid)),
      );
      expect(r.adapter.requests, isEmpty);
    });

    test('sender display name', () {
      EmailInboxItem from(String f) =>
          EmailInboxItem(id: 'x', importance: EmailImportance.info, from: f);
      expect(from('"BCA" <bca@bca.co.id>').sender, 'BCA');
      expect(
        from('Dosen Pembimbing <d@kampus.ac.id>').sender,
        'Dosen Pembimbing',
      );
      expect(from('<d@kampus.ac.id>').sender, '<d@kampus.ac.id>');
      expect(from('d@kampus.ac.id').sender, 'd@kampus.ac.id');
    });
  });

  group('use cases', () {
    late _Adapter adapter;
    late ApiEmailRepository repo;
    setUp(() {
      final r = _repo({
        'POST $_base/accounts/connect': (201, {'account': _account()}),
        'POST $_base/suggestions/s1/approve': (200, {'transactionId': 'tx1'}),
      });
      adapter = r.adapter;
      repo = r.repo;
    });

    test('ConnectGmail: cancel → null, no request', () async {
      expect(await ConnectGmail(repo, _Authorizer(null))(), isNull);
      expect(adapter.requests, isEmpty);
      final a = await ConnectGmail(repo, _Authorizer('code-1'))();
      expect(a?.id, 'acc1');
      expect(adapter.requests.single.data, {'serverAuthCode': 'code-1'});
    });

    test('ConnectGmail: unavailable build → signIn error', () async {
      await expectLater(
        ConnectGmail(repo, _Authorizer('x', available: false))(),
        throwsA(_kind(EmailErrorKind.signIn)),
      );
    });

    test('Approve: needs a wallet; transfer needs another wallet', () async {
      final approve = ApproveEmailSuggestion(repo);
      final noWallet = EmailSuggestion(
        id: 's1',
        kind: EmailSuggestionKind.expense,
        amount: 1000,
        occurredAt: DateTime(2026, 10, 1),
        status: EmailSuggestionStatus.pending,
      );
      expect(() => approve(noWallet), throwsA(_kind(EmailErrorKind.invalid)));
      expect(
        () => approve(
          noWallet,
          const EmailApproval(
            walletId: 'w1',
            kind: EmailSuggestionKind.transfer,
            toWalletId: 'w1',
          ),
        ),
        throwsA(_kind(EmailErrorKind.invalid)),
      );
      expect(adapter.requests, isEmpty);
      expect(
        await approve(noWallet, const EmailApproval(walletId: 'w1')),
        'tx1',
      );
      expect(adapter.requests.single.data, {'walletId': 'w1'});
    });
  });
}
