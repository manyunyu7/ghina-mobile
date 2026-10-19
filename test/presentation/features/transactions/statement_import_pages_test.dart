// "Impor mutasi" pages (`/transactions/import`, `/transactions/import/:id`) on
// a fake StatementRepository, with the real wallet data layer from the
// feature harness. Never pumpAndSettle: the mascots animate forever. Names and
// numbers are made up.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/transactions/import/pages/statement_import_page.dart';
import 'package:ghina/presentation/features/transactions/import/pages/statement_imports_page.dart';
import 'package:ghina/presentation/state/killa_access_provider.dart';
import 'package:go_router/go_router.dart';

import '_feature_harness.dart';

StatementRow row(
  String id, {
  StatementVerdict verdict = StatementVerdict.isNew,
  StatementRowStatus status = StatementRowStatus.pending,
  String walletId = 'w1',
  double amount = 45000,
  TxType type = TxType.expense,
  StatementMatch? match,
  int idx = 0,
}) => StatementRow(
  id: id,
  idx: idx,
  date: DateTime(2026, 10, 5, 12),
  type: type,
  amount: amount,
  description: 'KARTU DEBIT $id',
  note: 'Catatan $id',
  walletId: walletId,
  wallet: 'Rekening Utama',
  category: 'Makan',
  verdict: verdict,
  status: status,
  reason: verdict == StatementVerdict.isNew ? null : 'Nominal dan tanggal sama',
  duplicateOf: match,
);

StatementImport imp({
  String id = 'i1',
  StatementStatus status = StatementStatus.ready,
  String? error,
  StatementCounts counts = const StatementCounts(),
}) => StatementImport(
  id: id,
  fileName: 'mutasi-oktober.pdf',
  status: status,
  error: error,
  wallet: 'Rekening Utama',
  bank: 'BCA',
  accountLast4: '1234',
  periodFrom: DateTime(2026, 10, 1),
  periodTo: DateTime(2026, 10, 31),
  summary: 'Killa nemu 4 transaksi.',
  counts: counts,
);

class FakeStatementRepository implements StatementRepository {
  FakeStatementRepository({
    List<StatementImport>? imports,
    List<StatementRow>? rows,
    this.status = StatementStatus.ready,
    this.error,
  }) : imports = imports ?? [],
       rows = rows ?? [];

  List<StatementImport> imports;
  List<StatementRow> rows;
  StatementStatus status;
  String? error;
  StatementException? listError;

  int detailCalls = 0;
  int retryCalls = 0;
  final approved = <List<String>>[];
  final ignored = <List<String>>[];
  final deleted = <String>[];
  final edits = <(String, StatementRowPatch)>[];
  final uploads = <StatementUpload>[];

  /// What the next uploads answer with, in order (the last one repeats).
  List<StatementException?> uploadScript = [null];

  @override
  Future<List<StatementImport>> list() async {
    if (listError != null) throw listError!;
    return List.of(imports);
  }

  @override
  Future<StatementDetail> detail(String id) async {
    detailCalls++;
    return StatementDetail(
      import: imp(id: id, status: status, error: error),
      rows: List.of(rows),
    );
  }

  @override
  Future<StatementImport> upload(StatementUpload upload) async {
    uploads.add(upload);
    final i = uploads.length - 1;
    final step =
        uploadScript[i < uploadScript.length ? i : uploadScript.length - 1];
    if (step != null) throw step;
    return imp(id: 'new1', status: StatementStatus.parsing);
  }

  @override
  Future<StatementImport> retry(String id) async {
    retryCalls++;
    status = StatementStatus.parsing;
    return imp(id: id, status: status);
  }

  @override
  Future<StatementRow> editRow(String rowId, StatementRowPatch patch) async {
    edits.add((rowId, patch));
    return rows.firstWhere((r) => r.id == rowId);
  }

  @override
  Future<int> approve(String id, List<String> rowIds) async {
    approved.add(rowIds);
    rows = [
      for (final r in rows)
        if (rowIds.contains(r.id))
          row(r.id, status: StatementRowStatus.approved)
        else
          r,
    ];
    return rowIds.length;
  }

  @override
  Future<void> ignore(String id, List<String> rowIds) async {
    ignored.add(rowIds);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    imports.removeWhere((i) => i.id == id);
  }
}

class _FakePicker implements KillaMediaPicker {
  _FakePicker(this.pdf);
  final KillaOutgoingMedia? pdf;

  @override
  Future<List<KillaOutgoingMedia>> pickPhotos({int max = 3}) async => const [];
  @override
  Future<KillaOutgoingMedia?> takePhoto() async => null;
  @override
  Future<List<KillaOutgoingMedia>> pickPdfs({int max = 3}) async => [?pdf];
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

final _pdf = KillaOutgoingMedia(
  name: 'mutasi-oktober.pdf',
  mimeType: 'application/pdf',
  bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
);

class _Env {
  _Env({FakeStatementRepository? repo})
    : repo = repo ?? FakeStatementRepository();

