import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart' show currencyProvider;
import '../widgets/food_link_widgets.dart';
import '../widgets/food_photo.dart';

/// Food diary: today's calories and meals, then every day's logs with photos.
class FoodPage extends ConsumerStatefulWidget {
  const FoodPage({super.key});

  @override
  ConsumerState<FoodPage> createState() => _FoodPageState();
}

String _kcalText(FoodTotals t) => '${formatCalorieSpan(t, Fmt.number)} kkal';

class _FoodPageState extends ConsumerState<FoodPage> {
  String? _tag;

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncNowProvider)();
    } catch (_) {
      if (context.mounted) {
        showErrorToast(context, 'Belum bisa sinkron. Cek koneksi kamu, ya.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(watchFoodLogsProvider);
    final today = ref.watch(clockProvider).now();
    final hasData = async.value?.isNotEmpty ?? false;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Catatan makan'),
        actions: [
          IconButton(
            tooltip: 'Catat makanan',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/food/new'),
          ),
        ],
      ),
      bottomNavigationBar: hasData
          ? Container(
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
                label: 'Catat makanan',
                icon: Icons.photo_camera_rounded,
                color: GhinaColors.orange,
                onPressed: () => context.push('/food/new'),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ListView(
            children: [
              const SizedBox(height: 24),
              EmptyState(
                title: 'Belum ada catatan makan',
                message:
                    'Foto makananmu, catat kalorinya, dan bangun food diary kamu. +5 XP tiap catatan!',
                mood: MascotMood.waving,
                actionLabel: 'Catat makanan',
                onAction: () => context.push('/food/new'),
              ),
            ],
          ),
          AsyncData(:final value) => _list(context, value, today),
          AsyncError() => ListView(
            children: [
              ErrorRetry(onRetry: () => ref.invalidate(watchFoodLogsProvider)),
            ],
          ),
          _ => const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 5),
          ),
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<FoodLog> all, DateTime now) {
    final counts = foodTagCounts(all);
    // A tag that no longer exists (deleted logs) can't keep filtering.
    final tag = counts.any((c) => c.tag.toLowerCase() == _tag?.toLowerCase())
        ? _tag
        : null;
    final logs = filterFoodByTag(all, tag);
    // Group by local day (logs come newest first).
    final groups = <({DateTime day, List<FoodLog> items})>[];
    for (final l in logs) {
      final d = startOfDay(l.date);
      if (groups.isNotEmpty && isSameDay(groups.last.day, d)) {
        groups.last.items.add(l);
      } else {
        groups.add((day: d, items: [l]));
      }
    }
    final todayItems = all.where((l) => isSameDay(l.date, now)).toList();
    final weekly = weeklyFoodSummary(all, now);
    final suggestions =
        ref.watch(foodLinkSuggestionsProvider).value ??
        const <FoodLinkSuggestion>[];
    final stats = ref.watch(foodMonthStatsProvider).value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        _TodayCard(items: todayItems),
        for (final s in suggestions.take(3)) ...[
          const SizedBox(height: 12),
          FoodLinkSuggestionCard(suggestion: s),
        ],
        if (weekly.days.isNotEmpty) ...[
          const SizedBox(height: 12),
          _WeeklyCard(summary: weekly),
        ],
        if (stats != null && !stats.isEmpty) ...[
          const SizedBox(height: 12),
          FoodSpendCard(stats: stats),
        ],
        if (counts.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TagFilter(
            counts: counts,
            selected: tag,
            onSelect: (t) => setState(() => _tag = t),
          ),
        ],
        for (final grp in groups) ...[
          const SizedBox(height: 24),
          SectionHeader(
            title: Fmt.relativeDay(grp.day, now: now),
            subtitle:
                isSameDay(grp.day, now) || isSameDay(grp.day, addDays(now, -1))
                ? Fmt.dateFull(grp.day)
                : null,
            trailing: foodTotals(grp.items).hasCalories
                ? ChunkyPill(
                    key: ValueKey('day-total-${dateKey(grp.day)}'),
                    label: _dayLabel(foodTotals(grp.items)),
                    icon: Icons.local_fire_department_rounded,
                    color: GhinaColors.orange,
                    soft: true,
                    uppercase: false,
                  )
                : null,
          ),
          for (var i = 0; i < grp.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FoodCard(log: grp.items[i]),
            ),
        ],
      ],
    );
  }

  static String _dayLabel(FoodTotals t) =>
      t.isRange ? '${_kcalText(t)} · ≈ ${Fmt.number(t.mid)}' : _kcalText(t);
}

