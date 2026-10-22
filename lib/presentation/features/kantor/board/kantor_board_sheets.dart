import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import 'kantor_board_data.dart';
import 'kantor_board_filter.dart';
import 'kantor_board_lib.dart';
import 'kantor_board_widgets.dart';
import 'kantor_card_detail.dart';

/// Pick the role that "Kartu saya" stands for; returns its id.
Future<String?> kPickMe(BuildContext context, KOffice office, String cur) =>
    kPickOne<String>(
      context,
      title: 'Saya adalah',
      current: cur,
      options: [
        for (final r in office.activeRoles)
          (
            value: r.id,
            label: '${r.name} · ${r.title}',
            leading: KWhoAvatar(office: office, who: r.id, size: 30),
          ),
      ],
    );

/// Everything the quick filters do not cover.
Future<void> showKantorFilterSheet(
  BuildContext context, {
  required String officeId,
}) {
  return showChunkyBottomSheet<void>(
    context,
    title: 'Filter',
    builder: (_) => _FilterBody(officeId: officeId),
  );
}

class _FilterBody extends ConsumerWidget {
  const _FilterBody({required this.officeId});
  final String officeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(kantorFilterProvider(officeId));
    final n = ref.read(kantorFilterProvider(officeId).notifier);
    final board = ref.watch(kantorBoardProvider(officeId)).value;
    final office = ref.watch(kantorOfficeProvider(officeId)).value;
    final g = context.ghina;
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t, style: GhinaType.overline.copyWith(color: g.textMuted)),
    );
    final repos = <String>{
      ...?office?.rooms.where((r) => r.isRepo).map((r) => r.id),
      ...?board?.cards.map((c) => c.repo).where((r) => r.isNotEmpty),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            head('PRIORITAS'),
            ChunkyChoiceChips<String>(
              multi: true,
              options: [
                for (final p in kantorPrios) ChunkyChoice(value: p, label: p),
              ],
              selected: f.prios,
              onChanged: (s) => n.update((x) => x.copyWith(prios: s)),
            ),
            head('PENANGGUNG JAWAB'),
            ChunkyChoiceChips<String>(
              multi: true,
              options: [
                const ChunkyChoice(
                  value: kantorNone,
                  label: 'Belum ditugaskan',
                ),
                for (final r in office?.activeRoles ?? <KRole>[])
                  ChunkyChoice(value: r.id, label: r.name),
              ],
              selected: f.who,
              onChanged: (s) => n.update((x) => x.copyWith(who: s)),
            ),
            if (board != null && board.labels.isNotEmpty) ...[
              head('LABEL'),
              ChunkyChoiceChips<String>(
                multi: true,
                options: [
                  for (final l in board.labels)
                    ChunkyChoice(value: l.id, label: l.name),
                ],
                selected: f.labels,
                onChanged: (s) => n.update((x) => x.copyWith(labels: s)),
              ),
            ],
            head('REPO'),
            ChunkyChoiceChips<String>(
              multi: true,
              options: [
                const ChunkyChoice(value: kantorNone, label: 'Tanpa repo'),
                for (final r in repos)
                  ChunkyChoice(value: r, label: office?.repoName(r) ?? r),
              ],
              selected: f.repos,
              onChanged: (s) => n.update((x) => x.copyWith(repos: s)),
            ),
            head('TENGGAT'),
            ChunkyChoiceChips<String>(
              options: const [
                ChunkyChoice(value: '', label: 'Semua'),
                ChunkyChoice(value: 'overdue', label: 'Terlambat'),
                ChunkyChoice(value: 'week', label: 'Pekan ini'),
                ChunkyChoice(value: 'none', label: 'Tanpa tenggat'),
              ],
              selected: {f.due},
              onChanged: (s) => n.update((x) => x.copyWith(due: s.first)),
            ),
            head('KELOMPOK'),
            ChunkyChoiceChips<String>(
              options: [
                for (final gr in kantorGroups)
                  ChunkyChoice(value: gr.$1, label: gr.$2),
              ],
              selected: {f.group},
              onChanged: (s) => n.update((x) => x.copyWith(group: s.first)),
            ),
            if (office != null) ...[
              head('SAYA ADALAH'),
              KFieldRow(
                label: 'Role',
                value: f.me.isEmpty ? '(belum dipilih)' : office.whoName(f.me),
                onTap: () async {
                  final r = await kPickMe(context, office, f.me);
                  if (r != null) n.update((x) => x.copyWith(me: r));
                },
              ),
            ],
            const SizedBox(height: GhinaSpace.lg),
            Row(
              children: [
                Expanded(
                  child: ChunkyButton(
                    label: 'Reset',
                    variant: ChunkyButtonVariant.outline,
                    onPressed: n.clear,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChunkyButton(
                    label: 'Selesai',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Judul #label @role !P1" into a column. Returns true if a card was made.
Future<void> showKantorQuickAdd(
  BuildContext context, {
  required String officeId,
  required int col,
  String? colName,
  String? boardId,
  Map<String, dynamic> base = const {},
}) {
  return showChunkyBottomSheet<void>(
    context,
    title:
        'Kartu baru di ${colName ?? kantorCols[col.clamp(0, kantorCols.length - 1)]}',
    builder: (_) => _QuickAddBody(
      officeId: officeId,
      col: col,
      base: {'board': ?boardId, ...base},
    ),
  );
}

class _QuickAddBody extends ConsumerStatefulWidget {
  const _QuickAddBody({
    required this.officeId,
    required this.col,
    required this.base,
  });
  final String officeId;
  final int col;
  final Map<String, dynamic> base;

  @override
  ConsumerState<_QuickAddBody> createState() => _QuickAddBodyState();
}

class _QuickAddBodyState extends ConsumerState<_QuickAddBody> {
  final _ctl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  KQuick _parse() {
    final board = ref.read(kantorBoardProvider(widget.officeId)).value;
    final office = ref.read(kantorOfficeProvider(widget.officeId)).value;
    return kParseQuick(
      _ctl.text,
      labels: board?.labels ?? const [],
      roles: [
        for (final r in office?.activeRoles ?? <KRole>[])
          (id: r.id, name: r.name),
      ],
    );
  }

  Future<void> _submit() async {
    final p = _parse();
    if (p.title.isEmpty) {
      kToast(context, 'Judul kartu kosong');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(kantorBoardProvider(widget.officeId).notifier).create({
        ...widget.base,
        'title': p.title,
        'col': widget.col,
        'labels': p.labels,
        'who': ?p.who,
        'prio': ?p.prio,
      });
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        kToast(context, '$e', bad: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'Judul #label @role !P1',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '#label, @role, dan !P0..!P3 dibaca otomatis.',
            style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
          ),
          const SizedBox(height: GhinaSpace.lg),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Lengkap',
                  variant: ChunkyButtonVariant.outline,
                  onPressed: _busy
                      ? null
                      : () {
                          final p = _parse();
                          Navigator.of(context).pop();
                          openKantorNewCard(
                            context,
                            officeId: widget.officeId,
                            col: widget.col,
                            board: widget.base['board'] as String?,
                            title: p.title,
                          );
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChunkyButton(
                  label: 'Buat',
                  loading: _busy,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "..." menu of a card: open, move, assign, priority, archive.
Future<void> showKantorCardActions(
  BuildContext context,
  WidgetRef ref, {
  required String officeId,
  required KCard card,
  required KOffice? office,
}) async {
  final notifier = ref.read(kantorBoardProvider(officeId).notifier);
  Future<void> run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) kToast(context, '$e', bad: true);
    }
  }

  final act = await showChunkyBottomSheet<String>(
    context,
    title: card.title.length > 40
        ? '${card.title.substring(0, 40)}…'
        : card.title,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (id, label, icon) in const [
          ('open', 'Buka detail', Icons.open_in_full_rounded),
          ('move', 'Pindah ke…', Icons.drive_file_move_rounded),
          ('who', 'Tugaskan…', Icons.person_add_alt_1_rounded),
          ('prio', 'Prioritas…', Icons.flag_rounded),
          ('archive', 'Arsipkan', Icons.archive_rounded),
        ])
          ListTile(
            leading: Icon(icon),
            title: Text(label, style: GhinaType.body.w(600)),
            onTap: () => Navigator.of(ctx).pop(id),
          ),
      ],
    ),
  );
  if (act == null || !context.mounted) return;
  switch (act) {
    case 'open':
      openKantorCard(context, officeId: officeId, cardId: card.id);
    case 'move':
      final b = ref.read(kantorBoardProvider(officeId)).value;
      final cols = b?.colsOf(card) ?? kantorDefaultColumns;
      final col = await kPickOne<int>(
        context,
        title: 'Pindah ke',
        current: card.col,
        options: [
          for (var i = 0; i < cols.length; i++)
            (value: i, label: cols[i].name, leading: null),
        ],
      );
      if (col != null && col != card.col) {
        final last = b?.cards
            .where((c) => !c.epic && c.board == card.board && c.col == col)
            .fold<KCard?>(
              null,
              (m, c) => m == null || c.ord > m.ord ? c : m,
            );
        await run(() => notifier.place([card.id], col, prevId: last?.id));
      }
    case 'who':
      final who = await kPickOne<String>(
        context,
        title: 'Tugaskan ke',
        current: card.who,
        options: [
          (value: kantorNone, label: 'Belum ditugaskan', leading: null),
          for (final r in office?.activeRoles ?? <KRole>[])
            (
              value: r.id,
              label: '${r.name} · ${r.title}',
              leading: KWhoAvatar(office: office, who: r.id, size: 30),
            ),
        ],
      );
      if (who != null) {
        final v = who == kantorNone ? '' : who;
        await run(
          () => notifier.patchCard(card.id, {
            'who': v.isEmpty ? null : v,
          }, local: (c) => c.copyWith(who: v)),
        );
      }
    case 'prio':
      final p = await kPickOne<String>(
        context,
        title: 'Prioritas',
        current: card.prio,
        options: [
          for (final p in kantorPrios) (value: p, label: p, leading: null),
        ],
      );
      if (p != null) await run(() => notifier.patchCard(card.id, {'prio': p}));
    case 'archive':
      final ok = await showChunkyConfirm(
        context,
        title: 'Arsipkan kartu?',
        message: 'Kartu "${card.title}" diarsipkan dari board.',
        confirmLabel: 'Arsipkan',
        destructive: true,
      );
      if (ok == true) await run(() => notifier.archive(card.id));
  }
}
