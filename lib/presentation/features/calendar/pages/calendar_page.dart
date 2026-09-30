import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../calendar_format.dart';

enum _View { month, agenda }

/// "Kalender": month grid (Monday first) with the selected day's events, or
/// an agenda of what's coming.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late YearMonth _month;
  late DateTime _selected;
  _View _view = _View.month;

  @override
  void initState() {
    super.initState();
    final today = startOfDay(ref.read(clockProvider).now());
    _month = YearMonth.of(today);
    _selected = today;
  }

  void _goToday() {
    final today = startOfDay(ref.read(clockProvider).now());
    setState(() {
      _month = YearMonth.of(today);
      _selected = today;
    });
  }

  void _select(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = day;
      if (!_month.contains(day)) _month = YearMonth.of(day);
    });
  }

  void _add() => context.push('/calendar/new?date=${dateKey(_selected)}');

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(watchCalendarEventsProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Kalender'),
        actions: [
          IconButton(
            tooltip: 'Hari ini',
            icon: const Icon(Icons.today_rounded),
            onPressed: _goToday,
          ),
          IconButton(
            tooltip: 'Acara baru',
            icon: const Icon(Icons.add_rounded),
            onPressed: _add,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: g.background,
          border: Border(top: BorderSide(color: g.border, width: 2)),
        ),
        padding: EdgeInsets.fromLTRB(
          GhinaSpace.page,
          12,
          GhinaSpace.page,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ChunkyButton(
          label: 'Acara baru',
          icon: Icons.event_available_rounded,
          onPressed: _add,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: switch (async) {
          AsyncData(:final value) => _body(value),
          AsyncError() => ScrollableFill(
            child: ErrorRetry(
              onRetry: () => ref.invalidate(watchCalendarEventsProvider),
            ),
          ),
          _ => const LoadingListView(tiles: 4),
        },
      ),
    );
  }

  Widget _body(List<CalendarEvent> events) {
    final byDay = eventsByDay(events);
    final today = startOfDay(ref.watch(clockProvider).now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        ChunkySegmented<_View>(
          segments: const [
            ChunkySegment(
              value: _View.month,
              label: 'Bulan',
              icon: Icons.calendar_view_month_rounded,
            ),
            ChunkySegment(
              value: _View.agenda,
              label: 'Agenda',
              icon: Icons.view_agenda_rounded,
            ),
          ],
          value: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        const SizedBox(height: 16),
        if (_view == _View.month) ...[
          MonthSwitcher(
            value: _month,
            current: YearMonth.of(today),
            onChanged: (m) => setState(() {
              _month = m;
              _selected = m.contains(today) ? today : m.start;
            }),
          ),
          const SizedBox(height: 12),
          MonthGrid(
            month: _month,
            selected: _selected,
            today: today,
            byDay: byDay,
            onSelect: _select,
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: dayTitle(_selected, today),
            subtitle: switch (byDay[dateKey(_selected)]?.length ?? 0) {
              0 => 'Kosong',
              final n => '$n acara',
            },
          ),
          ..._dayEvents(byDay[dateKey(_selected)] ?? const []),
        ] else
          ..._agenda(events, byDay, today),
      ],
    );
  }

  List<Widget> _dayEvents(List<CalendarEvent> events) {
    if (events.isEmpty) {
      return [
        EmptyState(
          compact: true,
          title: 'Belum ada acara',
          message: 'Hari ini masih lowong. Mau jadwalin sesuatu?',
          mood: MascotMood.sleeping,
          actionLabel: 'Tambah acara',
          onAction: _add,
        ),
      ];
    }
    return [
      for (final (i, e) in events.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PopIn(
            delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
            child: EventTile(
              event: e,
              onTap: () => context.push('/calendar/${e.id}'),
            ),
          ),
        ),
    ];
  }

  /// Days from today on (60 days) that have events.
  List<Widget> _agenda(
    List<CalendarEvent> events,
    Map<String, List<CalendarEvent>> byDay,
    DateTime today,
  ) {
    final out = <Widget>[];
    for (var i = 0; i < 60; i++) {
      final day = addDays(today, i);
      final list = byDay[dateKey(day)];
      if (list == null || list.isEmpty) continue;
      out
        ..add(
          Padding(
            padding: EdgeInsets.only(top: out.isEmpty ? 0 : 16, bottom: 8),
            child: _AgendaDayHeader(day: day, today: today),
          ),
        )
        ..addAll([
          for (final e in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EventTile(
                event: e,
                onTap: () => context.push('/calendar/${e.id}'),
              ),
            ),
        ]);
    }
    if (out.isEmpty) {
      return [
        EmptyState(
          title: events.isEmpty ? 'Kalendermu masih kosong' : 'Belum ada acara',
          message: events.isEmpty
              ? 'Catat janji, ulang tahun, atau acara penting biar nggak lupa 📅'
              : 'Nggak ada acara dalam 60 hari ke depan.',
          mood: MascotMood.waving,
          actionLabel: 'Tambah acara',
          onAction: _add,
        ),
      ];
    }
    return out;
  }
}

