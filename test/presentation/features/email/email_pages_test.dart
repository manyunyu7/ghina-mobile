// Email pages (`/email`, `/email/review`, `/email/inbox`, `/email/rules`) on
// a fake EmailRepository + fake
// Gmail authorizer, with the real wallet data layer from the feature harness.
// Never pumpAndSettle: the mascots animate forever.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/email/pages/email_inbox_page.dart';
import 'package:ghina/presentation/features/email/pages/email_page.dart';
import 'package:ghina/presentation/features/email/pages/email_review_page.dart';
import 'package:ghina/presentation/features/email/pages/email_rules_page.dart';
import 'package:go_router/go_router.dart';

import '../transactions/_feature_harness.dart';

class FakeEmailRepository implements EmailRepository {
  FakeEmailRepository({
    this.enabled = true,
    List<EmailAccount>? accounts,
    List<EmailSuggestion>? rows,
    List<EmailInboxItem>? inboxItems,
    List<EmailTriageRule>? rules,
  }) : accounts = accounts ?? [],
       rows = rows ?? [],
       inboxItems = inboxItems ?? [],
       ruleRows = rules ?? [];

  final List<EmailInboxItem> inboxItems;
  final List<EmailTriageRule> ruleRows;
  final readIds = <String>[];
  final triageCalls = <(String, bool)>[];
  final inboxQueries = <(Set<EmailImportance>, int)>[];
  final addedRules = <EmailRuleInput>[];
  final deletedRules = <String>[];
  int _ruleSeq = 0;

  bool enabled;
  int backgroundSyncCalls = 0;
  final List<EmailAccount> accounts;
  final List<EmailSuggestion> rows;

  final connectCodes = <String>[];
  final approvals = <(String, EmailApproval)>[];
  final ignored = <String>[];
  final restored = <String>[];
  final disconnected = <String>[];
  int syncCalls = 0;

  static const _off = EmailException(
    EmailErrorKind.notEnabled,
    'Fitur email belum aktif untuk akun kamu.',
    status: 403,
  );

  EmailSuggestion _with(EmailSuggestion s, EmailSuggestionStatus status) =>
      EmailSuggestion(
        id: s.id,
        kind: s.kind,
        amount: s.amount,
        occurredAt: s.occurredAt,
        status: status,
        merchant: s.merchant,
        note: s.note,
        method: s.method,
        walletId: s.walletId,
        source: s.source,
        duplicateOf: s.duplicateOf,
        gmailUrl: s.gmailUrl,
      );

  void _move(String id, EmailSuggestionStatus to) {
    final i = rows.indexWhere((s) => s.id == id);
    rows[i] = _with(rows[i], to);
  }

  @override
  Future<EmailOverview> overview() async => EmailOverview(
    enabled: enabled,
    since: DateTime(2026, 10, 1),
    accounts: enabled ? List.of(accounts) : const [],
  );

  @override
  Future<EmailAccount> connect(String serverAuthCode) async {
    if (!enabled) throw _off;
    connectCodes.add(serverAuthCode);
    final a = EmailAccount(
      id: 'acc${accounts.length + 1}',
      email: 'baru@gmail.com',
      status: EmailAccountStatus.active,
    );
    accounts.add(a);
    return a;
  }

  @override
  Future<void> disconnect(String accountId) async {
    disconnected.add(accountId);
    accounts.removeWhere((a) => a.id == accountId);
  }

  @override
  Future<List<EmailSyncResult>> sync({
    String? accountId,
    bool background = false,
  }) async {
    syncCalls++;
    if (background) backgroundSyncCalls++;
    return [for (final a in accounts) EmailSyncResult(accountId: a.id)];
  }

