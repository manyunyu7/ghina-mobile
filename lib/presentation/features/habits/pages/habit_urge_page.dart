import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../lock/habit_lock_gate.dart';
import '../widgets/box_breathing.dart';
import '../widgets/relapse_sheet.dart';

/// "Lagi pengen…" — the emergency screen of a quit habit. Logs the urge right
/// away, then 60 s of box breathing with the habit's `why`, a gentle line,
/// the clean streak and quick ideas. Ends with "Berhasil tahan 💪" (keeps
/// the urge, XP toast) or "Aku kalah kali ini" (converts it to a relapse).
class HabitUrgePage extends StatelessWidget {
  const HabitUrgePage({super.key, required this.id, this.random});

  final String id;

  /// Picks the encouragement (tests pass a seeded one).
  final math.Random? random;

  @override
  Widget build(BuildContext context) => HabitLockGate(
    child: _UrgeView(id: id, random: random),
  );
}

class _UrgeView extends ConsumerStatefulWidget {
  const _UrgeView({required this.id, this.random});

  final String id;
  final math.Random? random;

  @override
  ConsumerState<_UrgeView> createState() => _UrgeViewState();
}

class _UrgeViewState extends ConsumerState<_UrgeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown = AnimationController(
    vsync: this,
    duration: const Duration(seconds: urgeBreathingSeconds),
  );
  late final String _line;
  RewardTracker? _rewards;

  /// null = logging, true = logged, false = failed.
  bool? _logged;
  bool _finishing = false;
  final Set<int> _ideasDone = {};

  @override
  void initState() {
    super.initState();
    final r = widget.random ?? math.Random();
    _line = urgeEncouragements[r.nextInt(urgeEncouragements.length)];
    _countdown.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        if (mounted) setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _logUrge());
  }

  @override
  void dispose() {
    _rewards?.cancel();
    _countdown.dispose();
    super.dispose();
  }

  Future<void> _logUrge() async {
    setState(() => _logged = null);
    final rewards = await RewardTracker.startLoaded(ref);
    if (!mounted) {
      rewards.cancel();
      return;
    }
    final r = await ref.read(logUrgeProvider)(
      widget.id,
      at: ref.read(clockProvider).now(),
    );
    if (!mounted) {
      rewards.cancel();
      return;
    }
    switch (r) {
      case Ok():
        _rewards = rewards;
        setState(() => _logged = true);
        _countdown.forward(from: 0);
      case Err(:final failure):
        rewards.cancel();
        setState(() => _logged = false);
        showFailureToast(context, failure);
    }
  }

  Future<void> _resisted() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final rewards = _rewards;
    _rewards = null;
    if (rewards != null) {
      await rewards.finish(
        context,
        xpToast: (xp) => 'Kamu menang! +$xp XP 💪',
        doneToast: 'Hebat, kamu berhasil tahan 💪',
      );
    }
    if (mounted) popOr(context, '/habits');
  }

  Future<void> _lost(HabitToday today) async {
    final logged = await showRelapseSheet(
      context,
      today: today,
      convertUrge: true,
    );
    if (!logged || !mounted) return;
    _rewards?.cancel();
    _rewards = null;
    popOr(context, '/habits');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final today = ref.watch(watchHabitTodayProvider(widget.id)).value;
    final habit = today?.habit;
    final done = _countdown.isCompleted;
    final calm = g.isDark
        ? Color.alphaBlend(
            GhinaColors.blue.base.withValues(alpha: 0.08),
            g.background,
          )
        : const Color(0xFFEFF8FE);

    return Scaffold(
      backgroundColor: calm,
      appBar: AppBar(
        backgroundColor: calm,
        leading: IconButton(
          key: const ValueKey('urge-close'),
          tooltip: 'Tutup',
          icon: const Icon(Icons.close_rounded),
          onPressed: _finishing ? null : _resisted,
        ),
        title: const Text('Tarik napas dulu'),
      ),
      body: SafeArea(
        top: false,
        child: _logged == false
            ? ErrorRetry(onRetry: _logUrge)
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  0,
                  GhinaSpace.page,
                  GhinaSpace.xxl,
                ),
                children: [
                  Text(
                    'Rasa pengen itu kayak ombak — naik, lalu turun. '
                    'Ikuti lingkarannya 60 detik, ya.',
                    textAlign: TextAlign.center,
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  ),
                  GhinaSpace.gapLg,
                  Center(
                    child: LayoutBuilder(
                      builder: (context, c) => BoxBreathing(
                        size: math.min(240, c.maxWidth * 0.7),
                        running: !done,
                      ),
                    ),
                  ),
                  GhinaSpace.gapMd,
                  AnimatedBuilder(
                    animation: _countdown,
                    builder: (context, _) {
                      final left =
                          (urgeBreathingSeconds * (1 - _countdown.value))
                              .ceil();
                      return Column(
                        children: [
                          ChunkyProgressBar(
                            value: _countdown.value,
                            color: GhinaColors.blue,
                            height: 10,
                            animate: false,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            done ? 'Selesai 🌿' : '$left detik lagi',
                            key: const ValueKey('urge-countdown'),
                            style: GhinaType.bodyS
                                .w(800)
                                .copyWith(color: g.textSecondary),
                          ),
                        ],
                      );
                    },
                  ),
                  GhinaSpace.gapLg,
                  if (done && today != null)
                    _EndChoice(
                      finishing: _finishing,
                      onResisted: _resisted,
                      onLost: () => _lost(today),
                    )
                  else ...[
                    ChunkyCard(
                      tinted: GhinaColors.blue,
                      child: Text(
                        _line,
                        key: const ValueKey('urge-encouragement'),
                        textAlign: TextAlign.center,
                        style: GhinaType.bodyL
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (habit?.why case final why?) ...[
                      GhinaSpace.gapMd,
                      ChunkyCard(
                        key: const ValueKey('urge-why'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ALASANMU',
                              style: GhinaType.overline.copyWith(
                                color: g.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              why,
                              style: GhinaType.body
                                  .w(700)
                                  .copyWith(color: g.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (today != null && today.streak.current > 0) ...[
                      GhinaSpace.gapMd,
                      ChunkyTile(
                        leading: CategoryAvatar(
                          icon: Icons.park_rounded,
                          color: GhinaColors.green.base,
                          size: 40,
                        ),
                        title: 'Hari bersih ke-${today.streak.current}',
                        subtitle: 'Jangan biarkan 60 detik menghapusnya',
                      ),
                    ],
                    GhinaSpace.gapLg,
                    Text(
                      'SAMBIL NUNGGU, COBA:',
                      style: GhinaType.overline.copyWith(color: g.textMuted),
                    ),
                    GhinaSpace.gapSm,
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (i, idea) in urgeQuickActions.indexed)
                          ChunkyChip(
                            label: idea,
                            icon: _ideaIcons[i % _ideaIcons.length],
                            selected: _ideasDone.contains(i),
                            color: GhinaColors.green,
                            onTap: () => setState(() {
                              if (!_ideasDone.remove(i)) _ideasDone.add(i);
                            }),
                          ),
                      ],
                    ),
                    GhinaSpace.gapXl,
                    Center(
                      child: TextButton(
                        key: const ValueKey('urge-early'),
                        onPressed: _logged == true && !_finishing
                            ? _resisted
                            : null,
                        child: const Text('Udah tenang? Selesai lebih awal'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

const _ideaIcons = [
  Icons.directions_walk_rounded,
  Icons.local_drink_rounded,
  Icons.call_rounded,
  Icons.air_rounded,
];

class _EndChoice extends StatelessWidget {
  const _EndChoice({
    required this.finishing,
    required this.onResisted,
    required this.onLost,
  });

  final bool finishing;
  final VoidCallback onResisted;
  final VoidCallback onLost;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return PopIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Berhasil tahan? 💪',
            textAlign: TextAlign.center,
            style: GhinaType.h1.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Apa pun jawabannya, kamu sudah berani berhenti sejenak.',
            textAlign: TextAlign.center,
            style: GhinaType.body.copyWith(color: g.textSecondary),
          ),
          GhinaSpace.gapLg,
          ChunkyButton(
            key: const ValueKey('urge-resisted'),
            label: 'Berhasil tahan 💪',
            loading: finishing,
            onPressed: finishing ? null : onResisted,
          ),
          GhinaSpace.gapSm,
          ChunkyButton(
            key: const ValueKey('urge-lost'),
            label: 'Aku kalah kali ini',
            variant: ChunkyButtonVariant.outline,
            uppercase: false,
            onPressed: finishing ? null : onLost,
          ),
        ],
      ),
    );
  }
}
