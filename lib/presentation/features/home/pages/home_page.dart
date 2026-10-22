import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/game/task_game_providers.dart';
import '../../../state/killa_access_provider.dart';
import '../../../state/session_controller.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../layout/home_card_builder.dart';
import '../layout/home_layout.dart';
import '../layout/home_layout_store.dart';
import '../widgets/home_sections.dart';
import 'home_layout_editor.dart';

/// Beranda: game stats, mascot, daily goal, money overview, shortcuts, and what's
/// coming up. Also presents pending reward celebrations whenever it's on screen.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _celebrating = false;

  bool get _visible =>
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  void _maybeCelebrate() {
    if (_celebrating) return;
    _celebrating = true;
    unawaited(_runCelebrations());
  }

  Future<void> _runCelebrations() async {
    try {
      // Let pushed screens finish closing (and possibly celebrate themselves) first.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || !_visible) return;
      await presentPendingCelebrations(context);
    } finally {
      _celebrating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final now = ref.watch(clockProvider).now();
    final user = ref.watch(currentUserProvider);
    final game = ref.watch(gameSummaryProvider);
    final summary = game.value;
    // Records yesterday's "FIRE kosong" snapshot on the first open of a day.
    ref.listen(fireClearRecorderProvider, (_, _) {});

    if (summary != null && summary.celebrations.isNotEmpty && _visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeCelebrate();
      });
    }

    final hour = now.hour;
    final greeting = hour < 11
        ? 'Selamat pagi'
        : hour < 15
        ? 'Selamat siang'
        : hour < 19
        ? 'Selamat sore'
        : 'Selamat malam';

    // Killa is for allowlisted accounts only: no shortcut after a 403.
    final killaLocked = ref.watch(killaAccessProvider) == KillaAccess.forbidden;

    return Scaffold(
      floatingActionButton: killaLocked
          ? null
          : FloatingActionButton(
              key: const ValueKey('home-killa-fab'),
              heroTag: 'home-killa-fab',
              tooltip: 'Killa',
              backgroundColor: GhinaColors.purple.base,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/killa'),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            HomeStatsBar(summary: summary),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => pullToSync(context, ref),
                child: ListView(
                  key: const PageStorageKey('home-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.lg,
                    GhinaSpace.page,
                    // Room for the Killa button over the last card.
                    killaLocked ? GhinaSpace.xxl : GhinaSpace.xxl + 64,
                  ),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$greeting, ${user?.displayName ?? 'kamu'}!',
                            style: GhinaType.h1.copyWith(color: g.textPrimary),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('home-customize'),
                          tooltip: 'Atur beranda',
                          icon: Icon(
                            Icons.tune_rounded,
                            color: g.textSecondary,
                          ),
                          onPressed: _openEditor,
                        ),
                      ],
                    ),
                    Text(
                      Fmt.dateFull(now),
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                    GhinaSpace.gapLg,
                    ..._cards(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The cards of the saved layout. Consecutive small cards pair up in a row.
  List<Widget> _cards() {
    final layout = ref.watch(homeLayoutProvider);
    final builder = HomeCardBuilder(
      context: context,
      ref: ref,
      now: ref.watch(clockProvider).now(),
      currency: ref.watch(currencyProvider),
    );
    final built = <(HomeEntry, Widget)>[];
    for (final e in layout.entries) {
      final w = builder.build(e, first: built.isEmpty);
      if (w != null) built.add((e, w));
    }
    if (built.isEmpty) {
      return [
        EmptyState(
          compact: true,
          title: 'Berandamu kosong',
          message: 'Pilih kartu atau preset lewat tombol Atur beranda.',
          actionLabel: 'Atur beranda',
          onAction: _openEditor,
        ),
      ];
    }
    final out = <Widget>[];
    var prevSmall = false;
    for (var i = 0; i < built.length; i++) {
      final (e, w) = built[i];
      final small = e.size == HomeCardSize.small;
      if (small) {
        final next =
            i + 1 < built.length && built[i + 1].$1.size == HomeCardSize.small
            ? built[i + 1].$2
            : null;
        if (out.isNotEmpty) {
          out.add(prevSmall ? GhinaSpace.gapMd : GhinaSpace.gapXl);
        }
        out.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: w),
                GhinaSpace.gapMd,
                Expanded(child: next ?? const SizedBox.shrink()),
              ],
            ),
          ),
        );
        if (next != null) i++;
        prevSmall = true;
        continue;
      }
      if (out.isNotEmpty && !HomeCardBuilder.selfSpaced(e)) {
        out.add(GhinaSpace.gapXl);
      }
      out.add(w);
      prevSmall = false;
    }
    return out;
  }

  void _openEditor() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const HomeLayoutEditorPage()));
}