/// Horizontally scrollable tag filter ("Semua" + one chip per tag).
class _TagFilter extends StatelessWidget {
  const _TagFilter({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final List<FoodTagCount> counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChunkyChip(
            key: const ValueKey('tag-filter-all'),
            label: 'Semua',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final c in counts) ...[
            const SizedBox(width: 8),
            ChunkyChip(
              key: ValueKey('tag-filter-${c.tag}'),
              label: '#${c.tag} (${c.count})',
              selected: selected?.toLowerCase() == c.tag.toLowerCase(),
              onTap: () => onSelect(c.tag),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact last-7-days summary (mirrors `GET /food/summary`).
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.summary});

  final FoodSummary summary;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final avg = summary.avgPerDay!;
    final span = avg.max > avg.min
        ? '${Fmt.number(avg.min)}–${Fmt.number(avg.max)}'
        : Fmt.number(avg.min);
    String? topMeal;
    for (final e in summary.byMeal.entries) {
      if (e.key == '(none)') continue;
      topMeal =
          MealType.values
              .where((m) => m.wire == e.key)
              .map((m) => m.label)
              .firstOrNull ??
          e.key;
      break;
    }
    final tags = summary.topTags.take(3).map((t) => '#${t.tag}').join(' ');
    return ChunkyCard(
      key: const ValueKey('food-weekly'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '7 HARI TERAKHIR',
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 4),
          Text('Rata-rata $span kkal/hari', style: GhinaType.h3),
          if (avg.max > avg.min)
            Text(
              'tengah ${Fmt.number(avg.mid)} kkal',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          const SizedBox(height: 4),
          Text(
            [
              '${summary.daysLogged} hari tercatat',
              ?(topMeal == null ? null : 'terbanyak: $topMeal'),
              if (tags.isNotEmpty) tags,
            ].join(' · '),
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.items});

  final List<FoodLog> items;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final totals = foodTotals(items);
    final logged = {for (final l in items) ?l.meal};
    return ChunkyCard(
      tinted: GhinaColors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CategoryAvatar(
                icon: Icons.local_fire_department_rounded,
                color: Color(0xFFFF9600),
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HARI INI',
                      style: GhinaType.overline.copyWith(
                        color: g.textSecondary,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        totals.hasCalories
                            ? _kcalText(totals)
                            : '${items.length} tercatat',
                        key: const ValueKey('today-total'),
                        style: GhinaType.moneyL,
                      ),
                    ),
                    if (totals.isRange)
                      Text(
                        'tengah ${Fmt.number(totals.mid)} kkal',
                        key: const ValueKey('today-mid'),
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${items.length} makanan',
                style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in MealType.values)
                _MealCheck(meal: m, done: logged.contains(m)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealCheck extends StatelessWidget {
  const _MealCheck({required this.meal, required this.done});

  final MealType meal;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = mealSwatch(meal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: done ? sw.base : g.surface,
        borderRadius: GhinaRadii.rPill,
        border: Border.all(color: done ? sw.edge : g.border, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(meal.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            meal.label,
            style: GhinaType.caption
                .w(800)
                .copyWith(color: done ? sw.on : g.textSecondary),
          ),
          if (done) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_rounded, size: 14, color: sw.on),
          ],
        ],
      ),
    );
  }
}

String _rowKcal(FoodLog l) {
  final hi = l.caloriesMax;
  final lo = l.calories!;
  return hi != null && hi > lo
      ? '${Fmt.number(lo)}–${Fmt.number(hi)}'
      : Fmt.number(lo);
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.log});

  final FoodLog log;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final pending = log.localPhotoPath != null && log.photoUrl == null;
    final mealText = log.mealText;
    final meal = log.meal;
    return ChunkyCard(
      padding: const EdgeInsets.all(10),
      onTap: () => context.push('/food/${log.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              FoodPhoto(log: log, size: 72),
              if (pending)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Tooltip(
                    message: 'Foto menunggu diunggah',
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: GhinaColors.blue.base,
                        shape: BoxShape.circle,
                        border: Border.all(color: g.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.cloud_upload_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.name,
                  style: GhinaType.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (mealText != null)
                      ChunkyPill(
                        label: meal == null
                            ? mealText
                            : '${meal.emoji} ${meal.label}',
                        color: meal == null
                            ? GhinaColors.purple
                            : mealSwatch(meal),
                        soft: true,
                        uppercase: false,
                      ),
                    Text(
                      Fmt.time(log.date),
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                    if (log.calories != null)
                      Text(
                        '· ${_rowKcal(log)} kkal',
                        key: ValueKey('kcal-${log.id}'),
                        style: GhinaType.caption
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    if (log.transactionId case final txId?)
                      _LinkedAmount(key: ValueKey('linked-$txId'), id: txId),
                  ],
                ),
                if (log.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in log.tags)
                        ChunkyPill(
                          label: '#$t',
                          color: GhinaColors.blue,
                          soft: true,
                          uppercase: false,
                        ),
                    ],
                  ),
                ],
                if (log.note != null && log.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    log.note!,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The linked expense's amount on a food card.
class _LinkedAmount extends ConsumerWidget {
  const _LinkedAmount({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(watchTransactionProvider(id)).value;
    return FoodLinkBadge(
      label: v == null
          ? 'Tertaut'
          : Fmt.money(
              v.amount,
              currency: v.wallet?.currency ?? ref.watch(currencyProvider),
            ),
    );
  }
}