  @override
  Future<EmailSuggestionPage> suggestions(
    EmailSuggestionStatus status, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!enabled) throw _off;
    final items = [
      for (final s in rows)
        if (s.status == status) s,
    ];
    return EmailSuggestionPage(items: items, total: items.length);
  }

  @override
  Future<String> approve(String id, EmailApproval approval) async {
    approvals.add((id, approval));
    _move(id, EmailSuggestionStatus.approved);
    return 'tx-$id';
  }

  @override
  Future<void> ignore(String id) async {
    ignored.add(id);
    _move(id, EmailSuggestionStatus.ignored);
  }

  @override
  Future<void> restore(String id) async {
    restored.add(id);
    _move(id, EmailSuggestionStatus.pending);
  }

  @override
  Future<EmailAccount> setTriage(String accountId, bool on) async {
    triageCalls.add((accountId, on));
    final i = accounts.indexWhere((a) => a.id == accountId);
    return accounts[i] = accounts[i].copyWith(triage: on);
  }

  @override
  Future<EmailInboxPage> inbox({
    Set<EmailImportance> importance = const {},
    int limit = 50,
    int offset = 0,
  }) async {
    if (!enabled) throw _off;
    inboxQueries.add((importance, offset));
    final levels = importance.isEmpty
        ? EmailImportance.shown.toSet()
        : importance;
    final all = [
      for (final i in inboxItems)
        if (levels.contains(i.importance)) i,
    ]..sort((a, b) => b.receivedAt!.compareTo(a.receivedAt!));
    return EmailInboxPage(
      items: all.skip(offset).take(limit).toList(),
      total: all.length,
      unread: all.where((i) => !i.read).length,
    );
  }

  @override
  Future<void> markRead(String id) async {
    readIds.add(id);
    final i = inboxItems.indexWhere((m) => m.id == id);
    inboxItems[i] = inboxItems[i].copyWith(read: true);
  }

  @override
  Future<List<EmailTriageRule>> rules() async => List.of(ruleRows);

  @override
  Future<EmailTriageRule> addRule(EmailRuleInput input) async {
    addedRules.add(input);
    final r = EmailTriageRule(
      id: 'r${++_ruleSeq}',
      kind: input.kind,
      match: input.match,
      pattern: input.pattern,
      note: input.note,
    );
    ruleRows.add(r);
    return r;
  }

  @override
  Future<void> deleteRule(String id) async {
    deletedRules.add(id);
    ruleRows.removeWhere((r) => r.id == id);
  }
}

EmailInboxItem inboxItem(
  String id, {
  EmailImportance importance = EmailImportance.important,
  int hour = 9,
  bool read = false,
  String? replyDraft,
  String from = 'Korlantas <etle@korlantas.polri.go.id>',
  String subject = 'Pemberitahuan Pelanggaran ETLE',
}) => EmailInboxItem(
  id: id,
  importance: importance,
  accountEmail: 'ghina@gmail.com',
  from: from,
  subject: subject,
  receivedAt: DateTime(2026, 10, 17, hour),
  summary: 'Ringkasan $id dari Killa.',
  action: 'Tindakan $id',
  replyDraft: replyDraft,
  gmailUrl: 'https://mail.google.com/mail/u/0/#all/$id',
  read: read,
);

class FakeGmailAuthorizer implements GmailAuthorizer {
  FakeGmailAuthorizer(this.code);
  final String? code;
  int calls = 0;

  @override
  bool get available => true;

  @override
  Future<String?> requestServerAuthCode() async {
    calls++;
    return code;
  }
}

class _CountingSync implements SyncService {
  int calls = 0;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async => calls++;
  @override
  Stream<SyncStatus> watchStatus() => const Stream.empty();
  @override
  Future<void> resetLocalData() async {}
}

EmailSuggestion suggestion(
  String id, {
  String? walletId,
  EmailSuggestionKind kind = EmailSuggestionKind.expense,
  EmailDuplicate? duplicateOf,
  EmailSuggestionSource source = EmailSuggestionSource.rule,
  String merchant = 'Tokopedia',
}) => EmailSuggestion(
  id: id,
  kind: kind,
  amount: 125000,
  occurredAt: DateTime(2026, 10, 17, 9, 58),
  status: EmailSuggestionStatus.pending,
  merchant: merchant,
  method: 'Kartu Kredit BCA •5736',
  walletId: walletId,
  source: source,
  duplicateOf: duplicateOf,
  gmailUrl: 'https://mail.google.com/mail/u/0/#all/$id',
);

class _Env {
  _Env({FakeEmailRepository? repo, String? code = 'code-1'})
    : repo = repo ?? FakeEmailRepository(),
      auth = FakeGmailAuthorizer(code);

