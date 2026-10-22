import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/agenda_rules.dart';
import '../../../design_system/design_system.dart';
import '../../kantor/kantor_format.dart';
import '../../kantor/kantor_data.dart';
import 'home_layout.dart';

/// Compact, data-light card used by the cards that have no bigger Beranda
/// block of their own. [HomeCardSize.small] is a half-width tile,
/// [HomeCardSize.medium] a full-width row and [HomeCardSize.wide] adds
/// [details] underneath.
class HomeTile extends StatelessWidget {
  const HomeTile({
    super.key,
    required this.size,
    required this.icon,
    required this.color,
    required this.title,
    required this.route,
    this.value,
    this.subtitle,
    this.details = const [],
  });

  final HomeCardSize size;
  final IconData icon;
  final ChunkySwatch color;
  final String title;
  final String route;
  final String? value;
  final String? subtitle;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final badge = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.base.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color.base),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
        ),
        if (value != null)
          Text(
            value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: size == HomeCardSize.small ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
      ],
    );
    final Widget body;
    if (size == HomeCardSize.small) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          badge,
          const SizedBox(height: GhinaSpace.sm),
          texts,
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              badge,
              const SizedBox(width: GhinaSpace.md),
              Expanded(child: texts),
              Icon(Icons.chevron_right_rounded, color: g.textMuted),
            ],
          ),
          if (size == HomeCardSize.wide && details.isNotEmpty) ...[
            const SizedBox(height: GhinaSpace.sm),
            Divider(height: 1, color: g.border),
            const SizedBox(height: GhinaSpace.sm),
            ...details,
          ],
        ],
      );
    }
    return ChunkyCard(
      key: ValueKey('home-tile-$route-${size.name}'),
      padding: const EdgeInsets.all(GhinaSpace.md),
      onTap: () => context.push(route),
      semanticLabel: title,
      child: body,
    );
  }
}

/// A detail row: [left] text and an optional [right] text.
Widget homeDetailRow(BuildContext context, String left, [String? right]) {
  final g = context.ghina;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.bodyS.copyWith(color: g.textPrimary),
          ),
        ),
        if (right != null)
          Text(right, style: GhinaType.caption.copyWith(color: g.textMuted)),
      ],
    ),
  );
}

Widget _tileSkeleton(HomeCardSize size) =>
    Skeleton(height: size == HomeCardSize.small ? 104 : 72, radius: 20);

/// "Dompet": total balance and the wallets behind it.
class HomeWalletsTile extends StatelessWidget {
  const HomeWalletsTile({
    super.key,
    required this.dash,
    required this.currency,
    required this.size,
  });

  final DashboardSummary dash;
  final String currency;
  final HomeCardSize size;

  @override
  Widget build(BuildContext context) {
    final wallets = dash.wallets.where((w) => !w.archived).toList();
    return HomeTile(
      size: size,
      icon: HomeCard.wallets.icon,
      color: GhinaColors.blue,
      title: 'Dompet',
      value: context.money(dash.totalBalance, currency: currency),
      subtitle: '${wallets.length} dompet',
      route: '/wallets',
      details: [
        for (final w in wallets.take(4))
          homeDetailRow(
            context,
            w.name,
            context.money(w.balance, currency: w.currency),
          ),
      ],
    );
  }
}

class HomeAgendaTile extends ConsumerWidget {
  const HomeAgendaTile({super.key, required this.size});

  final HomeCardSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchReminderGroupsProvider);
    final ReminderGroups? groups = async.value;
    if (groups == null) {
      return async.hasError ? const SizedBox.shrink() : _tileSkeleton(size);
    }
    final open = [...groups.overdue, ...groups.upcoming];
    return HomeTile(
      size: size,
      icon: HomeCard.agenda.icon,
      color: GhinaColors.orange,
      title: 'Pengingat',
      value: open.isEmpty ? 'Kosong' : '${open.length} aktif',
      subtitle: groups.overdue.isNotEmpty
          ? '${groups.overdue.length} terlambat'
          : open.isEmpty
          ? 'Tidak ada pengingat'
          : open.first.title,
      route: '/killa/reminders',
      details: [
        for (final r in open.take(3))
          homeDetailRow(context, r.title, Fmt.dateShortWeekday(r.dueAt)),
      ],
    );
  }
}

class HomeCalendarTile extends ConsumerWidget {
  const HomeCalendarTile({super.key, required this.size});

  final HomeCardSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchCalendarEventsProvider);
    final events = async.value;
    if (events == null) {
      return async.hasError ? const SizedBox.shrink() : _tileSkeleton(size);
    }
    final now = ref.watch(clockProvider).now();
    final today = DateTime(now.year, now.month, now.day);
    final next = [
      for (final e in events)
        if (!e.startAt.isBefore(today)) e,
    ];
    final first = next.firstOrNull;
    return HomeTile(
      size: size,
      icon: HomeCard.calendar.icon,
      color: GhinaColors.purple,
      title: 'Kalender',
      value: first?.title ?? 'Kosong',
      subtitle: first == null
          ? 'Belum ada acara'
          : Fmt.dateShortWeekday(first.startAt),
      route: '/calendar',
      details: [
        for (final e in next.take(3))
          homeDetailRow(context, e.title, Fmt.dateShortWeekday(e.startAt)),
      ],
    );
  }
}

