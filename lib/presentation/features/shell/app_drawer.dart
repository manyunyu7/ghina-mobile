import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../state/balance_privacy_provider.dart';
import '../../state/game/game_providers.dart';
import '../../state/session_controller.dart';
import '../../state/sync_status_provider.dart';
import '../settings/pages/settings_page.dart' show appVersion;
import 'app_menu.dart';
import 'sync_indicator.dart';

/// Gives the main tabs access to the shell's side drawer ([AppDrawer]).
/// Pages pushed outside the shell (e.g. `/wallets/:id/history`) have no scope.
class AppDrawerScope extends InheritedWidget {
  const AppDrawerScope({
    super.key,
    required this.scaffoldKey,
    required super.child,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;

  void open() => scaffoldKey.currentState?.openDrawer();
  void close() => scaffoldKey.currentState?.closeDrawer();

  static AppDrawerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDrawerScope>();

  @override
  bool updateShouldNotify(AppDrawerScope old) => old.scaffoldKey != scaffoldKey;
}

/// ☰ — opens the side drawer. Renders nothing outside the shell.
class AppDrawerButton extends StatelessWidget {
  const AppDrawerButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scope = AppDrawerScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('app-drawer-button'),
      tooltip: 'Semua menu',
      icon: Icon(Icons.menu_rounded, color: color),
      onPressed: scope.open,
    );
  }
}

