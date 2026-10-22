import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/game/task_game_providers.dart';
import '../../../state/killa_access_provider.dart';
import '../../content/widgets/today_posts_card.dart';
import '../widgets/balance_card.dart';
import '../widgets/home_habits.dart';
import '../widgets/home_kantor.dart';
import '../widgets/home_sections.dart';
import '../widgets/home_tasks.dart';
import 'home_layout.dart';
import 'home_tiles.dart';

/// Turns a [HomeEntry] into the widget Beranda shows. Returns null when the
/// card has nothing to show right now (it is then skipped, gap included).
class HomeCardBuilder {
  HomeCardBuilder({
    required this.context,
    required this.ref,
    required this.now,
    required this.currency,
  });

  final BuildContext context;
  final WidgetRef ref;
  final DateTime now;
  final String currency;

  bool _dashErrorShown = false;

  /// Cards that draw their own top gap and may vanish (so no stray space).
  static bool selfSpaced(HomeEntry e) => switch (e.card) {
    HomeCard.todayPosts => true,
    HomeCard.habits || HomeCard.kantor => e.size == HomeCardSize.medium,
    _ => false,
  };

  Widget? build(HomeEntry e, {required bool first}) {
    final size = e.size;
    final top = EdgeInsets.only(top: first ? 0 : 16);
    return switch (e.card) {
      HomeCard.mascot => _mascot(),
      HomeCard.balance => _dash(
        const Skeleton(height: 104, radius: 20),
        (d) => BalanceCard(dash: d, currency: currency),
      ),
      HomeCard.monthFlow => _dash(
        const Skeleton(height: 120, radius: 20),
        (d) => MonthFlowCard(dash: d, currency: currency),
      ),
      HomeCard.wallets => _dash(
        Skeleton(height: size == HomeCardSize.small ? 104 : 72, radius: 20),
        (d) => HomeWalletsTile(dash: d, currency: currency, size: size),
      ),
      HomeCard.tasks => const HomeTasksSection(),
      HomeCard.habits =>
        size == HomeCardSize.small
            ? HomeHabitsTile(size: size)
            : HomeHabitsCard(padding: top),
      HomeCard.agenda => HomeAgendaTile(size: size),
      HomeCard.calendar => HomeCalendarTile(size: size),
      HomeCard.todayPosts => TodayPostsCard(padding: top),
      HomeCard.kantor =>
        size == HomeCardSize.small && ref.watch(kantorApiProvider) != null
            ? HomeKantorTile(size: size)
            : HomeKantorCard(padding: top),
      HomeCard.killa =>
        ref.watch(killaAccessProvider) == KillaAccess.forbidden
            ? null
            : HomeTile(
                size: size,
                icon: HomeCard.killa.icon,
                color: GhinaColors.purple,
                title: 'Killa',
                value: 'Ngobrol',
                subtitle: 'Tanya atau suruh Killa',
                route: '/killa',
              ),
      HomeCard.portfolio => HomePortfolioTile(size: size, currency: currency),
      HomeCard.screener => HomeTile(
        size: size,
        icon: HomeCard.screener.icon,
        color: GhinaColors.teal,
        title: 'Screener',
        value: 'Saham IDX',
        subtitle: 'Cari saham yang lolos',
        route: '/investments/screener',
      ),
      HomeCard.learning => _learning(),
      HomeCard.prayers => HomeTile(
        size: size,
        icon: HomeCard.prayers.icon,
        color: GhinaColors.green,
        title: 'Sholat',
        value: 'Hari ini',
        subtitle: 'Catat sholat lima waktu',
        route: '/prayers',
      ),
      HomeCard.dreams => HomeDreamsTile(size: size),
      HomeCard.people => HomePeopleTile(size: size),
      HomeCard.notes => HomeTile(
        size: size,
        icon: HomeCard.notes.icon,
        color: GhinaColors.yellow,
        title: 'Catatan',
        value: 'Buka catatan',
        subtitle: 'Tulis atau cari catatan',
        route: '/notes',
      ),
      HomeCard.menu => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Menu'),
          QuickActionsGrid(),
        ],
      ),
      HomeCard.spending => _spending(),
      HomeCard.budgets => _budgets(),
      HomeCard.bills => _bills(),
      HomeCard.recent => _recent(),
    };
  }

  // ------------------------------------------------------------------ pieces

  /// Builds [card] from the dashboard, or its skeleton while loading. A load
  /// failure shows one retry message for all dashboard cards.
  Widget? _dash(Widget skeleton, Widget Function(DashboardSummary) card) {
    final dash = ref.watch(watchDashboardProvider);
    final d = dash.value;
    if (d != null) return card(d);
    if (!dash.hasError) return skeleton;
    if (_dashErrorShown) return null;
    _dashErrorShown = true;
    return EmptyState(
      compact: true,
      mood: MascotMood.sad,
      title: 'Ups, ada yang salah',
      message: 'Data keuanganmu gagal dimuat. Coba lagi, yuk.',
      actionLabel: 'Coba lagi',
      onAction: () => ref.invalidate(watchDashboardProvider),
    );
  }

  Widget _mascot() {
    final game = ref.watch(gameSummaryProvider);
    if (game.hasError && game.value == null) {
      return MascotSpeech(
        mood: MascotMood.sad,
        mascotSize: 84,
        message:
            'Ups, progresmu belum kebaca. Tarik ke bawah buat coba lagi, ya.',
      );
    }
    final s = game.value;
    if (s == null) {
      return const Column(
        children: [
          Row(
            children: [
              Skeleton.circle(size: 84),
              SizedBox(width: 12),
              Expanded(child: Skeleton(height: 64, radius: 16)),
            ],
          ),
          SizedBox(height: 16),
          Skeleton(height: 108, radius: 20),
        ],
      );
    }
    final line = ref.watch(homeMascotProvider);
    return Column(
      children: [
        HomeMascot(
          mood: line?.mood ?? s.mood,
          message: line?.message ?? s.message,
        ),
        GhinaSpace.gapLg,
        DailyGoalCard(summary: s),
      ],
    );
  }

  Widget? _learning() {
    final path = ref.watch(learnPathProvider).value;
    return path == null ? null : ContinueLearningCard(path: path);
  }

  Widget? _spending() {
    final loaded = ref.watch(watchDashboardProvider).value;
    if (loaded != null && loaded.spendingByCategory.isEmpty) return null;
    return _dash(const Skeleton(height: 140, radius: 20), (d) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Pengeluaran bulan ini',
            actionLabel: 'Analitik',
            onAction: () => context.push('/analytics'),
          ),
          SpendingCard(items: d.spendingByCategory, currency: currency),
        ],
      );
    });
  }

  Widget? _budgets() {
    final budgets = ref
        .watch(watchBudgetMonthProvider(YearMonth.of(now)))
        .value;
    if (budgets == null) return null;
    final hearts = ref.watch(gameSummaryProvider).value?.hearts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Anggaran',
          actionLabel: budgets.items.isEmpty ? null : 'Lihat semua',
          onAction: budgets.items.isEmpty
              ? null
              : () => context.push('/budgets'),
        ),
        BudgetSnapshotCard(month: budgets, hearts: hearts, currency: currency),
      ],
    );
  }

  Widget? _bills() {
    final subs = ref.watch(watchSubscriptionsProvider).value;
    final dueSoon = [
      for (final s in subs?.active ?? const <Subscription>[])
        if (s.daysUntilNext(now) <= 7) s,
    ]..sort((a, b) => a.daysUntilNext(now).compareTo(b.daysUntilNext(now)));
    if (dueSoon.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Tagihan sebentar lagi',
          actionLabel: 'Langganan',
          onAction: () => context.push('/subscriptions'),
        ),
        UpcomingSubscriptionsCard(
          items: dueSoon.take(3).toList(),
          now: now,
          currency: currency,
        ),
      ],
    );
  }

  Widget? _recent() => _dash(const SkeletonList(count: 3), (d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Transaksi terakhir',
          actionLabel: d.recent.isEmpty ? null : 'Lihat semua',
          onAction: d.recent.isEmpty ? null : () => context.go('/transactions'),
        ),
        if (d.recent.isEmpty)
          ChunkyCard(
            child: EmptyState(
              compact: true,
              mascotSize: 96,
              title: 'Belum ada transaksi',
              message: 'Catat yang pertama, yuk! Cuma 10 detik kok.',
              actionLabel: 'Catat sekarang',
              onAction: () => context.push('/transactions/new'),
            ),
          )
        else
          RecentTransactionsCard(
            items: d.recent.take(5).toList(),
            currency: currency,
            now: now,
          ),
      ],
    );
  });
}