class _AgendaDayHeader extends StatelessWidget {
  const _AgendaDayHeader({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final isToday = isSameDay(day, today);
    return Row(
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isToday ? GhinaColors.blue.base : g.surfaceAlt,
            borderRadius: GhinaRadii.rMd,
          ),
          child: Column(
            children: [
              Text(
                weekdayInitials[day.weekday - 1].toUpperCase(),
                style: GhinaType.caption
                    .w(800)
                    .copyWith(color: isToday ? Colors.white : g.textSecondary),
              ),
              Text(
                '${day.day}',
                style: GhinaType.h3.copyWith(
                  color: isToday ? Colors.white : g.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            dayTitle(day, today),
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// 6×7 month grid, Monday first: day number, up to three event bars, today
/// ringed, the selected day filled.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.byDay,
    required this.onSelect,
  });

  final YearMonth month;
  final DateTime selected;
  final DateTime today;
  final Map<String, List<CalendarEvent>> byDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final days = monthGridDays(month);
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              for (final (i, w) in weekdayInitials.indexed)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: GhinaType.caption
                          .w(800)
                          .copyWith(
                            color: i >= 5 ? GhinaColors.red.base : g.textMuted,
                          ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var w = 0; w < 6; w++)
            Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: _DayCell(
                      day: days[w * 7 + d],
                      inMonth: month.contains(days[w * 7 + d]),
                      isToday: isSameDay(days[w * 7 + d], today),
                      isSelected: isSameDay(days[w * 7 + d], selected),
                      events:
                          byDay[dateKey(days[w * 7 + d])] ??
                          const <CalendarEvent>[],
                      onTap: () => onSelect(days[w * 7 + d]),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<CalendarEvent> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final numColor = isSelected
        ? Colors.white
        : !inMonth
        ? g.textMuted.withValues(alpha: 0.5)
        : isToday
        ? GhinaColors.blue.base
        : g.textPrimary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${Fmt.dateFull(day)}, ${events.length} acara',
      child: InkWell(
        key: ValueKey('cal-day-${dateKey(day)}'),
        onTap: onTap,
        borderRadius: GhinaRadii.rMd,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: GhinaMotion.fast,
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? GhinaColors.blue.base : null,
                  border: isToday && !isSelected
                      ? Border.all(color: GhinaColors.blue.base, width: 2)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: GhinaType.bodyS
                      .w(isToday || isSelected ? 900 : 700)
                      .copyWith(color: numColor),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final e in events.take(3))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CategoryColors.parse(
                            e.displayColor,
                          ).withValues(alpha: inMonth ? 1 : 0.4),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One event: color bar, title, time, location.
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.onTap});

  final CalendarEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final e = event;
    final color = CategoryColors.parse(e.displayColor);
    return ChunkySurface(
      color: g.surface,
      edgeColor: g.borderEdge,
      borderColor: g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      semanticLabel: e.title,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: GhinaRadii.rPill,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        e.allDay
                            ? Icons.wb_sunny_rounded
                            : Icons.schedule_rounded,
                        size: 15,
                        color: g.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          eventTimeLabel(e),
                          style: GhinaType.bodyS
                              .w(700)
                              .copyWith(color: g.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (e.location != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.place_rounded, size: 15, color: g.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            e.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.bodyS.copyWith(color: g.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: g.textMuted),
          ],
        ),
      ),
    );
  }
}