class HomePortfolioTile extends ConsumerWidget {
  const HomePortfolioTile({
    super.key,
    required this.size,
    required this.currency,
  });

  final HomeCardSize size;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchPortfolioProvider);
    final p = async.value;
    if (p == null) {
      return async.hasError ? const SizedBox.shrink() : _tileSkeleton(size);
    }
    final pct = p.dayChangePct;
    return HomeTile(
      size: size,
      icon: HomeCard.portfolio.icon,
      color: GhinaColors.green,
      title: 'Portofolio',
      value: p.isEmpty
          ? 'Belum ada aset'
          : context.money(p.marketValue, currency: currency),
      subtitle: p.isEmpty
          ? 'Tambah aset pertama'
          : pct == null
          ? '${p.open.length} posisi'
          : 'Hari ini ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
      route: '/investments',
      details: [
        homeDetailRow(context, 'Posisi terbuka', '${p.open.length}'),
        for (final s in p.byKind.take(3))
          homeDetailRow(context, s.label, '${s.pct.round()}%'),
      ],
    );
  }
}

class HomeDreamsTile extends ConsumerWidget {
  const HomeDreamsTile({super.key, required this.size});

  final HomeCardSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchDreamsProvider);
    final dreams = async.value;
    if (dreams == null) {
      return async.hasError ? const SizedBox.shrink() : _tileSkeleton(size);
    }
    final active = dreams.where((d) => d.status == DreamStatus.active).toList();
    return HomeTile(
      size: size,
      icon: HomeCard.dreams.icon,
      color: GhinaColors.pink,
      title: 'Mimpi',
      value: dreams.isEmpty ? 'Kosong' : '${active.length} berjalan',
      subtitle: dreams.isEmpty
          ? 'Catat mimpi pertama'
          : '${dreams.length} mimpi',
      route: '/dreams',
      details: [
        for (final d in active.take(3))
          homeDetailRow(context, '${d.emoji ?? ''} ${d.title}'.trim()),
      ],
    );
  }
}

class HomePeopleTile extends ConsumerWidget {
  const HomePeopleTile({super.key, required this.size});

  final HomeCardSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchUpcomingPeopleProvider);
    final events = async.value;
    if (events == null) {
      return async.hasError ? const SizedBox.shrink() : _tileSkeleton(size);
    }
    String when(UpcomingEvent e) =>
        e.daysUntil == 0 ? 'hari ini' : '${e.daysUntil} hari lagi';
    final first = events.firstOrNull;
    return HomeTile(
      size: size,
      icon: HomeCard.people.icon,
      color: GhinaColors.yellow,
      title: 'Tanggal penting',
      value: first?.name ?? 'Kosong',
      subtitle: first == null
          ? 'Tidak ada dalam 60 hari'
          : '${first.label} · ${when(first)}',
      route: '/people',
      details: [
        for (final e in events.take(3))
          homeDetailRow(context, '${e.name} · ${e.label}', when(e)),
      ],
    );
  }
}

class HomeHabitsTile extends ConsumerWidget {
  const HomeHabitsTile({super.key, required this.size});

  final HomeCardSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchHabitBoardProvider);
    final board = async.value;
    if (board == null) {
      return async.hasError ? const SizedBox.shrink() : _tileSkeleton(size);
    }
    final due = board.dueCount;
    return HomeTile(
      size: size,
      icon: HomeCard.habits.icon,
      color: GhinaColors.orange,
      title: 'Kebiasaan',
      value: board.isEmpty ? 'Kosong' : '${board.metCount}/$due',
      subtitle: board.isEmpty ? 'Belum ada kebiasaan' : 'tercapai hari ini',
      route: '/habits',
    );
  }
}

/// Kantor as a tile: waiting permissions, working agents and cost.
class HomeKantorTile extends ConsumerWidget {
  const HomeKantorTile({super.key, required this.size});

  final HomeCardSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(kantorStateProvider);
    final state = st.value;
    if (state == null) {
      return st.hasError
          ? HomeTile(
              size: size,
              icon: HomeCard.kantor.icon,
              color: GhinaColors.gray,
              title: 'Kantor',
              value: 'Tidak terhubung',
              subtitle: 'Cek Tailscale',
              route: '/kantor',
            )
          : _tileSkeleton(size);
    }
    final offices = (state['offices'] as List? ?? const []).whereType<Map>();
    final inbox = state['inbox'] as List? ?? const [];
    var working = 0;
    var cost = 0.0;
    for (final o in offices) {
      cost += (o['monthCost'] as num?)?.toDouble() ?? 0;
      for (final s in (o['sessions'] as List? ?? const [])) {
        if (s is Map && s['status'] == 'working') working++;
      }
    }
    return HomeTile(
      size: size,
      icon: HomeCard.kantor.icon,
      color: inbox.isEmpty ? GhinaColors.blue : GhinaColors.orange,
      title: 'Kantor',
      value: inbox.isEmpty ? '$working bekerja' : '${inbox.length} izin',
      subtitle: inbox.isEmpty
          ? '${kantorUsd(cost, 0)} bulan ini'
          : '$working bekerja · ${kantorUsd(cost, 0)}',
      route: '/kantor',
    );
  }
}
