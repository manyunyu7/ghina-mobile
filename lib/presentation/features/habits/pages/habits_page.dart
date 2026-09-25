import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/habit_actions.dart';
import '../lock/habit_lock.dart';
import '../lock/habit_lock_gate.dart';
import '../widgets/habit_cards.dart';

/// Kebiasaan: today's board — "Membangun" and "Berhenti" — plus reorder and
/// the archive. Behind "Kunci Kebiasaan" when it's on.
class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const HabitLockGate(child: _HabitsView());
}

class _HabitsView extends ConsumerStatefulWidget {
  const _HabitsView();

  @override
  ConsumerState<_HabitsView> createState() => _HabitsViewState();
}

class _HabitsViewState extends ConsumerState<_HabitsView> {
  bool _reorder = false;
  bool _showArchived = false;
  bool _celebrated = false;

  void _maybeCelebrate(HabitBoard board) {
    if (_celebrated || board.isEmpty) return;
    _celebrated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      await celebrateHabitMilestones(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(watchHabitBoardProvider);
    final lock = ref.watch(habitLockProvider);
    final value = board.value;
    if (value != null) _maybeCelebrate(value);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kebiasaan'),
        actions: [
          if (lock.enabled)
            IconButton(
              tooltip: 'Kunci sekarang',
              icon: const Icon(Icons.lock_rounded),
              onPressed: () {
                ref.read(habitLockProvider.notifier).lockNow();
              },
            ),
          if (value != null && value.items.length > 1)
            IconButton(
              key: const ValueKey('habit-reorder'),
              tooltip: _reorder ? 'Selesai' : 'Urutkan',
              icon: Icon(
                _reorder ? Icons.check_rounded : Icons.swap_vert_rounded,
              ),
              onPressed: () => setState(() => _reorder = !_reorder),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChunkyIconButton(
              key: const ValueKey('habit-add'),
              icon: Icons.add_rounded,
              size: 40,
              color: GhinaColors.green,
              tooltip: 'Kebiasaan baru',
              onPressed: () => context.push('/habits/new'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => pullToSync(context, ref),
          child: switch (board) {
            AsyncValue(:final value?) when _reorder => _ReorderList(
              board: value,
            ),
            AsyncValue(:final value?) => _Board(
              board: value,
              showArchived: _showArchived,
              onToggleArchived: () =>
                  setState(() => _showArchived = !_showArchived),
            ),
            AsyncError() => ScrollableFill(
              child: ErrorRetry(
                onRetry: () => ref.invalidate(watchHabitBoardProvider),
              ),
            ),
            _ => const LoadingListView(tiles: 4, hero: true),
          },
        ),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({
    required this.board,
    required this.showArchived,
    required this.onToggleArchived,
  });

  final HabitBoard board;
  final bool showArchived;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = [
      for (final h
          in ref.watch(watchAllHabitsProvider).value ?? const <Habit>[])
        if (h.archived) h,
    ];
    if (board.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(GhinaSpace.page),
        children: [
          const SizedBox(height: 24),
          EmptyState(
            key: const ValueKey('habits-empty'),
            mood: MascotMood.waving,
            title: 'Yuk mulai satu kebiasaan',
            message:
                'Bangun yang baik (olahraga, baca, minum air) atau tinggalkan '
                'yang kurang baik (rokok, begadang). Ghina temani tiap hari 🌱',
            actionLabel: 'Buat kebiasaan',
            onAction: () => context.push('/habits/new'),
          ),
          if (archived.isNotEmpty) ...[
            GhinaSpace.gapXl,
            _ArchiveSection(
              habits: archived,
              open: showArchived,
              onToggle: onToggleArchived,
            ),
          ],
        ],
      );
    }
    final build = board.build.toList();
    final quit = board.quit.toList();
    var i = 0;
    Widget pop(Widget w) => PopIn(
      delay: Duration(milliseconds: i < 5 ? 50 * i++ : 0),
      child: w,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      children: [
        _Summary(board: board),
        if (build.isNotEmpty) ...[
          GhinaSpace.gapXl,
          SectionHeader(
            title: 'Membangun',
            subtitle: board.dueCount == 0
                ? 'Nggak ada jadwal hari ini'
                : '${board.metCount}/${board.dueCount} tercapai hari ini',
          ),
          for (final t in build) ...[
            pop(BuildHabitCard(today: t)),
            GhinaSpace.gapMd,
          ],
        ],
        if (quit.isNotEmpty) ...[
          GhinaSpace.gapLg,
          const SectionHeader(
            title: 'Berhenti',
            subtitle: 'Satu hari bersih pada satu waktu',
          ),
          for (final t in quit) ...[
            pop(QuitHabitCard(today: t)),
            GhinaSpace.gapMd,
          ],
        ],
        if (archived.isNotEmpty) ...[
          GhinaSpace.gapLg,
          _ArchiveSection(
            habits: archived,
            open: showArchived,
            onToggle: onToggleArchived,
          ),
        ],
      ],
    );
  }
}

/// Mascot + today's progress ring.
class _Summary extends StatelessWidget {
  const _Summary({required this.board});

  final HabitBoard board;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final due = board.dueCount;
    final met = board.metCount;
    final quit = board.quit.toList();
    final clean = quit.where((q) => !q.relapsedToday).length;
    final allMet = board.allMet;
    final message = board.build.isEmpty
        ? (clean == quit.length
              ? 'Semua masih bersih hari ini. Kamu hebat 🌳'
              : 'Hari berat itu wajar. Besok kita mulai lagi, ya 🌱')
        : allMet
        ? 'Semua kebiasaan hari ini beres! Mantap 🎉'
        : due == 0
        ? 'Hari ini santai. Istirahat juga penting ✨'
        : 'Tinggal ${due - met} lagi. Pelan-pelan, kamu pasti bisa!';
    return ChunkyCard(
      tinted: allMet ? GhinaColors.green : null,
      child: Row(
        children: [
          MascotView(
            mood: allMet ? MascotMood.excited : MascotMood.happy,
            size: 64,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hari ini',
                  style: GhinaType.overline.copyWith(color: g.textMuted),
                ),
                Text(
                  message,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
              ],
            ),
          ),
          if (due > 0) ...[
            const SizedBox(width: 8),
            ProgressRing(
              value: due == 0 ? 0 : met / due,
              size: 58,
              stroke: 7,
              color: GhinaColors.green,
              child: Text(
                '$met/$due',
                style: GhinaType.bodyS.w(900).copyWith(color: g.textPrimary),
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchiveSection extends ConsumerWidget {
  const _ArchiveSection({
    required this.habits,
    required this.open,
    required this.onToggle,
  });

  final List<Habit> habits;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTile(
          key: const ValueKey('habit-archive-toggle'),
          title: 'Diarsipkan (${habits.length})',
          subtitle: 'Riwayatnya tetap tersimpan',
          leading: CategoryAvatar(
            icon: Icons.inventory_2_rounded,
            color: GhinaColors.gray.base,
            size: 40,
          ),
          trailing: Icon(
            open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          ),
          onTap: onToggle,
        ),
        if (open)
          for (final h in habits) ...[
            GhinaSpace.gapSm,
            ChunkyTile(
              title: h.name,
              subtitle: h.kind.label,
              leading: HabitAvatar(habit: h, size: 40),
              onTap: () => context.push('/habits/${h.id}'),
              trailing: TextButton(
                key: ValueKey('habit-unarchive-${h.id}'),
                onPressed: () async {
                  final r = await ref.read(setHabitArchivedProvider)(
                    h.id,
                    false,
                  );
                  if (!context.mounted) return;
                  switch (r) {
                    case Ok():
                      showOkToast(context, 'Aktif lagi 👍');
                    case Err(:final failure):
                      showFailureToast(context, failure);
                  }
                },
                child: const Text('Aktifkan'),
              ),
            ),
          ],
      ],
    );
  }
}

class _ReorderList extends ConsumerStatefulWidget {
  const _ReorderList({required this.board});

  final HabitBoard board;

  @override
  ConsumerState<_ReorderList> createState() => _ReorderListState();
}

class _ReorderListState extends ConsumerState<_ReorderList> {
  late List<Habit> _items = [for (final t in widget.board.items) t.habit];

  @override
  void didUpdateWidget(_ReorderList old) {
    super.didUpdateWidget(old);
    final ids = {for (final t in widget.board.items) t.id};
    if (ids.length != _items.length ||
        !_items.every((h) => ids.contains(h.id))) {
      _items = [for (final t in widget.board.items) t.habit];
    }
  }

  Future<void> _onReorder(int from, int to) async {
    setState(() {
      final h = _items.removeAt(from);
      _items.insert(to, h);
    });
    final r = await ref.read(reorderHabitsProvider)([
      for (final h in _items) h.id,
    ]);
    if (r case Err(:final failure) when mounted) {
      showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Tahan & geser untuk mengubah urutan',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      ),
      itemCount: _items.length,
      onReorderItem: _onReorder,
      itemBuilder: (context, i) {
        final h = _items[i];
        return Padding(
          key: ValueKey('habit-order-${h.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            title: h.name,
            subtitle: h.isQuit ? 'Berhenti' : 'Membangun',
            leading: HabitAvatar(habit: h, size: 40),
            trailing: ReorderableDragStartListener(
              index: i,
              child: Icon(Icons.drag_handle_rounded, color: g.textMuted),
            ),
          ),
        );
      },
    );
  }
}
