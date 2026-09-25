import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../habit_format.dart';
import '../lock/habit_lock_gate.dart';
import '../widgets/habit_cards.dart';
import '../widgets/habit_insight_widgets.dart';

/// One habit: streak ring + milestones, today's controls, heatmap
/// (month/year), completion by range, streak history, insights, journal and
/// the log list.
class HabitDetailPage extends StatelessWidget {
  const HabitDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) =>
      HabitLockGate(child: _DetailView(id: id));
}

enum _Range {
  d30(30, '30 hari'),
  d90(90, '90 hari'),
  y1(365, '1 tahun');

  const _Range(this.days, this.label);
  final int days;
  final String label;
}

class _DetailView extends ConsumerStatefulWidget {
  const _DetailView({required this.id});

  final String id;

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  _Range _range = _Range.d30;
  bool _year = false;
  late YearMonth _month = YearMonth.of(ref.read(clockProvider).now());

  Future<void> _archive(Habit h) async {
    final r = await ref.read(setHabitArchivedProvider)(h.id, !h.archived);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          h.archived ? 'Aktif lagi 👍' : 'Diarsipkan. Riwayatnya tetap aman.',
        );
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete(Habit h) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus "${h.name}"?',
      message:
          'Semua catatan dan jurnalnya ikut terhapus permanen. '
          'Kalau cuma mau rehat, arsipkan saja.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteHabitProvider)(h.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Kebiasaan dihapus');
        popOr(context, '/habits');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).now();
    final detail = ref.watch(
      watchHabitDetailProvider((
        id: widget.id,
        range: habitRangeLastDays(now, _range.days),
      )),
    );
    final d = detail.value;
    final h = d?.habit;

    return Scaffold(
      appBar: AppBar(
        title: Text(h?.name ?? 'Kebiasaan', overflow: TextOverflow.ellipsis),
        actions: [
          if (h != null) ...[
            IconButton(
              key: const ValueKey('habit-edit'),
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => context.push('/habits/${h.id}/edit'),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('habit-menu'),
              onSelected: (v) => v == 'archive' ? _archive(h) : _delete(h),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Text(h.archived ? 'Aktifkan lagi' : 'Arsipkan'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Hapus')),
              ],
            ),
          ],
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => pullToSync(context, ref),
          child: switch (detail) {
            AsyncValue(:final value?) => _content(context, value, now),
            AsyncValue(hasValue: true) => const ScrollableFill(
              child: EmptyState(
                title: 'Kebiasaan nggak ditemukan',
                message: 'Mungkin sudah dihapus di perangkat lain.',
              ),
            ),
            AsyncError() => ScrollableFill(
              child: ErrorRetry(
                onRetry: () => ref.invalidate(watchHabitDetailProvider),
              ),
            ),
            _ => const LoadingListView(tiles: 4, hero: true),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, HabitDetail d, DateTime now) {
    final h = d.habit;
    final t = d.today;
    final sw = habitSwatch(h);
    final ins = d.insights;
    final heat = _year
        ? ref.watch(
            watchHabitDetailProvider((
              id: h.id,
              range: habitRangeLastDays(now, 365),
            )),
          )
        : ref.watch(
            watchHabitDetailProvider((
              id: h.id,
              range: habitRangeOfMonth(_month),
            )),
          );
    final heatCells = heat.value?.insights.heatmap;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      children: [
        _Hero(today: t, urgesTotal: h.isQuit ? ins.urges.total : null),
        GhinaSpace.gapLg,
        if (h.archived)
          ChunkyCard(
            tinted: GhinaColors.gray,
            child: Text(
              'Kebiasaan ini diarsipkan. Aktifkan lagi dari menu ⋮ untuk lanjut check-in.',
              style: GhinaType.bodyS.copyWith(
                color: context.ghina.textSecondary,
              ),
            ),
          )
        else if (h.isBuild)
          BuildHabitCard(today: t, linkToDetail: false)
        else
          QuitActions(today: t),
        GhinaSpace.gapXl,
        const SectionHeader(title: 'Target streak'),
        _Milestones(streak: t.streak),
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Kalender',
          trailing: ChunkyChoiceChips<bool>(
            options: const [
              ChunkyChoice(value: false, label: 'Bulan'),
              ChunkyChoice(value: true, label: 'Tahun'),
            ],
            selected: {_year},
            onChanged: (s) => setState(() => _year = s.first),
          ),
        ),
        ChunkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_year) ...[
                MonthSwitcher(
                  value: _month,
                  current: YearMonth.of(now),
                  onChanged: (m) => setState(() => _month = m),
                ),
                GhinaSpace.gapMd,
              ],
              if (heatCells == null)
                const Skeleton(height: 180, radius: 16)
              else if (_year)
                YearHeatmap(cells: heatCells, color: sw)
              else
                MonthHeatmap(
                  cells: heatCells,
                  color: sw,
                  onTapDay: (c) => _showDay(context, h, c),
                ),
              GhinaSpace.gapMd,
              HeatmapLegend(kind: h.kind, color: sw),
            ],
          ),
        ),
        GhinaSpace.gapXl,
        SectionHeader(title: h.isQuit ? 'Hari bersih' : 'Tingkat keberhasilan'),
        ChunkySegmented<_Range>(
          segments: [
            for (final r in _Range.values)
              ChunkySegment(value: r, label: r.label),
          ],
          value: _range,
          onChanged: (r) => setState(() => _range = r),
          height: 42,
        ),
        GhinaSpace.gapMd,
        _Completion(insights: ins, habit: h),
        if (ins.streakHistory.length > 1) ...[
          GhinaSpace.gapXl,
          const SectionHeader(title: 'Riwayat streak'),
          ChunkyCard(
            child: StreakHistoryChart(points: ins.streakHistory, color: sw),
          ),
        ],
        GhinaSpace.gapXl,
        const SectionHeader(title: 'Insight'),
        _Insights(insights: ins, habit: h),
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Jurnal',
          actionLabel: 'Tulis hari ini',
          onAction: () => _editJournal(context, h, dateKey(now), null),
        ),
        _Journal(
          entries: ins.journal,
          today: dateKey(now),
          onEdit: (e) => _editJournal(context, h, e.date, e),
        ),
        GhinaSpace.gapXl,
        const SectionHeader(title: 'Catatan harian'),
        _LogList(logs: d.logs, habit: h, today: dateKey(now)),
      ],
    );
  }

  void _showDay(BuildContext context, Habit h, HabitDayCell c) {
    final parts = [
      heatmapStateLabel(c.state),
      if (h.isBuild && c.value != null) progressLabel(h.target, c.value),
      if (c.urges > 0) '${c.urges}× godaan ditahan',
      if (c.relapses > 0) '${c.relapses}× kambuh',
      if (c.cleanCheckIn) 'check-in bersih ✅',
    ];
    showToastBadge(
      context,
      message: '${habitLongDate(c.date)}: ${parts.join(' · ')}',
      icon: Icons.event_rounded,
      color: habitSwatch(h),
    );
  }

  Future<void> _editJournal(
    BuildContext context,
    Habit h,
    String day,
    HabitJournalEntry? entry,
  ) async {
    final text = await showChunkyBottomSheet<String>(
      context,
      title: entry == null
          ? 'Jurnal hari ini'
          : 'Jurnal · ${habitDayLabel(day, dateKey(ref.read(clockProvider).now()))}',
      showClose: true,
      builder: (_) => _JournalSheet(initial: entry?.note ?? ''),
    );
    if (text == null || !context.mounted) return;
    final r = await ref.read(setHabitJournalProvider)(
      h.id,
      parseDateKey(day),
      text.isEmpty ? null : text,
      type: entry?.type,
    );
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Jurnal tersimpan ✍️');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.today, this.urgesTotal});

  final HabitToday today;
  final int? urgesTotal;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final h = today.habit;
    final s = today.streak;
    final quit = h.isQuit;
    final ringColor = quit ? GhinaColors.green : GhinaColors.orange;
    return ChunkyCard(
      child: Column(
        children: [
          Row(
            children: [
              HabitAvatar(habit: h, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.name,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    Text(
                      [
                        quit ? 'Berhenti' : scheduleLabel(h.schedule),
                        if (!quit && !h.target.isCheck) targetLabel(h.target),
                        if (h.isPrivate) 'Pribadi 🔒',
                      ].join(' · '),
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          GhinaSpace.gapLg,
          ProgressRing(
            key: const ValueKey('habit-streak-ring'),
            value: milestoneFraction(s),
            size: 168,
            stroke: 14,
            color: ringColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quit)
                  Icon(Icons.park_rounded, color: ringColor.base, size: 28)
                else
                  StreakFlame(count: s.current, showCount: false, size: 28),
                Text(
                  '${s.current}',
                  style: GhinaType.display
                      .w(900)
                      .copyWith(color: g.textPrimary),
                  textScaler: TextScaler.noScaling,
                ),
                Text(
                  quit ? 'hari bersih' : '${s.unit.label} beruntun',
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(color: g.textSecondary),
                  textScaler: TextScaler.noScaling,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            today.relapsedToday
                ? 'Hari bersih barumu dimulai besok 🌱'
                : nextMilestoneLine(s),
            textAlign: TextAlign.center,
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
          if (quit && s.current > 0)
            Text(
              'hari ini masih berjalan',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          GhinaSpace.gapLg,
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.emoji_events_rounded,
                  value: '${s.longest} ${s.unit.label}',
                  label: 'Terpanjang',
                  color: GhinaColors.yellow,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: urgesTotal != null
                    ? StatTile(
                        icon: Icons.shield_rounded,
                        value: '$urgesTotal×',
                        label: 'Godaan ditahan',
                        color: GhinaColors.blue,
                      )
                    : StatTile(
                        icon: Icons.event_rounded,
                        value: habitDayLabel(h.startDate, today.date),
                        label: 'Mulai',
                        color: GhinaColors.blue,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones({required this.streak});

  final HabitStreak streak;

  @override
  Widget build(BuildContext context) {
    final quit = streak.kind == HabitKind.quit;
    final best = streak.longest > streak.current
        ? streak.longest
        : streak.current;
    final list = quit
        ? [...quitMilestones, for (var m = 400; m <= best + 100; m += 100) m]
        : buildMilestones;
    final sw = quit ? GhinaColors.green : GhinaColors.orange;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in list)
          ChunkyPill(
            key: ValueKey('milestone-$m'),
            label: '$m ${streak.unit.label}',
            color: m <= best ? sw : GhinaColors.gray,
            soft: m > streak.current,
            icon: m <= best ? Icons.check_rounded : null,
            uppercase: false,
          ),
      ],
    );
  }
}

class _Completion extends StatelessWidget {
  const _Completion({required this.insights, required this.habit});

  final HabitInsights insights;
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = insights.completion;
    final rate = c.rate;
    final pct = rate == null ? null : (rate * 100).round();
    final unit = habit.isBuild && habit.schedule.isPerWeek ? 'minggu' : 'hari';
    return ChunkyCard(
      child: Row(
        children: [
          ProgressRing(
            value: rate ?? 0,
            size: 76,
            stroke: 9,
            color: habitSwatch(habit),
            child: Text(
              pct == null ? '–' : '$pct%',
              key: const ValueKey('habit-completion'),
              style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
              textScaler: TextScaler.noScaling,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              rate == null
                  ? 'Belum ada hari yang dinilai di rentang ini.'
                  : habit.isQuit
                  ? '${c.met} dari ${c.total} hari bersih'
                  : '${c.met} dari ${c.total} $unit terjadwal tercapai',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({required this.insights, required this.habit});

  final HabitInsights insights;
  final Habit habit;

  static final _hourLabels = [
    for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : '',
  ];

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = habitSwatch(habit);
    if (habit.isBuild) {
      final byDay = List.filled(7, 0);
      for (final c in insights.heatmap) {
        if (c.state == HabitDayState.met) {
          byDay[parseDateKey(c.date).weekday - 1]++;
        }
      }
      final any = byDay.any((v) => v > 0);
      return ChunkyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hari paling rajin',
              style: GhinaType.h3.copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: 8),
            if (any)
              MiniBars(values: byDay, labels: weekdaysShort, color: sw)
            else
              Text(
                'Belum ada data. Check-in beberapa hari dulu, ya.',
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
          ],
        ),
      );
    }
    final rel = insights.relapses;
    final urg = insights.urges;
    final hasEvents = rel.total + urg.total > 0;
    final weekday = [
      for (var i = 0; i < 7; i++) rel.byWeekday[i] + urg.byWeekday[i],
    ];
    final hours = [for (var i = 0; i < 24; i++) rel.byHour[i] + urg.byHour[i]];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.shield_rounded,
                value: '${urg.total}',
                label: 'Godaan ditahan',
                color: GhinaColors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.refresh_rounded,
                value: '${rel.total}',
                label: 'Kambuh',
                color: GhinaColors.gray,
              ),
            ),
          ],
        ),
        GhinaSpace.gapMd,
        ChunkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kapan rasa pengen datang',
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
              Text(
                'Godaan + kambuh, biar kamu siap di waktu rawan',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
              const SizedBox(height: 10),
              if (!hasEvents)
                Text(
                  'Belum ada catatan godaan. Semoga tetap tenang terus 🌿',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                )
              else ...[
                MiniBars(
                  values: weekday,
                  labels: weekdaysShort,
                  color: GhinaColors.purple,
                ),
                GhinaSpace.gapMd,
                MiniBars(
                  values: hours,
                  labels: _hourLabels,
                  color: GhinaColors.blue,
                  height: 60,
                ),
                if (rel.unknownHour + urg.unknownHour > 0)
                  Text(
                    '${rel.unknownHour + urg.unknownHour} tanpa jam',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ],
          ),
        ),
        if (insights.topTriggers.isNotEmpty) ...[
          GhinaSpace.gapMd,
          ChunkyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pemicu teratas',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in insights.topTriggers.take(6))
                      ChunkyPill(
                        label: '${t.tag} · ${t.count}×',
                        color: GhinaColors.purple,
                        soft: true,
                        uppercase: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Journal extends StatelessWidget {
  const _Journal({
    required this.entries,
    required this.today,
    required this.onEdit,
  });

  final List<HabitJournalEntry> entries;
  final String today;
  final ValueChanged<HabitJournalEntry> onEdit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (entries.isEmpty) {
      return ChunkyCard(
        child: Text(
          'Belum ada jurnal di rentang ini. Tulis perasaan atau pelajaranmu — cuma kamu yang baca.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      );
    }
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final e in entries)
            ChunkyTile(
              key: ValueKey('journal-${e.logId}'),
              framed: false,
              title: e.note,
              subtitle: '${habitDayLabel(e.date, today)} · ${e.type.label}',
              leading: CategoryAvatar(
                icon: Icons.edit_note_rounded,
                color: GhinaColors.purple.base,
                size: 36,
                soft: true,
              ),
              onTap: () => onEdit(e),
            ),
        ],
      ),
    );
  }
}

class _LogList extends ConsumerWidget {
  const _LogList({
    required this.logs,
    required this.habit,
    required this.today,
  });

  final List<HabitLog> logs;
  final Habit habit;
  final String today;

  String _value(HabitLog l) => switch (l.type) {
    HabitLogType.done =>
      habit.isBuild && !habit.target.isCheck
          ? progressLabel(habit.target, l.value)
          : (habit.isQuit ? 'Bersih ✅' : 'Selesai ✅'),
    HabitLogType.skip => 'Libur 🌴',
    HabitLogType.relapse => '${l.amount.round()}× kambuh',
    HabitLogType.urge => '${l.amount.round()}× godaan ditahan',
  };

  Future<void> _delete(BuildContext context, WidgetRef ref, HabitLog l) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus catatan ini?',
      message:
          '${habitDayLabel(l.date, today)} · ${_value(l)}. Jurnal di catatan ini ikut terhapus.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final r = await ref.read(deleteHabitLogProvider)(l.id);
    if (!context.mounted) return;
    if (r case Err(:final failure)) showFailureToast(context, failure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    if (logs.isEmpty) {
      return ChunkyCard(
        child: Text(
          'Belum ada catatan di rentang ini.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      );
    }
    final shown = logs.take(40).toList();
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final l in shown)
            ChunkyTile(
              key: ValueKey('log-${l.id}'),
              framed: false,
              dense: true,
              title: _value(l),
              subtitle: [
                habitDayLabel(l.date, today),
                if (l.at case final at?)
                  '${at.hour.toString().padLeft(2, '0')}.${at.minute.toString().padLeft(2, '0')}',
                if (l.triggers.isNotEmpty) l.triggers.join(', '),
              ].join(' · '),
              leading: CategoryAvatar(
                icon: switch (l.type) {
                  HabitLogType.done => Icons.check_circle_rounded,
                  HabitLogType.skip => Icons.beach_access_rounded,
                  HabitLogType.relapse => Icons.refresh_rounded,
                  HabitLogType.urge => Icons.shield_rounded,
                },
                color: switch (l.type) {
                  HabitLogType.done => GhinaColors.green.base,
                  HabitLogType.skip => GhinaColors.blue.base,
                  HabitLogType.relapse => GhinaColors.gray.base,
                  HabitLogType.urge => GhinaColors.purple.base,
                },
                size: 34,
                soft: true,
              ),
              trailing: IconButton(
                key: ValueKey('log-delete-${l.id}'),
                tooltip: 'Hapus',
                icon: Icon(Icons.delete_outline_rounded, color: g.textMuted),
                onPressed: () => _delete(context, ref, l),
              ),
            ),
          if (logs.length > shown.length)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '+${logs.length - shown.length} catatan lain di rentang ini',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _JournalSheet extends StatefulWidget {
  const _JournalSheet({required this.initial});

  final String initial;

  @override
  State<_JournalSheet> createState() => _JournalSheetState();
}

class _JournalSheetState extends State<_JournalSheet> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChunkyTextField(
        key: const ValueKey('journal-text'),
        controller: _ctl,
        hint: 'Apa yang kamu rasakan atau pelajari hari ini?',
        maxLines: 6,
        minLines: 3,
        maxLength: habitNoteMax,
        autofocus: true,
      ),
      GhinaSpace.gapMd,
      ChunkyButton(
        key: const ValueKey('journal-save'),
        label: 'Simpan',
        onPressed: () => Navigator.of(context).pop(_ctl.text.trim()),
      ),
    ],
  );
}
