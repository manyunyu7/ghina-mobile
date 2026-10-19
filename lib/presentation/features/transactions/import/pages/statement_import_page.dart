import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../di/di.dart';
import '../../../../../domain/entities/entities.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../state/session_controller.dart' show currencyProvider;
import '../statement_state.dart';
import '../widgets/statement_confirm_sheet.dart';
import '../widgets/statement_row_edit_sheet.dart';
import '../widgets/statement_row_tile.dart';

/// How often a `parsing` import is refetched while its page is open.
const statementPollInterval = Duration(seconds: 4);

/// One import (`/transactions/import/:id`): Killa reading the PDF, then the
/// review of its rows. Nothing becomes a transaction until the user saves;
/// saving creates normal transactions on the server, which arrive here with
/// the sync pull.
class StatementImportPage extends ConsumerStatefulWidget {
  const StatementImportPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<StatementImportPage> createState() =>
      _StatementImportPageState();
}

class _StatementImportPageState extends ConsumerState<StatementImportPage> {
  /// Checked state per row id; rows are seeded once (new → checked), so the
  /// user's toggles survive refetches.
  final Map<String, bool> _checked = {};
  Timer? _poll;
  bool _pollStarted = false;
  bool _busy = false;
  bool _duplicatesOpen = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Keeps polling while Killa is reading; stops on any other status.
  void _schedulePoll(AsyncValue<StatementDetail> v) {
    if (v.isLoading) return; // a fetch is in flight; wait for its answer
    _poll?.cancel();
    _poll = null;
    if (v.value?.import.status != StatementStatus.parsing) return;
    _poll = Timer(statementPollInterval, () {
      if (mounted) ref.invalidate(statementDetailProvider(widget.id));
    });
  }

  void _seed(List<StatementRow> rows) {
    for (final r in rows) {
      _checked.putIfAbsent(
        r.id,
        () => r.pending && r.verdict == StatementVerdict.isNew,
      );
    }
  }