  final FakeStatementRepository repo;
  final sync = _CountingSync();
  late final ProviderContainer c = makeContainer(
    overrides: [
      statementRepositoryProvider.overrideWithValue(repo),
      killaMediaPickerProvider.overrideWithValue(_FakePicker(_pdf)),
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
  }) async {
    tester.view.physicalSize = const Size(390, 1800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/transactions',
          builder: (_, _) => const Scaffold(body: Text('TRANSAKSI')),
        ),
        GoRoute(
          path: '/transactions/import',
          builder: (_, s) =>
              StatementImportsPage(sharedPdfPath: s.extra as String?),
        ),
        GoRoute(
          path: '/transactions/import/:id',
          builder: (_, s) => StatementImportPage(id: s.pathParameters['id']!),
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

Future<void> tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
  await tester.pump(const Duration(seconds: 1)); // sheets finish closing
}

String buttonLabel(WidgetTester tester, String key) =>
    tester.widget<ChunkyButton>(find.byKey(Key(key))).label;

bool isChecked(WidgetTester tester, String rowId) =>
    tester.widget<Checkbox>(find.byKey(Key('statement-check-$rowId'))).value!;

final _match = StatementMatch(
  id: 't1',
  date: DateTime(2026, 10, 5),
  amount: 45000,
  note: 'Makan siang',
  wallet: 'Rekening Utama',
);

FakeStatementRepository _reviewRepo() => FakeStatementRepository(
  rows: [
    row('n1', idx: 0),
    row('n2', idx: 1),
    row('u1', idx: 2, verdict: StatementVerdict.uncertain, match: _match),
    row('d1', idx: 3, verdict: StatementVerdict.duplicate, match: _match),
    row('a1', idx: 4, status: StatementRowStatus.approved),
  ],
);

void main() {
  group('Review page', () {
    testWidgets('groups rows, checks only the new ones, saves the checked', (
      tester,
    ) async {
      final env = _Env(repo: _reviewRepo());
      await env.pump(tester, '/transactions/import/i1');

      expect(find.text('Baru · 2'), findsOneWidget);
      expect(find.text('Mungkin dobel · 1'), findsOneWidget);
      expect(find.text('Sudah tercatat · 1'), findsOneWidget);
      expect(find.text('Sudah diproses · 1'), findsOneWidget);
      // Header: bank, last 4, wallet and Killa's one-liner.
      expect(find.textContaining('BCA •1234'), findsWidgets);
      expect(find.text('Killa nemu 4 transaksi.'), findsOneWidget);

      expect(isChecked(tester, 'n1'), isTrue);
      expect(isChecked(tester, 'n2'), isTrue);
      expect(isChecked(tester, 'u1'), isFalse);
      // "Sudah tercatat" is collapsed; the approved row has no checkbox.
      expect(find.byKey(const Key('statement-row-d1')), findsNothing);
      expect(find.byKey(const Key('statement-check-a1')), findsNothing);
      // The uncertain row shows the matching transaction and the reason.
      expect(find.textContaining('Mirip: "Makan siang"'), findsOneWidget);
      expect(find.text('Nominal dan tanggal sama'), findsOneWidget);
      expect(buttonLabel(tester, 'statement-save'), 'Simpan 2 transaksi');

      await tap(tester, 'statement-check-u1');
      expect(buttonLabel(tester, 'statement-save'), 'Simpan 3 transaksi');

      await tap(tester, 'statement-save');
      expect(env.repo.approved, [
        ['n1', 'n2', 'u1'],
      ]);
      expect(find.text('3 transaksi tersimpan'), findsOneWidget);
      expect(env.sync.calls, 1);
      await tearDownApp(tester, env.c);
    });

    testWidgets('"Sudah tercatat" expands, rows unchecked', (tester) async {
      final env = _Env(repo: _reviewRepo());
      await env.pump(tester, '/transactions/import/i1');
      await tap(tester, 'statement-section-duplicate');
      expect(find.byKey(const Key('statement-row-d1')), findsOneWidget);
      expect(isChecked(tester, 'd1'), isFalse);
      await tearDownApp(tester, env.c);
    });

    testWidgets('"Abaikan sisanya" asks first, then ignores the unchecked', (
      tester,
    ) async {
      final env = _Env(repo: _reviewRepo());
      await env.pump(tester, '/transactions/import/i1');
      await tap(tester, 'statement-check-n2');
      await tap(tester, 'statement-ignore-rest');
      expect(find.text('Abaikan 3 baris?'), findsOneWidget);
      expect(env.repo.ignored, isEmpty);
      await tap(tester, 'statement-confirm');
      // n2 and u1 are unchecked and pending; d1 too.
      expect(env.repo.ignored.single, unorderedEquals(['n2', 'u1', 'd1']));
      await tearDownApp(tester, env.c);
    });

    testWidgets('editing a row sends only what changed', (tester) async {
      final env = _Env(repo: _reviewRepo());
      final wallet = await env.seedWallet(tester, 'Rekening Utama');
      env.repo.rows = [row('n1', walletId: wallet)];
      await env.pump(tester, '/transactions/import/i1');

      await tap(tester, 'statement-row-n1');
      expect(find.text('Edit baris'), findsOneWidget);
      // Nothing changed → nothing sent.
      await tap(tester, 'statement-edit-submit');
      expect(env.repo.edits, isEmpty);
      await tap(tester, 'statement-row-n1');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('statement-edit-amount')),
          matching: find.byType(EditableText),
        ),
        '50000',
      );
      await tap(tester, 'statement-edit-submit');
      expect(env.repo.edits, hasLength(1));
      final (id, patch) = env.repo.edits.single;
      expect(id, 'n1');
      expect(patch.amount, 50000);
      expect(patch.type, isNull);
      expect(patch.walletId, isNull);
      await tearDownApp(tester, env.c);
    });

    testWidgets('done: summary and the way back', (tester) async {
      final repo = FakeStatementRepository(
        status: StatementStatus.done,
        rows: [
          row('a1', status: StatementRowStatus.approved),
          row('i1', status: StatementRowStatus.ignored),
        ],
      );
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import/i1');
      expect(find.byKey(const Key('statement-done')), findsOneWidget);
      expect(find.byKey(const Key('statement-save')), findsNothing);
      await tap(tester, 'statement-back');
      expect(find.text('TRANSAKSI'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });
  });

  group('Parsing', () {
    testWidgets('polls every 4 s while parsing, stops on ready', (
      tester,
    ) async {
      final repo = FakeStatementRepository(
        status: StatementStatus.parsing,
        rows: [row('n1')],
      );
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import/i1');
      expect(find.text('Killa lagi baca mutasimu…'), findsOneWidget);
      expect(repo.detailCalls, 1);

      await tester.pump(const Duration(seconds: 3));
      expect(repo.detailCalls, 1);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(repo.detailCalls, 2);
      expect(find.text('Killa lagi baca mutasimu…'), findsOneWidget);

      repo.status = StatementStatus.ready;
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      expect(repo.detailCalls, 3);
      expect(find.text('Baru · 1'), findsOneWidget);

      // Ready: no more polling.
      await tester.pump(const Duration(seconds: 20));
      await settle(tester);
      expect(repo.detailCalls, 3);
      await tearDownApp(tester, env.c);
    });

    testWidgets('leaving the page stops the polling', (tester) async {
      final repo = FakeStatementRepository(status: StatementStatus.parsing);
      final env = _Env(repo: repo);
      final router = await env.pump(tester, '/home');
      router.push('/transactions/import/i1');
      await settle(tester);
      expect(repo.detailCalls, 1);

      router.pop();
      await settle(tester, 8);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(StatementImportPage), findsNothing);
      await tester.pump(const Duration(seconds: 12));
      await settle(tester);
      expect(repo.detailCalls, 1);
      await tearDownApp(tester, env.c);
    });

    testWidgets('failed: reason and "Coba lagi" starts a new run', (
      tester,
    ) async {
      final repo = FakeStatementRepository(
        status: StatementStatus.failed,
        error: 'Killa belum selesai membaca. Coba lagi.',
      );
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import/i1');
      expect(
        find.text('Killa belum selesai membaca. Coba lagi.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(ChunkyButton));
      await settle(tester);
      expect(repo.retryCalls, 1);
      expect(find.text('Killa lagi baca mutasimu…'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });
  });

  group('Imports page', () {
    testWidgets('lists imports with status chips', (tester) async {
      final repo = FakeStatementRepository(
        imports: [
          imp(),
          imp(id: 'i2', status: StatementStatus.parsing),
          imp(id: 'i3', status: StatementStatus.failed, error: 'Gagal baca.'),
          imp(id: 'i4', status: StatementStatus.done),
        ],
      );
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import');
      expect(find.text('Siap direview'), findsOneWidget);
      expect(find.text('Membaca…'), findsOneWidget);
      expect(find.text('Gagal'), findsOneWidget);
      expect(find.text('Selesai'), findsOneWidget);
      expect(find.text('Gagal baca.'), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('empty state and upload button', (tester) async {
      final env = _Env();
      await env.pump(tester, '/transactions/import');
      expect(find.byKey(const Key('statement-empty')), findsOneWidget);
      expect(buttonLabel(tester, 'statement-upload'), 'Unggah PDF');
      await tearDownApp(tester, env.c);
    });

    testWidgets('upload: password asked only when needed, never kept', (
      tester,
    ) async {
      final repo = FakeStatementRepository(status: StatementStatus.parsing);
      repo.uploadScript = [
        const StatementException(
          StatementErrorKind.passwordRequired,
          'PDF ini dikunci.',
        ),
        const StatementException(
          StatementErrorKind.passwordWrong,
          'Password-nya belum cocok. Coba lagi, ya.',
        ),
        null,
      ];
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import');
      await tap(tester, 'statement-upload');
      expect(find.text('mutasi-oktober.pdf'), findsWidgets);
      expect(find.text('Biar Killa yang tebak'), findsOneWidget);
      expect(find.byKey(const Key('statement-upload-password')), findsNothing);

      await tap(tester, 'statement-upload-submit');
      expect(repo.uploads.single.password, isNull);
      expect(
        find.byKey(const Key('statement-upload-password')),
        findsOneWidget,
      );
      expect(
        find.text('PDF ini dikunci. Masukkan password-nya — tidak disimpan.'),
        findsOneWidget,
      );

      Future<void> typePassword(String pw) => tester.enterText(
        find.descendant(
          of: find.byKey(const Key('statement-upload-password')),
          matching: find.byType(EditableText),
        ),
        pw,
      );
      await typePassword('salah');
      await tap(tester, 'statement-upload-submit');
      expect(repo.uploads.last.password, 'salah');
      expect(
        find.text('Password-nya belum cocok. Coba lagi, ya.'),
        findsOneWidget,
      );

      await typePassword('benar');
      await tap(tester, 'statement-upload-submit');
      expect(repo.uploads.last.password, 'benar');
      // Success → straight to the new import.
      expect(find.text('Killa lagi baca mutasimu…'), findsOneWidget);
      expect(repo.uploads, hasLength(3));
      await tearDownApp(tester, env.c);
    });

    testWidgets('upload answered 403 hides the entry for good', (tester) async {
      final repo = FakeStatementRepository();
      repo.uploadScript = [
        const StatementException(
          StatementErrorKind.forbidden,
          'Impor mutasi belum aktif untuk akun kamu.',
          status: 403,
        ),
      ];
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import');
      await tap(tester, 'statement-upload');
      await tap(tester, 'statement-upload-submit');
      expect(env.c.read(killaAccessProvider), KillaAccess.forbidden);
      expect(
        find.text('Impor mutasi belum aktif untuk akun kamu.'),
        findsOneWidget,
      );
      await tearDownApp(tester, env.c);
    });

    testWidgets('delete asks in a sheet, then removes the import', (
      tester,
    ) async {
      final repo = FakeStatementRepository(
        imports: [
          imp(),
          imp(id: 'i2'),
        ],
      );
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import');
      await tap(tester, 'statement-delete-i1');
      expect(find.text('Hapus impor ini?'), findsOneWidget);
      expect(repo.deleted, isEmpty);
      await tap(tester, 'statement-confirm');
      expect(repo.deleted, ['i1']);
      expect(find.byKey(const Key('statement-import-i1')), findsNothing);
      expect(find.byKey(const Key('statement-import-i2')), findsOneWidget);
      await tearDownApp(tester, env.c);
    });

    testWidgets('403 on the list: friendly message, no upload button', (
      tester,
    ) async {
      final repo = FakeStatementRepository()
        ..listError = const StatementException(
          StatementErrorKind.forbidden,
          'Impor mutasi belum aktif untuk akun kamu.',
          status: 403,
        );
      final env = _Env(repo: repo);
      await env.pump(tester, '/transactions/import');
      expect(find.byKey(const Key('statement-forbidden')), findsOneWidget);
      expect(find.byKey(const Key('statement-upload')), findsNothing);
      expect(env.c.read(killaAccessProvider), KillaAccess.forbidden);
      await tearDownApp(tester, env.c);
    });
  });

  group('Transactions page entry', () {
    testWidgets('"Impor mutasi" shows on Transaksi, not on a wallet history', (
      tester,
    ) async {
      final c = makeContainer();
      await pumpApp(tester, c, '/transactions');
      final button = find.byKey(const ValueKey('tx-import'));
      expect(button, findsOneWidget);
      expect(find.byTooltip('Impor mutasi'), findsOneWidget);

      // Known to be forbidden → hidden.
      await c.read(killaAccessProvider.notifier).markForbidden();
      await settle(tester);
      expect(button, findsNothing);
      await tearDownApp(tester, c);
    });

    testWidgets('the per-wallet history has no import button', (tester) async {
      final c = makeContainer();
      await pumpApp(tester, c, '/wallets/w1/history');
      expect(find.byKey(const ValueKey('tx-import')), findsNothing);
      await tearDownApp(tester, c);
    });
  });
}