/// "Semua menu": every screen grouped (Uang · Hidup · Produktif · Lainnya),
/// with a search box, the current screen highlighted, a few cheap badges and
/// a footer (sync state, "Sembunyikan saldo", version).
///
/// Tabs open with `go` (switch branch); everything else is pushed. Nothing
/// sensitive is shown (no amounts, no habit or task names).
class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key, required this.location});

  /// Current location (the active tab), for the highlight.
  final String location;

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  final _search = TextEditingController();
  final _activeKey = GlobalKey();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Bring the current screen's row into view (e.g. Tugas, far down).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.5);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _go(String path, {bool tab = false}) {
    final router = GoRouter.of(context);
    Scaffold.maybeOf(context)?.closeDrawer();
    if (tab) {
      router.go(path);
    } else {
      router.push(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final items = filterAppMenu(_query);
    final width = math.min(320.0, MediaQuery.sizeOf(context).width * 0.86);
    return Drawer(
      key: const ValueKey('app-drawer'),
      width: width,
      backgroundColor: g.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              active: widget.location == '/profile',
              onTap: () => _go('/profile', tab: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                key: const ValueKey('app-drawer-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                style: GhinaType.body.w(700).copyWith(color: g.textPrimary),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) {
                  if (items.length == 1) {
                    _go(items.single.path, tab: items.single.isTab);
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Cari menu…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? _NoResults(query: _query.trim())
                  // ~20 short rows: build them all (no lazy list) so the
                  // active one can be scrolled into view.
                  : SingleChildScrollView(
                      key: const ValueKey('app-drawer-list'),
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final group in AppMenuGroup.values)
                            if (items.any((i) => i.group == group)) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  10,
                                  2,
                                ),
                                child: Text(
                                  group.label,
                                  style: GhinaType.overline.copyWith(
                                    color: g.textMuted,
                                  ),
                                ),
                              ),
                              for (final item in items)
                                if (item.group == group)
                                  _MenuRow(
                                    key:
                                        isAppMenuItemActive(
                                          item,
                                          widget.location,
                                        )
                                        ? _activeKey
                                        : null,
                                    item: item,
                                    active: isAppMenuItemActive(
                                      item,
                                      widget.location,
                                    ),
                                    onTap: () =>
                                        _go(item.path, tab: item.isTab),
                                  ),
                            ],
                        ],
                      ),
                    ),
            ),
            _Footer(onSync: () => _go('/sync')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- header

class _Header extends ConsumerWidget {
  const _Header({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final user = ref.watch(currentUserProvider);
    final summary = ref.watch(gameSummaryProvider).value;
    final name = user?.name?.trim().isNotEmpty == true
        ? user!.name!.trim()
        : (user?.displayName ?? 'Kamu');
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Material(
        color: active
            ? GhinaColors.green.tint(g.brightness)
            : Colors.transparent,
        borderRadius: GhinaRadii.rXl,
        child: InkWell(
          key: const ValueKey('app-drawer-profile'),
          borderRadius: GhinaRadii.rXl,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
            child: Row(
              children: [
                const MascotView(size: 58, animate: false, showShadow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.h3
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 6),
                      if (summary != null)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LevelBadge(level: summary.level.level, size: 24),
                              const SizedBox(width: 8),
                              StatPill(
                                icon: Icons.bolt_rounded,
                                value: '${Fmt.number(summary.totalXp)} XP',
                                color: GhinaColors.yellow,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: g.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- rows

class _MenuRow extends ConsumerWidget {
  const _MenuRow({
    super.key,
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppMenuItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final badge = switch (item.path) {
      '/tasks' => _overdueTasks(ref),
      '/prayers' => _prayersLeft(ref),
      _ => null,
    };
    final accent = g.isDark ? item.color.base : item.color.edge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? item.color.tint(g.brightness) : Colors.transparent,
        borderRadius: GhinaRadii.rLg,
        child: InkWell(
          key: ValueKey('drawer-${item.path}'),
          borderRadius: GhinaRadii.rLg,
          onTap: onTap,
          child: Semantics(
            selected: active,
            button: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  CategoryAvatar(
                    icon: item.icon,
                    color: item.color.base,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.body
                          .w(active ? 900 : 800)
                          .copyWith(color: active ? accent : g.textPrimary),
                    ),
                  ),
                  ?badge,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _overdueTasks(WidgetRef ref) {
    final n = ref.watch(watchTaskHomeProvider).value?.overdueCount ?? 0;
    if (n <= 0) return null;
    return _CountBadge(
      key: const ValueKey('drawer-badge-/tasks'),
      count: n,
      color: GhinaColors.red,
      semantics: '$n tugas lewat tenggat',
    );
  }

  Widget? _prayersLeft(WidgetRef ref) {
    final today = startOfDay(ref.watch(clockProvider).now());
    final entries = ref
        .watch(watchPrayersProvider((from: today, to: today)))
        .value;
    if (entries == null) return null;
    final key = dateKey(today);
    final done = {
      for (final e in entries)
        if (e.date == key && e.prayer.kind == PrayerKind.fardhu) e.prayer,
    };
    final fardhu = Prayer.values.where((p) => p.kind == PrayerKind.fardhu);
    final left = fardhu.length - done.length;
    if (left <= 0) return null;
    return _CountBadge(
      key: const ValueKey('drawer-badge-/prayers'),
      count: left,
      color: GhinaColors.lime,
      semantics: '$left salat wajib belum dicatat hari ini',
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    super.key,
    required this.count,
    required this.color,
    required this.semantics,
  });

  final int count;
  final ChunkySwatch color;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.base,
        borderRadius: GhinaRadii.rPill,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: GhinaType.caption.w(900).copyWith(color: color.on),
      ),
    ),
  );
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(
          child: MascotView(
            mood: MascotMood.thinking,
            size: 88,
            animate: false,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Menu "$query" nggak ketemu',
          textAlign: TextAlign.center,
          style: GhinaType.h3.copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Coba kata lain, misalnya "budget", "saham" atau "doa".',
          textAlign: TextAlign.center,
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- footer

class _Footer extends ConsumerWidget {
  const _Footer({required this.onSync});

  final VoidCallback onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final hidden = ref.watch(balancePrivacyProvider.select((s) => s.hidden));
    final sync = ref.watch(syncStatusProvider).value ?? SyncStatus.initial;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: g.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sembunyikan saldo',
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
                Switch(
                  key: const ValueKey('app-drawer-privacy'),
                  value: hidden,
                  onChanged: (v) =>
                      ref.read(balancePrivacyProvider.notifier).setHidden(v),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SyncBadge(
                      state: syncIndicatorOf(sync),
                      pendingCount: sync.pendingCount,
                      onTap: onSync,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Ghina v$appVersion',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
