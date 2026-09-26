import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../notification_log_format.dart';
import '../widgets/listener_status_card.dart';

/// "Log Notifikasi" (Android): notifications captured from other apps, newest
/// first, with search, a per-app filter and "Hapus". Entries turned into a
/// transaction by a rule get an income/expense badge; any entry can become a
/// new rule ("Jadikan rule").
class NotificationLogPage extends ConsumerStatefulWidget {
  const NotificationLogPage({super.key});

  @override
  ConsumerState<NotificationLogPage> createState() =>
      _NotificationLogPageState();
}

class _NotificationLogPageState extends ConsumerState<NotificationLogPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _package;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  NotificationLogQuery get _filter => (
    packageName: _package,
    search: _query.trim().isEmpty ? null : _query.trim(),
  );

  Future<void> _clear(List<NotificationSource> sources) async {
    final app = sources.where((s) => s.packageName == _package).firstOrNull;
    final ok = await showChunkyConfirm(
      context,
      title: app == null
          ? 'Hapus semua log notifikasi?'
          : 'Hapus log dari ${app.displayAppName}?',
      message:
          'Cuma log-nya yang dihapus. Transaksi yang sudah tercatat tetap aman.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(clearCapturedNotificationsProvider)(
      packageName: _package,
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        setState(() => _package = null);
        showOkToast(context, '$value notifikasi dihapus');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _openActions(CapturedNotification n) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: n.displayAppName,
      showClose: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n.transactionId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChunkyTile(
                dense: true,
                leading: const Icon(Icons.receipt_long_rounded),
                title: 'Lihat transaksi',
                showChevron: true,
                onTap: () => Navigator.of(c).pop('tx'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              key: const ValueKey('notif-make-rule'),
              dense: true,
              leading: const Icon(Icons.rule_rounded),
              title: 'Jadikan rule',
              subtitle: 'Catat notifikasi seperti ini jadi transaksi',
              showChevron: true,
              onTap: () => Navigator.of(c).pop('rule'),
            ),
          ),
          ChunkyTile(
            dense: true,
            leading: const Icon(Icons.copy_rounded),
            title: 'Salin teks',
            onTap: () => Navigator.of(c).pop('copy'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'tx':
        context.push('/transactions/${n.transactionId}');
      case 'rule':
        context.push(
          '/notification-log/rules/new',
          extra: NotificationRuleDraft.fromNotification(n),
        );
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: [n.title, n.body].join('\n').trim()),
        );
        if (mounted) showOkToast(context, 'Teks disalin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(deviceNotificationListenerProvider).isSupported;
    if (!supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Log Notifikasi')),
        body: const Center(
          child: EmptyState(
            mood: MascotMood.thinking,
            title: 'Khusus Android',
            message:
                'iPhone nggak mengizinkan aplikasi membaca notifikasi dari aplikasi lain.',
          ),
        ),
      );
    }
    final sources =
        ref.watch(watchNotificationSourcesProvider).value ??
        const <NotificationSource>[];
    final async = ref.watch(watchCapturedNotificationsProvider(_filter));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Notifikasi'),
        actions: [
          IconButton(
            key: const ValueKey('notif-rules'),
            tooltip: 'Rule transaksi',
            icon: const Icon(Icons.rule_rounded),
            onPressed: () => context.push('/notification-log/rules'),
          ),
          IconButton(
            key: const ValueKey('notif-clear'),
            tooltip: 'Hapus log',
            icon: Icon(Icons.delete_sweep_rounded, color: GhinaColors.red.base),
            onPressed: sources.isEmpty ? null : () => _clear(sources),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              0,
            ),
            sliver: SliverList.list(
              children: [
                const ListenerStatusCard(),
                const SizedBox(height: GhinaSpace.lg),
                ChunkyTextField(
                  key: const ValueKey('notif-search'),
                  controller: _search,
                  hint: 'Cari judul, isi atau aplikasi…',
                  prefixIcon: Icons.search_rounded,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  suffix: _query.isEmpty
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
                if (sources.length > 1) ...[
                  const SizedBox(height: GhinaSpace.md),
                  ChunkyChoiceChips<String>(
                    key: const ValueKey('notif-app-filter'),
                    scrollable: true,
                    options: [
                      const ChunkyChoice(value: '', label: 'Semua'),
                      for (final s in sources)
                        ChunkyChoice(
                          value: s.packageName,
                          label: '${s.displayAppName} (${s.count})',
                        ),
                    ],
                    selected: {_package ?? ''},
                    onChanged: (v) => setState(() {
                      final p = v.isEmpty ? '' : v.first;
                      _package = p.isEmpty ? null : p;
                    }),
                  ),
                ],
                const SizedBox(height: GhinaSpace.md),
              ],
            ),
          ),
          switch (async) {
            AsyncValue(:final value?) when value.isEmpty => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                compact: true,
                title: _query.isNotEmpty || _package != null
                    ? 'Nggak ada yang cocok'
                    : 'Belum ada notifikasi',
                message: _query.isNotEmpty || _package != null
                    ? 'Coba kata lain atau pilih "Semua".'
                    : 'Nyalakan "Catat notifikasi" di atas, nanti notifikasi baru muncul di sini.',
              ),
            ),
            AsyncValue(:final value?) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                0,
                GhinaSpace.page,
                GhinaSpace.xxxl,
              ),
              sliver: SliverList.separated(
                itemCount: value.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: GhinaSpace.sm),
                itemBuilder: (context, i) => _NotificationRow(
                  item: value[i],
                  onTap: () => _openActions(value[i]),
                ),
              ),
            ),
            AsyncValue(hasError: true) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorRetry(
                onRetry: () =>
                    ref.invalidate(watchCapturedNotificationsProvider(_filter)),
              ),
            ),
            _ => const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: GhinaSpace.page),
              sliver: SliverToBoxAdapter(child: SkeletonList(count: 4)),
            ),
          },
        ],
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.item, required this.onTap});

  final CapturedNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final n = item;
    final currency = ref.watch(currencyProvider);
    final type = n.txType;
    return ChunkyCard(
      key: ValueKey('notif-${n.id}'),
      onTap: onTap,
      onLongPress: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      borderRadius: GhinaRadii.rLg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppInitialAvatar(
            packageName: n.packageName,
            label: n.displayAppName,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.displayAppName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.caption
                            .w(900)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      notificationTimeLabel(n.postedAt),
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                ),
                if (n.title.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                ],
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ],
                if (type != null && n.hasTransaction) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChunkyPill(
                        key: ValueKey('notif-badge-${n.id}'),
                        label: n.amount == null
                            ? type.label
                            : '${type.label} ${context.money(n.amount!, currency: currency)}',
                        color: txTypeSwatch(type),
                        icon: txTypeIcon(type),
                        soft: true,
                        uppercase: false,
                      ),
                    ],
                  ),
                ] else if (n.parseError != null) ...[
                  const SizedBox(height: 8),
                  ChunkyPill(
                    label: 'Rule cocok, tapi ${n.parseError!.toLowerCase()}',
                    color: GhinaColors.orange,
                    icon: Icons.warning_amber_rounded,
                    soft: true,
                    uppercase: false,
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
