import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'habit_lock.dart';

/// Wraps every Habits page: shows [child] when "Kunci Kebiasaan" is off or
/// unlocked this session, the lock screen otherwise (prompting right away).
class HabitLockGate extends ConsumerStatefulWidget {
  const HabitLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HabitLockGate> createState() => _HabitLockGateState();
}

class _HabitLockGateState extends ConsumerState<HabitLockGate> {
  bool _autoPrompted = false;
  HabitAuthOutcome? _last;

  Future<void> _unlock() async {
    final r = await ref.read(habitLockProvider.notifier).unlock();
    if (!mounted) return;
    setState(() => _last = r);
    if (r == HabitAuthOutcome.unavailable) {
      showToastBadge(
        context,
        message: 'HP-mu belum pakai kunci layar, jadi Kebiasaan dibuka dulu.',
        icon: Icons.lock_open_rounded,
        color: GhinaColors.orange,
        duration: const Duration(milliseconds: 3200),
      );
    }
  }

  /// The page was shown (unlocked) at least once: from then on it stays
  /// mounted — hidden, not rebuilt — while the area re-locks, so a re-lock
  /// after backgrounding keeps unsaved form input and doesn't re-run the
  /// page's `initState` (the emergency screen would log a second urge).
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(habitLockProvider);
    final locked = lock.locked;
    if (!locked) {
      _autoPrompted = false;
      _shown = true;
    } else if (lock.loaded && !_autoPrompted) {
      _autoPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unlock();
      });
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: locked,
          child: TickerMode(
            enabled: !locked,
            child: ExcludeFocus(
              excluding: locked,
              child: ExcludeSemantics(
                excluding: locked,
                child: _shown ? widget.child : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        if (locked)
          lock.loaded
              ? HabitLockScreen(
                  busy: lock.busy,
                  message: switch (_last) {
                    HabitAuthOutcome.lockedOut =>
                      'Terlalu banyak percobaan. Tunggu sebentar, lalu coba lagi ya.',
                    HabitAuthOutcome.error =>
                      'Ups, kuncinya belum bisa dibuka. Coba lagi, yuk.',
                    _ => null,
                  },
                  onUnlock: _unlock,
                )
              : const Scaffold(body: Center(child: SizedBox.shrink())),
      ],
    );
  }
}

/// The calm lock screen of the Habits area.
class HabitLockScreen extends StatelessWidget {
  const HabitLockScreen({
    super.key,
    required this.onUnlock,
    this.busy = false,
    this.message,
  });

  final VoidCallback onUnlock;
  final bool busy;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => popOr(context, '/home')),
        title: const Text('Kebiasaan'),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: c.maxHeight - GhinaSpace.page * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const MascotView(mood: MascotMood.thinking, size: 120),
                      Positioned(
                        right: -6,
                        bottom: 4,
                        child: CategoryAvatar(
                          icon: Icons.lock_rounded,
                          color: GhinaColors.purple.base,
                          size: 44,
                        ),
                      ),
                    ],
                  ),
                  GhinaSpace.gapLg,
                  Text(
                    'Kebiasaan terkunci 🔒',
                    textAlign: TextAlign.center,
                    style: GhinaType.h2.copyWith(color: g.textPrimary),
                  ),
                  GhinaSpace.gapSm,
                  Text(
                    message ??
                        'Buka pakai sidik jari, wajah, atau PIN HP-mu. '
                            'Cuma kamu yang bisa lihat.',
                    textAlign: TextAlign.center,
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  ),
                  GhinaSpace.gapXl,
                  ChunkyButton(
                    key: const ValueKey('habit-unlock'),
                    label: 'Buka kunci',
                    icon: Icons.fingerprint_rounded,
                    loading: busy,
                    onPressed: busy ? null : onUnlock,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings → Privasi: the "Kunci Kebiasaan" switch row.
class HabitLockSettingTile extends ConsumerWidget {
  const HabitLockSettingTile({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on) async {
    final r = await ref.read(habitLockProvider.notifier).setEnabled(on);
    if (!context.mounted) return;
    switch (r) {
      case HabitLockToggle.changed:
        showToastBadge(
          context,
          message: on
              ? 'Kebiasaan sekarang terkunci 🔒'
              : 'Kunci Kebiasaan mati',
          icon: on ? Icons.lock_rounded : Icons.lock_open_rounded,
          color: GhinaColors.purple,
        );
      case HabitLockToggle.noDeviceLock:
        await showChunkyDialog<void>(
          context,
          builder: (c) => ChunkyDialog(
            title: 'Pasang kunci layar dulu, ya',
            message:
                'Kunci Kebiasaan memakai sidik jari, wajah, atau PIN HP. '
                'Aktifkan kunci layar di pengaturan HP-mu, lalu coba lagi.',
            mood: MascotMood.thinking,
            actions: [
              ChunkyButton(
                label: 'Oke',
                onPressed: () => Navigator.of(c).pop(),
              ),
            ],
          ),
        );
      case HabitLockToggle.failed:
        showErrorToast(context, 'Belum terverifikasi. Coba lagi, yuk.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(habitLockProvider);
    return ChunkyTile(
      framed: false,
      title: 'Kunci Kebiasaan',
      subtitle: 'Buka halaman Kebiasaan pakai sidik jari / PIN HP',
      leading: CategoryAvatar(
        icon: Icons.fingerprint_rounded,
        color: GhinaColors.green.base,
        size: 40,
      ),
      trailing: Switch(
        key: const ValueKey('settings-habit-lock'),
        value: lock.enabled,
        onChanged: lock.busy || !lock.loaded
            ? null
            : (v) => _toggle(context, ref, v),
      ),
      onTap: lock.busy || !lock.loaded
          ? null
          : () => _toggle(context, ref, !lock.enabled),
    );
  }
}