  final FakeEmailRepository repo;
  final FakeGmailAuthorizer auth;
  final sync = _CountingSync();
  late final ProviderContainer c = makeContainer(
    overrides: [
      emailRepositoryProvider.overrideWithValue(repo),
      gmailAuthorizerProvider.overrideWithValue(auth),
      syncNowProvider.overrideWithValue(SyncNow(sync)),
    ],
  );

  Future<String> seedWallet(WidgetTester tester, String name) =>
      real(tester, () async {
        final w = (await c.read(createWalletProvider)(
          WalletInput(name: name, initialBalance: 500000),
        )).valueOrThrow;
        return w.id;
      });

  Future<GoRouter> pump(
    WidgetTester tester,
    String location, {
    bool dark = false,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/email', builder: (_, _) => const EmailPage()),
        GoRoute(
          path: '/email/review',
          builder: (_, _) => const EmailReviewPage(),
        ),
        GoRoute(
          path: '/email/inbox',
          builder: (_, _) => const EmailImportantPage(),
        ),
        GoRoute(
          path: '/email/rules',
          builder: (_, _) => const EmailRulesPage(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
    return router;
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  // Lazily built list rows below the fold.
  if (f.evaluate().isEmpty) await scrollTo(tester, f);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

void main() {
  group('Email page', () {
    testWidgets('connect: fake platform code → connect → first sync', (
      tester,
    ) async {
      final env = _Env();
      await env.pump(tester, '/email');
      expect(find.text('Belum ada Gmail terhubung'), findsOneWidget);
      expect(find.textContaining('mulai 1 Oktober 2026'), findsOneWidget);

      await tapKey(tester, 'email-connect');
      await settle(tester);
      expect(env.auth.calls, 1);
      expect(env.repo.connectCodes, ['code-1']);
      expect(env.repo.syncCalls, 1);
      expect(
        env.repo.backgroundSyncCalls,
        1,
        reason: 'first sync runs in the background',
      );
      expect(find.text('baru@gmail.com'), findsWidgets);
      expect(find.byKey(const Key('email-account-acc1')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('connect cancelled: nothing is sent', (tester) async {
      final env = _Env(code: null);
      await env.pump(tester, '/email');
      await tapKey(tester, 'email-connect');
      expect(env.auth.calls, 1);
      expect(env.repo.connectCodes, isEmpty);
      expect(find.text('Belum ada Gmail terhubung'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('not enabled: friendly locked state, no buttons', (
      tester,
    ) async {
      final env = _Env(repo: FakeEmailRepository(enabled: false));
      await env.pump(tester, '/email');
      expect(find.byKey(const Key('email-not-enabled')), findsOneWidget);
      expect(find.text('Fitur email belum aktif'), findsOneWidget);
      expect(find.byKey(const Key('email-connect')), findsNothing);
      await tearDownApp(tester, env.c);
    });

    testWidgets('connect answered 403 email_not_enabled → explanation', (
      tester,
    ) async {
      final repo = FakeEmailRepository();
      final env = _Env(repo: repo);
      await env.pump(tester, '/email');
      repo.enabled = false; // turned off after the page loaded
      await tapKey(tester, 'email-connect');
      await settle(tester);
      expect(find.textContaining('daftar uji coba'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('disconnect asks first, then removes the account', (
      tester,
    ) async {
      final env = _Env(
        repo: FakeEmailRepository(
          accounts: [
            const EmailAccount(
              id: 'acc1',
              email: 'ghina@gmail.com',
              status: EmailAccountStatus.active,
              pendingCount: 2,
            ),
          ],
        ),
      );
      await env.pump(tester, '/email');
      expect(find.text('2 perlu dicek'), findsOneWidget);
      await tapKey(tester, 'email-disconnect-acc1');
      expect(find.text('Putuskan ghina@gmail.com?'), findsOneWidget);
      await tester.tap(find.text('PUTUSKAN'));
      await settle(tester);
      expect(env.repo.disconnected, ['acc1']);
      expect(find.text('Belum ada Gmail terhubung'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('sync now calls the server', (tester) async {
      final env = _Env(
        repo: FakeEmailRepository(
          accounts: [
            const EmailAccount(
              id: 'acc1',
              email: 'ghina@gmail.com',
              status: EmailAccountStatus.active,
            ),
          ],
        ),
      );
      await env.pump(tester, '/email');
      await tapKey(tester, 'email-sync');
      expect(env.repo.syncCalls, 1);
      expect(env.repo.backgroundSyncCalls, 1);
      await tearDownApp(tester, env.c);
    });

    testWidgets(
      'a running server sync shows on the card, then reports when done',
      (tester) async {
        final repo = FakeEmailRepository(
          accounts: [
            const EmailAccount(
              id: 'acc1',
              email: 'ghina@gmail.com',
              status: EmailAccountStatus.active,
              syncing: true,
            ),
          ],
        );
        final env = _Env(repo: repo);
        await env.pump(tester, '/email');
        expect(find.text('Lagi menyinkron di latar belakang…'), findsOneWidget);
        // The server finishes with 3 new pending suggestions; the 4 s poll picks it up.
        repo.accounts[0] = const EmailAccount(
          id: 'acc1',
          email: 'ghina@gmail.com',
          status: EmailAccountStatus.active,
          pendingCount: 3,
        );
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
        expect(find.text('Lagi menyinkron di latar belakang…'), findsNothing);
        expect(
          find.text('Sinkron selesai: 3 transaksi baru perlu dicek'),
          findsOneWidget,
        );
        await tearDownApp(tester, env.c);
      },
    );
  });

  group('Perlu dicek', () {
    testWidgets('approve with the guessed wallet, then a sync pull', (
      tester,
    ) async {
      final env = _Env();
      final w = await env.seedWallet(tester, 'BCA');
      env.repo.rows.add(suggestion('s1', walletId: w));
      await env.pump(tester, '/email/review');
      expect(find.text('Tokopedia'), findsOneWidget);
      expect(find.text('Otomatis'), findsOneWidget);
      expect(find.text('BCA'), findsOneWidget);

      await tapKey(tester, 'email-approve-s1');
      expect(env.repo.approvals.single.$1, 's1');
      expect(env.repo.approvals.single.$2.walletId, w);
      expect(env.sync.calls, 1);
      expect(find.byKey(const Key('email-suggestion-s1')), findsNothing);
      expect(find.text('Semua sudah dicek'), findsOneWidget);

      await tester.tap(find.text('Disetujui'));
      await settle(tester);
      expect(find.byKey(const Key('email-suggestion-s1')), findsOneWidget);
      expect(find.text('Sudah dicatat'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('approve without a wallet asks with the wallet picker', (
      tester,
    ) async {
      final env = _Env();
      final w = await env.seedWallet(tester, 'Tunai');
      env.repo.rows.add(suggestion('s1', source: EmailSuggestionSource.ai));
      await env.pump(tester, '/email/review');
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('Dompet belum dipilih'), findsOneWidget);

      await tapKey(tester, 'email-approve-s1');
      expect(find.text('Masuk ke dompet mana?'), findsOneWidget);
      expect(env.repo.approvals, isEmpty);
      await tester.tap(find.text('Tunai').last);
      await settle(tester);
      expect(env.repo.approvals.single.$2.walletId, w);
      await tearDownApp(tester, env.c);
    });

    testWidgets('ignore, then undo restores it', (tester) async {
      final env = _Env();
      env.repo.rows.add(suggestion('s1'));
      await env.pump(tester, '/email/review');

      await tapKey(tester, 'email-ignore-s1');
      expect(env.repo.ignored, ['s1']);
      expect(find.byKey(const Key('email-suggestion-s1')), findsNothing);
      expect(find.text('"Tokopedia" diabaikan'), findsOneWidget);

      await tester.tap(find.text('BATAL'));
      await settle(tester);
      expect(env.repo.restored, ['s1']);
      expect(find.byKey(const Key('email-suggestion-s1')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('ignored tab: Kembalikan moves it back', (tester) async {
      final env = _Env();
      env.repo.rows.add(suggestion('s1'));
      await env.pump(tester, '/email/review');
      await tapKey(tester, 'email-ignore-s1');
      await tester.pump(const Duration(seconds: 5)); // snackbar gone

      await tester.tap(find.text('Diabaikan'));
      await settle(tester);
      await tapKey(tester, 'email-restore-s1');
      expect(env.repo.restored, ['s1']);
      expect(find.byKey(const Key('email-suggestion-s1')), findsNothing);
      await tearDownApp(tester, env.c);
    });

    testWidgets('"Mungkin dobel" shows only for a possible duplicate', (
      tester,
    ) async {
      final env = _Env();
      env.repo.rows
        ..add(
          suggestion(
            's1',
            duplicateOf: EmailDuplicate(
              transactionId: 't9',
              amount: 125000,
              date: DateTime(2026, 10, 17),
              note: 'Tokped',
            ),
          ),
        )
        ..add(suggestion('s2', merchant: 'Gojek'));
      await env.pump(tester, '/email/review');
      final dup = find.byKey(const Key('email-duplicate'));
      expect(dup, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('email-suggestion-s1')),
          matching: dup,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Mungkin dobel', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Tokped', findRichText: true), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('edit: change the amount, then approve', (tester) async {
      final env = _Env();
      final w = await env.seedWallet(tester, 'BCA');
      env.repo.rows.add(suggestion('s1', walletId: w));
      await env.pump(tester, '/email/review');

      await tapKey(tester, 'email-edit-s1');
      expect(find.text('Edit sebelum disetujui'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('email-edit-amount')),
          matching: find.byType(EditableText),
        ),
        '99000',
      );
      await tester.pump();
      await tapKey(tester, 'email-edit-submit');
      final (id, a) = env.repo.approvals.single;
      expect(id, 's1');
      expect(a.amount, 99000);
      expect(a.walletId, w);
      expect(a.kind, isNull);
      await tearDownApp(tester, env.c);
    });

    testWidgets('cards and the page fit: dark, large text, 360 wide', (
      tester,
    ) async {
      final env = _Env(
        repo: FakeEmailRepository(
          accounts: [
            const EmailAccount(
              id: 'acc1',
              email: 'nama.panjang.sekali@gmail.com',
              status: EmailAccountStatus.error,
              lastError: 'invalid_grant',
              pendingCount: 12,
            ),
          ],
        ),
      );
      env.repo.rows.add(
        suggestion(
          's1',
          merchant: 'Pembayaran Tagihan Kartu Kredit Bulan Oktober',
          duplicateOf: const EmailDuplicate(transactionId: 't', amount: 1),
        ),
      );
      await tester.runAsync(loadFonts); // real glyph widths
      tester.view.physicalSize = const Size(360, 740) * 2;
      await env.pump(tester, '/email/review', dark: true, textScale: 1.3);
      tester.view.physicalSize = const Size(360, 740) * 2;
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tearDownApp(tester, env.c);
      final env2 = _Env(repo: env.repo);
      await env2.pump(tester, '/email', dark: true, textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tearDownApp(tester, env2.c);
    });

    testWidgets('not enabled: the queue shows the locked state', (
      tester,
    ) async {
      final env = _Env(repo: FakeEmailRepository(enabled: false));
      await env.pump(tester, '/email/review');
      expect(find.byKey(const Key('email-not-enabled')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });
  });

  group('Killa baca semua email', () {
    EmailAccount account({bool triage = false, int unread = 0}) => EmailAccount(
      id: 'acc1',
      email: 'ghina@gmail.com',
      status: EmailAccountStatus.active,
      triage: triage,
      inboxUnread: unread,
    );

    testWidgets('turning it on asks first; off goes straight through', (
      tester,
    ) async {
      final env = _Env(repo: FakeEmailRepository(accounts: [account()]));
      await env.pump(tester, '/email');
      expect(find.text('Killa baca semua email'), findsOneWidget);

      // Cancel: nothing changes.
      await tapKey(tester, 'email-triage-acc1');
      expect(find.text('Killa baca semua email?'), findsOneWidget);
      expect(find.textContaining('jam 08, 12, 18, 21'), findsOneWidget);
      await tester.tap(find.text('BATAL'));
      await settle(tester);
      expect(env.repo.triageCalls, isEmpty);
      expect(
        tester.widget<Switch>(find.byKey(const Key('email-triage-acc1'))).value,
        isFalse,
      );

      await tapKey(tester, 'email-triage-acc1');
      await tester.tap(find.text('NYALAKAN'));
      await settle(tester);
      expect(env.repo.triageCalls, [('acc1', true)]);
      expect(
        tester.widget<Switch>(find.byKey(const Key('email-triage-acc1'))).value,
        isTrue,
      );

      await tapKey(tester, 'email-triage-acc1');
      expect(find.text('Killa baca semua email?'), findsNothing);
      expect(env.repo.triageCalls, [('acc1', true), ('acc1', false)]);
      await tearDownApp(tester, env.c);
    });

    testWidgets('"Email penting" shows the unread count and opens the inbox', (
      tester,
    ) async {
      final env = _Env(
        repo: FakeEmailRepository(
          accounts: [account(triage: true, unread: 3)],
          inboxItems: [inboxItem('m1')],
        ),
      );
      await env.pump(tester, '/email');
      expect(find.byKey(const Key('email-inbox-entry')), findsOneWidget);
      expect(find.byKey(const Key('email-review-entry')), findsOneWidget);
      expect(
        find.text('3 email belum dibaca, sudah diringkas Killa'),
        findsOneWidget,
      );
      await tapKey(tester, 'email-inbox-entry');
      expect(find.byKey(const Key('inbox-item-m1')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });
  });

  group('Email penting', () {
    FakeEmailRepository mixed() => FakeEmailRepository(
      accounts: [
        const EmailAccount(
          id: 'acc1',
          email: 'ghina@gmail.com',
          status: EmailAccountStatus.active,
          triage: true,
        ),
      ],
      inboxItems: [
        inboxItem('u1', importance: EmailImportance.urgent, hour: 8),
        inboxItem('p1', hour: 10, from: 'Dosen <dosen@kampus.ac.id>'),
        inboxItem('i1', importance: EmailImportance.info, hour: 9, read: true),
      ],
    );

    Finder segment(String label) => find.descendant(
      of: find.byType(ChunkySegmented<EmailImportance?>),
      matching: find.text(label),
    );

    double top(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(Key('inbox-item-$id'))).dy;

    testWidgets('segments filter by importance, newest first', (tester) async {
      final env = _Env(repo: mixed());
      await env.pump(tester, '/email/inbox');
      expect(find.byKey(const Key('inbox-item-u1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-item-p1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-item-i1')), findsOneWidget);
      expect(top(tester, 'p1'), lessThan(top(tester, 'i1')));
      expect(top(tester, 'i1'), lessThan(top(tester, 'u1')));
      expect(find.text('Dosen'), findsOneWidget, reason: 'display name');
      expect(find.text('Perlu dilakukan'), findsNWidgets(3));
      // Unread dots: u1 and p1, not the read i1.
      expect(find.byKey(const Key('inbox-unread-u1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-i1')), findsNothing);

      await tester.tap(segment('🔴 Mendesak'));
      await settle(tester);
      expect(env.repo.inboxQueries.last.$1, {EmailImportance.urgent});
      expect(find.byKey(const Key('inbox-item-u1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-item-p1')), findsNothing);

      await tester.tap(segment('🔵 Info'));
      await settle(tester);
      expect(find.byKey(const Key('inbox-item-i1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-item-u1')), findsNothing);

      await tester.tap(segment('🟠 Penting'));
      await settle(tester);
      expect(find.byKey(const Key('inbox-item-p1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-item-i1')), findsNothing);
      await tearDownApp(tester, env.c);
    });

    testWidgets('opening an item marks it read once', (tester) async {
      final env = _Env(repo: mixed());
      await env.pump(tester, '/email/inbox');
      expect(find.byKey(const Key('inbox-unread-p1')), findsOneWidget);
      await tapKey(tester, 'inbox-item-p1');
      expect(env.repo.readIds, ['p1']);
      expect(find.byKey(const Key('inbox-unread-p1')), findsNothing);
      await tapKey(tester, 'inbox-item-p1');
      expect(env.repo.readIds, ['p1'], reason: 'already read');
      await tapKey(tester, 'inbox-item-i1');
      expect(env.repo.readIds, ['p1']);
      await tearDownApp(tester, env.c);
    });

    testWidgets('Draf balasan expands and Salin copies it', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final env = _Env(
        repo: FakeEmailRepository(
          inboxItems: [
            inboxItem(
              'p1',
              replyDraft: 'Baik Pak, saya kirim revisinya besok pagi.',
            ),
            inboxItem('p2', hour: 7),
          ],
        ),
      );
      await env.pump(tester, '/email/inbox');
      expect(find.text('Draf balasan'), findsOneWidget, reason: 'p2 has none');
      expect(find.byKey(const Key('inbox-copy-p1')), findsNothing);

      await tapKey(tester, 'inbox-draft-p1');
      expect(
        find.text('Baik Pak, saya kirim revisinya besok pagi.'),
        findsOneWidget,
      );
      expect(env.repo.readIds, ['p1'], reason: 'expanding opens it');
      await tapKey(tester, 'inbox-copy-p1');
      expect(copied, 'Baik Pak, saya kirim revisinya besok pagi.');
      expect(find.text('Draf balasan disalin'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('pages of 30: "Muat lagi" loads the rest', (tester) async {
      final env = _Env(
        repo: FakeEmailRepository(
          inboxItems: [
            for (var n = 0; n < 35; n++) inboxItem('m$n', hour: 0, read: true),
          ],
        ),
      );
      // Distinct times, newest = m0.
      for (var n = 0; n < 35; n++) {
        final m = env.repo.inboxItems[n];
        env.repo.inboxItems[n] = EmailInboxItem(
          id: m.id,
          importance: m.importance,
          receivedAt: DateTime(2026, 10, 17, 12).subtract(Duration(hours: n)),
          summary: m.summary,
          read: true,
        );
      }
      await env.pump(tester, '/email/inbox');
      expect(env.repo.inboxQueries.single.$1, isEmpty);
      expect(env.repo.inboxQueries.single.$2, 0);
      await scrollTo(tester, find.byKey(const Key('inbox-item-m29')));
      await settle(tester);
      final more = find.byKey(const Key('inbox-more'));
      if (more.evaluate().isNotEmpty) {
        await tapKey(tester, 'inbox-more');
      }
      expect(env.repo.inboxQueries.last.$2, 30);
      await scrollTo(tester, find.byKey(const Key('inbox-item-m34')));
      expect(find.byKey(const Key('inbox-item-m34')), findsOneWidget);
      expect(find.byKey(const Key('inbox-more')), findsNothing);
      await tearDownApp(tester, env.c);
    });

    testWidgets('empty with triage off points to the switch', (tester) async {
      final env = _Env(
        repo: FakeEmailRepository(
          accounts: [
            const EmailAccount(
              id: 'acc1',
              email: 'ghina@gmail.com',
              status: EmailAccountStatus.active,
            ),
          ],
        ),
      );
      await env.pump(tester, '/email/inbox');
      expect(find.byKey(const Key('inbox-empty-off')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('app bar opens "Aturan Killa"', (tester) async {
      final env = _Env(repo: mixed());
      await env.pump(tester, '/email/inbox');
      await tapKey(tester, 'inbox-rules');
      expect(find.text('Aturan Killa'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });
  });

  group('Aturan Killa', () {
    Future<void> type(WidgetTester tester, String key, String text) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(EditableText),
        ),
        text,
      );
      await tester.pump();
    }

    testWidgets('empty state has Indonesian examples', (tester) async {
      final env = _Env();
      await env.pump(tester, '/email/rules');
      expect(find.byKey(const Key('rules-empty')), findsOneWidget);
      expect(find.textContaining('Selalu penting: kampus.ac.id'), findsOne);
      expect(find.textContaining('Abaikan: newsletter@'), findsOne);
      await tearDownApp(tester, env.c);
    });

    testWidgets('add a rule: never / sender / pattern / note', (tester) async {
      final env = _Env();
      await env.pump(tester, '/email/rules');
      await tapKey(tester, 'rules-add');
      expect(find.text('Aturan baru'), findsOneWidget);

      // An empty pattern is refused in the sheet.
      await tapKey(tester, 'rule-submit');
      expect(find.text('Isi alamat atau domain pengirimnya.'), findsOneWidget);
      expect(env.repo.addedRules, isEmpty);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('rule-kind')),
          matching: find.text('Abaikan'),
        ),
      );
      await tester.pump();
      await type(tester, 'rule-pattern', '  newsletter@tokopedia.com ');
      await type(tester, 'rule-note', 'promo terus');
      await tapKey(tester, 'rule-submit');
      final r = env.repo.addedRules.single;
      expect(r.kind, EmailRuleKind.never);
      expect(r.match, EmailRuleMatch.sender);
      expect(r.pattern, 'newsletter@tokopedia.com');
      expect(r.note, 'promo terus');
      expect(find.byKey(const Key('rule-r1')), findsOneWidget);
      expect(find.text('newsletter@tokopedia.com'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('keyword rule', (tester) async {
      final env = _Env();
      await env.pump(tester, '/email/rules');
      await tapKey(tester, 'rules-add');
      await tester.tap(find.text('Kata kunci'));
      await tester.pump();
      await type(tester, 'rule-pattern', 'tagihan');
      await tapKey(tester, 'rule-submit');
      final r = env.repo.addedRules.single;
      expect(
        (r.kind, r.match, r.note),
        (EmailRuleKind.always, EmailRuleMatch.keyword, null),
      );
      await tearDownApp(tester, env.c);
    });

    testWidgets('delete, then undo puts it back', (tester) async {
      final env = _Env(
        repo: FakeEmailRepository(
          rules: [
            const EmailTriageRule(
              id: 'x1',
              kind: EmailRuleKind.always,
              match: EmailRuleMatch.sender,
              pattern: 'kampus.ac.id',
              note: 'dosen',
            ),
          ],
        ),
      );
      await env.pump(tester, '/email/rules');
      expect(find.byKey(const Key('rule-x1')), findsOneWidget);
      expect(find.text('Selalu penting'), findsOneWidget);

      await tapKey(tester, 'rule-delete-x1');
      expect(env.repo.deletedRules, ['x1']);
      expect(find.byKey(const Key('rule-x1')), findsNothing);
      expect(find.text('Aturan "kampus.ac.id" dihapus'), findsOneWidget);

      await tester.tap(find.text('BATAL'));
      await settle(tester);
      final back = env.repo.addedRules.single;
      expect(
        (back.kind, back.match, back.pattern, back.note),
        (EmailRuleKind.always, EmailRuleMatch.sender, 'kampus.ac.id', 'dosen'),
      );
      expect(find.byKey(const Key('rule-r1')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });
  });

  testWidgets('inbox pages fit: dark, text 1.3, 360 wide', (tester) async {
    final repo = FakeEmailRepository(
      accounts: [
        const EmailAccount(
          id: 'acc1',
          email: 'nama.panjang.sekali@gmail.com',
          status: EmailAccountStatus.active,
          triage: true,
          inboxUnread: 128,
          pendingCount: 12,
        ),
      ],
      inboxItems: [
        inboxItem(
          'u1',
          importance: EmailImportance.urgent,
          from:
              'Direktorat Jenderal Pajak Kementerian Keuangan <noreply@pajak.go.id>',
          subject:
              'Surat Teguran Pajak Penghasilan Tahun 2025 yang Belum Dibayar',
          replyDraft: 'Terima kasih, saya akan segera menyelesaikannya.',
        ),
        inboxItem('p1', hour: 7),
      ],
      rules: [
        const EmailTriageRule(
          id: 'x1',
          kind: EmailRuleKind.never,
          match: EmailRuleMatch.keyword,
          pattern: 'diskon besar-besaran akhir tahun untuk semua pelanggan',
          note: 'promo yang selalu datang tiap minggu dari toko online',
        ),
      ],
    );
    await tester.runAsync(loadFonts);
    for (final loc in ['/email', '/email/inbox', '/email/rules']) {
      final env = _Env(repo: repo);
      tester.view.physicalSize = const Size(360, 740) * 2;
      await env.pump(tester, loc, dark: true, textScale: 1.3);
      tester.view.physicalSize = const Size(360, 740) * 2;
      await settle(tester);
      if (loc == '/email/inbox') {
        await tapKey(tester, 'inbox-draft-u1');
      }
      if (loc == '/email/rules') {
        await tapKey(tester, 'rules-add');
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('rule-match')),
            matching: find.text('Kata kunci'),
          ),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: loc);
      await tearDownApp(tester, env.c);
    }
  });
}
