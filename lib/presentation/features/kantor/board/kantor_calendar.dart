import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'kantor_board_data.dart';
import 'kantor_board_lib.dart';
import 'kantor_board_widgets.dart';
import 'kantor_card_detail.dart';

/// Opens the publish calendar (cards by `publishAt`, else `due`).
Future<void> openKantorCalendar(
  BuildContext context, {
  required String officeId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => KantorCalendarScreen(officeId: officeId)),
);

const _monthNames = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', //
  'Agustus', 'September', 'Oktober', 'November', 'Desember',
];
const _dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Month grid of cards by publish date, colored by board.
class KantorCalendarScreen extends ConsumerStatefulWidget {
  const KantorCalendarScreen({super.key, required this.officeId});
  final String officeId;

  @override
  ConsumerState<KantorCalendarScreen> createState() =>
      _KantorCalendarScreenState();
}

class _KantorCalendarScreenState extends ConsumerState<KantorCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _day;

  /// Board filter; empty = all boards.
  String _board = '';

  String get id => widget.officeId;

  void _shift(int n) => setState(() {
    _month = DateTime(_month.year, _month.month + n);
    _day = null;
  });

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(kantorAllCardsProvider(id));
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Kalender tayang'),
        actions: [
          IconButton(
            tooltip: 'Bulan ini',
            icon: const Icon(Icons.today_rounded),
            onPressed: () => setState(() {
              final n = DateTime.now();
              _month = DateTime(n.year, n.month);
              _day = kTodayStr();
            }),
          ),
        ],
      ),
      body: async.when(
        loading: () => const KantorLoading(),
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kantorAllCardsProvider(id)),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(KBoard b) {
    final g = context.ghina;
    final cards = [
      for (final c in b.cards)
        if (c.calDay.isNotEmpty && (_board.isEmpty || c.board == _board)) c,
    ];
    final byDay = <String, List<KCard>>{};
    for (final c in cards) {
      (byDay[c.calDay] ??= []).add(c);
    }
    final first = DateTime(_month.year, _month.month);
    final lead = (first.weekday + 6) % 7; // Monday first
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((lead + days) / 7).ceil() * 7;
    final prefix = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    final monthCards = cards.where((c) => c.calDay.startsWith(prefix)).toList()
      ..sort((a, x) => a.calDay.compareTo(x.calDay));
    final shown = _day == null ? monthCards : (byDay[_day] ?? const <KCard>[]);
    final today = kTodayStr();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (b.boards.isNotEmpty)
          KChipStrip(
            children: [
              ChunkyChip(
                label: 'Semua papan',
                selected: _board.isEmpty,
                onTap: () => setState(() => _board = ''),
              ),
              for (final d in b.activeBoards)
                ChunkyChip(
                  label: d.icon.isEmpty ? d.name : '${d.icon} ${d.name}',
                  selected: _board == d.id,
                  onTap: () => setState(() => _board = d.id),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _shift(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Row(
                children: [
                  for (final d in _dayNames)
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var w = 0; w < cells ~/ 7; w++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var k = 0; k < 7; k++)
                      Expanded(
                        child: _cell(
                          w * 7 + k - lead + 1,
                          days,
                          byDay,
                          b,
                          today,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  (_day == null
                          ? 'Bulan ini (${shown.length})'
                          : '${kFmtDay(_day)} (${shown.length})')
                      .toUpperCase(),
                  style: GhinaType.overline.copyWith(color: g.textMuted),
                ),
              ),
              if (_day != null)
                TextButton(
                  onPressed: () => setState(() => _day = null),
                  child: const Text('Semua tanggal'),
                ),
            ],
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Belum ada kartu dengan tanggal tayang.',
              style: GhinaType.bodyS.copyWith(color: g.textMuted),
            ),
          ),
        for (final c in shown) _row(c, b),
      ],
    );
  }

  Widget _cell(
    int day,
    int days,
    Map<String, List<KCard>> byDay,
    KBoard b,
    String today,
  ) {
    final g = context.ghina;
    if (day < 1 || day > days) return const SizedBox(height: 64);
    final key = kDayStr(DateTime(_month.year, _month.month, day));
    final list = byDay[key] ?? const <KCard>[];
    final sel = _day == key;
    return GestureDetector(
      onTap: () => setState(() => _day = sel ? null : key),
      child: Container(
        height: 64,
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: sel ? GhinaColors.blue.tint(g.brightness) : g.surfaceAlt,
          borderRadius: GhinaRadii.rMd,
          border: key == today
              ? Border.all(color: GhinaColors.blue.base, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$day',
              style: GhinaType.caption
                  .w(key == today ? 800 : 600)
                  .copyWith(color: g.textSecondary),
            ),
            for (final c in list.take(3))
              Container(
                height: 9,
                width: double.infinity,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: kBoardColor(
                    b.boardDef(c.board),
                  ).withValues(alpha: c.done ? 0.35 : 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            if (list.length > 3)
              Text(
                '+${list.length - 3}',
                style: GhinaType.caption.copyWith(
                  color: g.textMuted,
                  fontSize: 9,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(KCard c, KBoard b) {
    final g = context.ghina;
    final def = b.boardDef(c.board);
    final isPublish = isKDate(c.publishAt);
    return ListTile(
      leading: Container(
        width: 6,
        height: 36,
        decoration: BoxDecoration(
          color: kBoardColor(def),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(
        c.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GhinaType.body
            .w(700)
            .copyWith(
              color: g.textPrimary,
              decoration: c.done ? TextDecoration.lineThrough : null,
            ),
      ),
      subtitle: Text(
        [
          '${isPublish ? 'Tayang' : 'Tenggat'} ${kFmtDay(c.calDay)}',
          ?def?.name,
          b.colNameOf(c),
        ].join(' · '),
        style: GhinaType.caption.copyWith(color: g.textMuted),
      ),
      trailing: c.coverUrl == null
          ? null
          : SizedBox(
              width: 48,
              child: KCardCover(url: c.coverUrl!, height: 40),
            ),
      onTap: () => openKantorCard(context, officeId: id, cardId: c.id),
    );
  }
}