  void _refresh() => ref.invalidate(statementDetailProvider(widget.id));

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } on StatementException catch (e) {
      if (!mounted) return;
      showErrorToast(context, e.message);
      if (e.kind == StatementErrorKind.conflict ||
          e.kind == StatementErrorKind.notFound) {
        _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() => _run(() async {
    await ref.read(statementRepositoryProvider).retry(widget.id);
    if (!mounted) return;
    invalidateStatements(ref);
  });

  Future<void> _approve(List<StatementRow> rows) => _run(() async {
    final ids = [
      for (final r in rows)
        if (r.pending && _checked[r.id] == true) r.id,
    ];
    if (ids.isEmpty) return;
    final n = await ref
        .read(statementRepositoryProvider)
        .approve(widget.id, ids);
    if (!mounted) return;
    showOkToast(context, '$n transaksi tersimpan');
    invalidateStatements(ref);
    // Pull the new transactions onto the phone.
    unawaited(ref.read(syncNowProvider)());
  });

  Future<void> _ignoreRest(List<StatementRow> rows) async {
    final ids = [
      for (final r in rows)
        if (r.pending && _checked[r.id] != true) r.id,
    ];
    if (ids.isEmpty) return;
    final ok = await showStatementConfirmSheet(
      context,
      title: 'Abaikan ${ids.length} baris?',
      message:
          'Baris yang nggak dicentang ditandai diabaikan dan nggak jadi '
          'transaksi.',
      confirmLabel: 'Abaikan',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(statementRepositoryProvider).ignore(widget.id, ids);
      if (!mounted) return;
      showOkToast(context, '${ids.length} baris diabaikan');
      invalidateStatements(ref);
    });
  }

  Future<void> _edit(StatementRow row) async {
    final patch = await showStatementRowEditSheet(
      context,
      row: row,
      wallets: ref.read(watchWalletsProvider).value ?? const [],
      categories: ref.read(watchCategoriesProvider(null)).value ?? const [],
      currency: ref.read(currencyProvider),
    );
    if (patch == null || patch.isEmpty || !mounted) return;
    await _run(() async {
      await ref.read(statementRepositoryProvider).editRow(row.id, patch);
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(statementDetailProvider(widget.id));
    ref.listen(
      statementDetailProvider(widget.id),
      (_, next) => _schedulePoll(next),
    );
    if (!_pollStarted && !async.isLoading) {
      _pollStarted = true;
      _schedulePoll(async);
    }
    // Kept alive for the edit sheet (it reads them when a row is tapped).
    ref.watch(watchWalletsProvider);
    ref.watch(watchCategoriesProvider(null));
    final detail = async.value;
    if (detail != null) _seed(detail.rows);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Impor mutasi')),
      body: detail == null
          ? switch (async) {
              AsyncError(:final error) => ScrollableFill(
                child: ErrorRetry(
                  message: statementErrorMessage(error),
                  onRetry: _refresh,
                ),
              ),
              _ => const LoadingListView(hero: false, tiles: 3),
            }
          : _body(detail),
    );
  }

  Widget _body(StatementDetail d) {
    final i = d.import;
    return switch (i.status) {
      StatementStatus.parsing => RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(statementDetailProvider(widget.id).future),
        child: const ScrollableFill(
          child: Column(
            key: Key('statement-parsing'),
            mainAxisSize: MainAxisSize.min,
            children: [
              MascotView(mood: MascotMood.thinking, size: 140),
              SizedBox(height: 16),
              _CenterText(
                title: 'Killa lagi baca mutasimu…',
                message:
                    'Biasanya 1–4 menit. Boleh ditinggal ke layar lain: '
                    'statusnya kelihatan di halaman Transaksi, dan tombol '
                    'Impor mutasi dapat tanda begitu siap direview.',
              ),
            ],
          ),
        ),
      ),
      StatementStatus.failed => RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(statementDetailProvider(widget.id).future),
        child: ScrollableFill(
          child: EmptyState(
            key: const Key('statement-failed'),
            mood: MascotMood.sad,
            title: 'Mutasinya belum kebaca',
            message: i.error ?? 'Killa belum bisa membaca PDF ini.',
            actionLabel: _busy ? null : 'Coba lagi',
            onAction: _retry,
          ),
        ),
      ),
      _ => _review(d),
    };
  }

  Widget _review(StatementDetail d) {
    final g = context.ghina;
    final currency = ref.watch(currencyProvider);
    final rows = d.rows;
    List<StatementRow> pending(StatementVerdict v) => [
      for (final r in rows)
        if (r.pending && r.verdict == v) r,
    ];
    final fresh = pending(StatementVerdict.isNew);
    final maybe = pending(StatementVerdict.uncertain);
    final known = pending(StatementVerdict.duplicate);
    final decided = [
      for (final r in rows)
        if (!r.pending) r,
    ];
    final pendingCount = fresh.length + maybe.length + known.length;
    final selected = [
      for (final r in rows)
        if (r.pending && _checked[r.id] == true) r,
    ];

    Widget tile(StatementRow r) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StatementRowTile(
        row: r,
        currency: currency,
        checked: _checked[r.id] == true,
        onChecked: (v) => setState(() => _checked[r.id] = v),
        onTap: () => _edit(r),
      ),
    );

    final done = d.import.status == StatementStatus.done || pendingCount == 0;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(statementDetailProvider(widget.id).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                4,
                GhinaSpace.page,
                24,
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _Header(import: d.import),
                const SizedBox(height: 16),
                if (done) _DoneCard(counts: d.import.counts),
                if (fresh.isNotEmpty) ...[
                  _SectionTitle(
                    key: const Key('statement-section-new'),
                    title: 'Baru',
                    count: fresh.length,
                    hint: 'Belum ada di Ghina',
                  ),
                  for (final r in fresh) tile(r),
                ],
                if (maybe.isNotEmpty) ...[
                  _SectionTitle(
                    key: const Key('statement-section-uncertain'),
                    title: 'Mungkin dobel',
                    count: maybe.length,
                    hint: 'Cek dulu, mirip transaksi yang sudah ada',
                  ),
                  for (final r in maybe) tile(r),
                ],
                if (known.isNotEmpty) ...[
                  _SectionTitle(
                    key: const Key('statement-section-duplicate'),
                    title: 'Sudah tercatat',
                    count: known.length,
                    hint: 'Sudah ada di Ghina',
                    open: _duplicatesOpen,
                    onToggle: () =>
                        setState(() => _duplicatesOpen = !_duplicatesOpen),
                  ),
                  if (_duplicatesOpen)
                    for (final r in known) tile(r),
                ],
                if (decided.isNotEmpty) ...[
                  _SectionTitle(
                    key: const Key('statement-section-decided'),
                    title: 'Sudah diproses',
                    count: decided.length,
                  ),
                  for (final r in decided) tile(r),
                ],
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      'Killa nggak nemu transaksi di PDF ini.',
                      textAlign: TextAlign.center,
                      style: GhinaType.body.copyWith(color: g.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              12,
            ),
            child: pendingCount == 0
                ? ChunkyButton(
                    key: const Key('statement-back'),
                    label: 'Balik ke transaksi',
                    icon: Icons.receipt_long_rounded,
                    size: ChunkyButtonSize.large,
                    onPressed: () => context.go('/transactions'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ChunkyButton(
                        key: const Key('statement-save'),
                        label: 'Simpan ${selected.length} transaksi',
                        icon: Icons.check_rounded,
                        size: ChunkyButtonSize.large,
                        loading: _busy,
                        onPressed: _busy || selected.isEmpty
                            ? null
                            : () => _approve(rows),
                      ),
                      const SizedBox(height: 4),
                      ChunkyButton(
                        key: const Key('statement-ignore-rest'),
                        label: 'Abaikan sisanya',
                        variant: ChunkyButtonVariant.ghost,
                        size: ChunkyButtonSize.small,
                        onPressed: _busy || selected.length == pendingCount
                            ? null
                            : () => _ignoreRest(rows),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _CenterText extends StatelessWidget {
  const _CenterText({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GhinaType.body.copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Bank, account, period, the statement's wallet and Killa's one-liner.
class _Header extends StatelessWidget {
  const _Header({required this.import});

  final StatementImport import;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final i = import;
    final caption = statementCaption(i);
    return ChunkyCard(
      key: const Key('statement-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption.isEmpty ? i.fileName : caption,
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (caption.isNotEmpty) i.fileName,
              if (i.wallet != null) 'Rekening: ${i.wallet}',
            ].join(' · '),
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
          if (i.summary != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: GhinaColors.purple.base,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i.summary!,
                    style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.counts});

  final StatementCounts counts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: ChunkyCard(
      key: const Key('statement-done'),
      tinted: GhinaColors.green,
      child: Row(
        children: [
          const MascotView(mood: MascotMood.happy, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Beres! ${counts.approved} transaksi tersimpan, '
              '${counts.ignored} diabaikan.',
              style: GhinaType.body.w(800),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    super.key,
    required this.title,
    required this.count,
    this.hint,
    this.open,
    this.onToggle,
  });

  final String title;
  final int count;
  final String? hint;

  /// Collapsible sections: current state and toggle.
  final bool? open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final head = Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title · $count',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          if (open != null)
            Icon(
              open! ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: g.textSecondary,
            ),
        ],
      ),
    );
    return onToggle == null ? head : InkWell(onTap: onToggle, child: head);
  }
}
