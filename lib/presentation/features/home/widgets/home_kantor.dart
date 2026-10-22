import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../kantor/kantor_data.dart';
import '../../kantor/kantor_format.dart';
import '../../kantor/widgets/kantor_inbox.dart';
import '../../kantor/widgets/kantor_sprite.dart';

const _dismissKey = 'home.kantor_invite_dismissed';

/// Whether the "set up Kantor" invitation was dismissed. Only affects the
/// not-configured state: once a token is saved the card always shows.
final homeKantorInviteDismissedProvider =
    AsyncNotifierProvider<HomeKantorInviteDismissed, bool>(
      HomeKantorInviteDismissed.new,
    );

class HomeKantorInviteDismissed extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_dismissKey) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismiss() async {
    state = const AsyncData(true);
    try {
      await (await SharedPreferences.getInstance()).setBool(_dismissKey, true);
    } catch (_) {}
  }
}

/// Beranda → "Kantor": waiting permissions (quick Izinkan/Tolak on the top
/// one), up to three working agents, this month's cost and shortcuts.
/// Loads on its own so it never delays the rest of Beranda.
class HomeKantorCard extends ConsumerWidget {
  const HomeKantorCard({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  /// Agents listed before "+N lainnya".
  static const maxAgents = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(kantorConfigProvider);
    // Config still loading (or secure storage unavailable): stay out of the way.
    if (!config.hasValue) return const SizedBox.shrink();
    final api = ref.watch(kantorApiProvider);

    final Widget body;
    if (api == null) {
      if (ref.watch(homeKantorInviteDismissedProvider).value ?? true) {
        return const SizedBox.shrink();
      }
      body = _SetupInvite(
        onDismiss: () =>
            ref.read(homeKantorInviteDismissedProvider.notifier).dismiss(),
      );
    } else {
      final st = ref.watch(kantorStateProvider);
      // Riverpod retries failed reads: a retry in flight still counts as the
      // error, so the card does not flicker back to a skeleton.
      body = st.hasValue
          ? _Content(state: st.requireValue)
          : st.hasError
          ? _Problem(
              error: st.error!,
              onRetry: () => ref.invalidate(kantorStateProvider),
            )
          : const Skeleton(height: 120, radius: 20);
    }
    return Padding(
      padding: padding,
      child: Column(
        key: const ValueKey('home-kantor'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Kantor',
            actionLabel: api == null ? null : 'Buka',
            onAction: api == null ? null : () => context.push('/kantor'),
          ),
          body,
        ],
      ),
    );
  }
}

class _SetupInvite extends StatelessWidget {
  const _SetupInvite({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pantau agen Claude-mu dari sini. Isi alamat dan token Kantor dulu.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.md),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Atur Kantor',
                  size: ChunkyButtonSize.small,
                  onPressed: () => context.push('/kantor/settings'),
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              Expanded(
                child: ChunkyButton(
                  label: 'Nanti saja',
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final kind = error is KantorException
        ? (error as KantorException).kind
        : KantorFailure.server;
    final (text, action, route) = switch (kind) {
      KantorFailure.unreachable => (
        'Kantor tidak terjangkau. Nyalakan Tailscale dan pastikan Mac kantor menyala.',
        'Coba lagi',
        null,
      ),
      KantorFailure.unauthorized => (
        'Token Kantor ditolak. Periksa di pengaturan.',
        'Pengaturan',
        '/kantor/settings',
      ),
      _ => ('Kantor belum bisa dibaca sekarang.', 'Coba lagi', null),
    };
    return ChunkyCard(
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: g.textMuted),
          const SizedBox(width: GhinaSpace.md),
          Expanded(
            child: Text(
              text,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
          const SizedBox(width: GhinaSpace.sm),
          TextButton(
            onPressed: route == null ? onRetry : () => context.push(route),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.state});

  final Map<String, dynamic> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final offices = (state['offices'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final inbox = state['inbox'] as List? ?? const [];
    final working = <(Map<String, dynamic>, Map<String, dynamic>)>[
      for (final o in offices)
        for (final s in (o['sessions'] as List? ?? const []))
          if (s is Map && s['status'] == 'working')
            (o, Map<String, dynamic>.from(s)),
    ];
    final cost = offices.fold<double>(
      0,
      (a, o) => a + ((o['monthCost'] as num?)?.toDouble() ?? 0),
    );
    final last = ref.watch(kantorLastOfficeProvider).value;
    final lastKnown = last != null && offices.any((o) => o['id'] == last);
    final base = lastKnown
        ? '/kantor/o/${Uri.encodeComponent(last)}'
        : '/kantor';
    final shown = working.take(HomeKantorCard.maxAgents).toList();
    // Held requests can be answered here; the rest only live in a terminal.
    final top = inbox.where((e) => e is Map && e['held'] == true).take(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inbox.isNotEmpty) ...[
          Row(
            children: [
              ChunkyPill(
                label: '${inbox.length} izin menunggu',
                color: GhinaColors.orange,
                soft: true,
              ),
            ],
          ),
          const SizedBox(height: GhinaSpace.sm),
          if (top.isNotEmpty)
            KantorInboxList(items: top.toList(), offices: offices),
        ],
        ChunkyCard(
          padding: const EdgeInsets.all(GhinaSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shown.isEmpty)
                Text(
                  'Belum ada agen yang bekerja.',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                )
              else ...[
                for (final (o, s) in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                    child: Row(
                      children: [
                        KantorSprite(
                          look: s['look'] is Map
                              ? Map<String, dynamic>.from(s['look'] as Map)
                              : KantorSprite.guestLook('${s['sid']}'),
                          size: 28,
                        ),
                        const SizedBox(width: GhinaSpace.sm),
                        Expanded(
                          child: Text(
                            '${(s['look'] as Map?)?['name'] ?? o['name']} · '
                            '${kantorShort(kantorSessionLabel(s), 36)}',
                            style: GhinaType.bodyS.copyWith(
                              color: g.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (working.length > shown.length)
                  Text(
                    '+${working.length - shown.length} lainnya',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
              const SizedBox(height: GhinaSpace.xs),
              Text(
                '${kantorUsd(cost, 0)} bulan ini (estimasi)',
                key: const ValueKey('home-kantor-cost'),
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: GhinaSpace.md),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: 'Buka Kantor',
                      size: ChunkyButtonSize.small,
                      onPressed: () => context.push(base),
                    ),
                  ),
                  const SizedBox(width: GhinaSpace.sm),
                  Expanded(
                    child: ChunkyButton(
                      label: 'Suruh manager',
                      size: ChunkyButtonSize.small,
                      variant: ChunkyButtonVariant.secondary,
                      onPressed: () =>
                          context.push(lastKnown ? '$base?tab=kantor' : base),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
