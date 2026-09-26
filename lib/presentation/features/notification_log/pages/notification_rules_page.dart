import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../notification_log_format.dart';

/// Parsing rules: notifications from chosen apps that match a keyword/regex
/// become income/expense transactions. "Rule kamu" (user rules) + the
/// built-in presets (off until switched on).
class NotificationRulesPage extends ConsumerWidget {
  const NotificationRulesPage({super.key});

  Future<void> _toggleRule(
    BuildContext context,
    WidgetRef ref,
    NotificationRule rule,
    bool on,
  ) async {
    final r = await ref.read(setNotificationRuleEnabledProvider)(rule.id, on);
    if (r case Err(:final failure) when context.mounted) {
      showFailureToast(context, failure);
    }
  }

  Future<void> _togglePreset(
    BuildContext context,
    WidgetRef ref,
    NotificationRulePreset preset,
    NotificationRule? rule,
    bool on,
  ) async {
    final Result<void> r;
    if (on) {
      r = await ref.read(enableNotificationRulePresetProvider)(preset.key);
    } else if (rule != null) {
      r = await ref.read(setNotificationRuleEnabledProvider)(rule.id, false);
    } else {
      return;
    }
    if (!context.mounted) return;
    switch (r) {
      case Ok() when on:
        showOkToast(context, '${preset.name} aktif 👍');
      case Err(:final failure):
        showFailureToast(context, failure);
      case Ok():
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchNotificationRulesProvider);
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rule transaksi'),
        actions: [
          IconButton(
            key: const ValueKey('notif-rule-add'),
            tooltip: 'Tambah rule',
            icon: const Icon(Icons.add_circle_rounded),
            color: GhinaColors.green.base,
            onPressed: () => context.push('/notification-log/rules/new'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (async) {
        AsyncValue(:final value?) => _list(context, ref, value, wallets),
        AsyncValue(hasError: true) => ErrorRetry(
          onRetry: () => ref.invalidate(watchNotificationRulesProvider),
        ),
        _ => const LoadingListView(tiles: 4, hero: false),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<NotificationRule> rules,
    List<Wallet> wallets,
  ) {
    final own = rules.where((r) => r.presetKey == null).toList();
    final byPreset = {
      for (final r in rules)
        if (r.presetKey != null) r.presetKey!: r,
    };
    String walletName(NotificationRule r) =>
        wallets.where((w) => w.id == r.walletId).firstOrNull?.name ??
        'Dompet pertama';
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxxl,
      ),
      children: [
        const MascotSpeech(
          mood: MascotMood.thinking,
          mascotSize: 64,
          message:
              'Notifikasi dari aplikasi pilihanmu yang cocok dengan kata kunci '
              'bakal otomatis jadi transaksi. Nominal Rp-nya dibaca dari teks.',
        ),
        const SizedBox(height: GhinaSpace.xl),
        SectionHeader(
          title: 'Rule kamu',
          actionLabel: 'Tambah',
          onAction: () => context.push('/notification-log/rules/new'),
        ),
        if (own.isEmpty)
          EmptyState(
            compact: true,
            title: 'Belum ada rule',
            message:
                'Bikin sendiri, nyalakan preset di bawah, atau tap notifikasi di log → "Jadikan rule".',
            actionLabel: 'Bikin rule',
            onAction: () => context.push('/notification-log/rules/new'),
          )
        else
          for (final r in own)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
              child: _RuleTile(
                key: ValueKey('notif-rule-${r.id}'),
                title: r.name,
                subtitle: '${r.packages.join(', ')} · ${walletName(r)}',
                type: r.type,
                enabled: r.enabled,
                onChanged: (v) => _toggleRule(context, ref, r, v),
                onTap: () => context.push('/notification-log/rules/${r.id}'),
              ),
            ),
        const SizedBox(height: GhinaSpace.xl),
        const SectionHeader(
          title: 'Preset',
          subtitle: 'Bank & e-wallet populer — tinggal nyalakan',
        ),
        for (final p in notificationRulePresets)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
            child: _RuleTile(
              key: ValueKey('notif-preset-${p.key}'),
              title: byPreset[p.key]?.name ?? p.name,
              subtitle: byPreset[p.key] == null
                  ? p.packages.join(', ')
                  : '${byPreset[p.key]!.packages.join(', ')} · '
                        '${walletName(byPreset[p.key]!)}',
              type: byPreset[p.key]?.type ?? p.type,
              enabled: byPreset[p.key]?.enabled ?? false,
              onChanged: (v) =>
                  _togglePreset(context, ref, p, byPreset[p.key], v),
              onTap: () => byPreset[p.key] == null
                  ? context.push('/notification-log/rules/new', extra: p)
                  : context.push(
                      '/notification-log/rules/${byPreset[p.key]!.id}',
                    ),
            ),
          ),
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.enabled,
    required this.onChanged,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final TxType type;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChunkyTile(
    dense: true,
    leading: CategoryAvatar(
      icon: txTypeIcon(type),
      color: txTypeSwatch(type).base,
      size: 36,
      soft: !enabled,
    ),
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: enabled, onChanged: onChanged),
    onTap: onTap,
  );
}
