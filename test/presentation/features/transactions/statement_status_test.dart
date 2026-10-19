// "Impor mutasi" status outside its own pages: StatementAttention (what gets
// flagged), the badge on the Transactions app bar button and the status cards,
// fed by a fake StatementRepository. Never pumpAndSettle: the parsing spinner
// spins forever. Names and numbers are made up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/transactions/import/statement_state.dart';
import 'package:ghina/presentation/features/transactions/import/widgets/statement_status.dart';
import 'package:ghina/presentation/state/killa_access_provider.dart';

import 'statement_import_pages_test.dart' show FakeStatementRepository, imp;

class _CountingRepo extends FakeStatementRepository {
  _CountingRepo(List<StatementImport> imports) : super(imports: imports);

  int listCalls = 0;

  @override
  Future<List<StatementImport>> list() {
    listCalls++;
    return super.list();
  }
}

StatementImport _at(
  String id,
  StatementStatus status, {
  DateTime? updatedAt,
  int pending = 0,
}) => StatementImport(
  id: id,
  fileName: '$id.pdf',
  status: status,
  updatedAt: updatedAt,
  counts: StatementCounts(pending: pending),
);

void main() {
  group('StatementAttention.of', () {
    final now = DateTime(2026, 10, 19, 20);

    test('flags imports being read, ready ones with rows left and recent '
        'failures; ready first, then failed, then parsing', () {
      final a = StatementAttention.of([
        _at('p', StatementStatus.parsing),
        _at('r', StatementStatus.ready, pending: 3),
        _at('r0', StatementStatus.ready),
        _at('d', StatementStatus.done),
        _at(
          'f',
          StatementStatus.failed,
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
        _at(
          'old',
          StatementStatus.failed,
          updatedAt: now.subtract(const Duration(days: 4)),
        ),
      ], now);
      expect([for (final i in a.items) i.id], ['r', 'f', 'p']);
      expect(a.isEmpty, isFalse);
    });

    test('nothing to flag → empty', () {
      final a = StatementAttention.of([_at('d', StatementStatus.done)], now);
      expect(a.isEmpty, isTrue);
      expect(StatementAttention.none.items, isEmpty);
    });
  });

  group('badge + status cards', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      _CountingRepo repo,
    ) async {
      final c = ProviderContainer(
        overrides: [
          statementRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(
            FixedClock(DateTime(2026, 10, 19, 20)),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(
              appBar: AppBar(actions: const [StatementImportButton()]),
              body: const SingleChildScrollView(child: StatementStatusCards()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    // Unmount and dispose inside the test body: the poll timer and drift's
    // stream timers must be gone before flutter_test checks for pending ones.
    Future<void> done(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('being read → blue dot + card; turns ready on its own, then '
        'stops polling', (tester) async {
      final repo = _CountingRepo([
        imp(id: 'p1', status: StatementStatus.parsing),
      ]);
      final c = await pump(tester, repo);
      expect(find.byKey(const ValueKey('tx-import-badge-parsing')), findsOne);
      expect(find.byKey(const Key('statement-status-p1')), findsOne);
      expect(find.text('Killa lagi baca mutasimu…'), findsOne);

      repo.imports = [
        imp(
          id: 'p1',
          counts: const StatementCounts(total: 3, newRows: 3, pending: 3),
        ),
      ];
      await tester.pump(statementAttentionPoll);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tx-import-badge-ready')), findsOne);
      expect(find.text('1'), findsOne);
      expect(find.text('Mutasi siap direview'), findsOne);
      expect(find.textContaining('3 baris nunggu keputusanmu'), findsOne);

      final calls = repo.listCalls;
      await tester.pump(statementAttentionPoll * 3);
      expect(repo.listCalls, calls, reason: 'nothing is being read');
      await done(tester, c);
    });

    testWidgets('failed → red dot + card; more than two → "Lihat semua"', (
      tester,
    ) async {
      final repo = _CountingRepo([
        imp(
          id: 'a',
          status: StatementStatus.failed,
          error: 'Rekening tidak ketemu',
        ),
        imp(id: 'b', status: StatementStatus.parsing),
        imp(id: 'c', status: StatementStatus.parsing),
      ]);
      final c = await pump(tester, repo);
      expect(find.byKey(const ValueKey('tx-import-badge-failed')), findsOne);
      expect(find.text('Impor mutasi gagal'), findsOne);
      expect(find.text('Rekening tidak ketemu'), findsOne);
      expect(find.byKey(const Key('statement-status-b')), findsOne);
      expect(find.byKey(const Key('statement-status-c')), findsNothing);
      expect(find.text('Lihat semua impor (+1)'), findsOne);
      await done(tester, c);
    });

    testWidgets(
      'nothing pending, offline or no Killa → plain button, no card',
      (tester) async {
        final repo = _CountingRepo([
          imp(id: 'd', status: StatementStatus.done),
        ]);
        final c0 = await pump(tester, repo);
        expect(find.byKey(const ValueKey('tx-import')), findsOne);
        expect(find.byType(Badge), findsNothing);
        expect(find.byType(ChunkyCard), findsNothing);
        await done(tester, c0);

        final forbidden =
            _CountingRepo([imp(id: 'p', status: StatementStatus.parsing)])
              ..listError = const StatementException(
                StatementErrorKind.forbidden,
                'no',
              );
        final c = await pump(tester, forbidden);
        expect(find.byType(Badge), findsNothing);
        expect(find.byType(ChunkyCard), findsNothing);
        expect(c.read(killaAccessProvider), KillaAccess.forbidden);
        await done(tester, c);
      },
    );
  });
}
