import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../notification_log_format.dart';
import '../widgets/listener_status_card.dart';
import '../widgets/log_overview.dart';

/// "Log Notifikasi" (Android): notifications captured from other apps.
///
/// Two views over one filter (search, date range, kind, app): a timeline
/// grouped by day ("Muat lagi" pages past the first rows) and a per-app
/// breakdown whose cards narrow the timeline to one app. The overview card
/// shows totals and a 14-day activity strip (tap a bar = that day). "Export"
/// writes the filtered log as JSON; "Hapus" clears all or one app. Opening it
/// drops reposts logged by older versions. Entries turned into a transaction
/// by a rule get an income/expense badge; any entry can become a new rule.
class NotificationLogPage extends ConsumerStatefulWidget {
  const NotificationLogPage({super.key, this.today});

  /// Fixed "today" for tests.
  final DateTime? today;

  @override
  ConsumerState<NotificationLogPage> createState() =>
      _NotificationLogPageState();
}

enum _View { timeline, apps }

/// Date presets; [custom] = a picked range.
enum _Range {
  all('Semua waktu'),
  today('Hari ini'),
  week('7 hari'),
  month('30 hari'),
  custom('Pilih tanggal');

  const _Range(this.label);
  final String label;
}

class _NotificationLogPageState extends ConsumerState<NotificationLogPage> {
  static const _page = 200;

  final _search = TextEditingController();
  var _filter = const NotificationLogFilter();
  var _range = _Range.all;
  var _view = _View.timeline;
  var _limit = _page;

  DateTime get _today => startOfDay(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    // Reposts logged before the listener detected them; idempotent and cheap.
    ref.read(removeNotificationRepostsProvider)();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(NotificationLogFilter f) => setState(() {
    _filter = f;
    _limit = _page;
  });

  void _setRange(_Range r, {DateTime? from, DateTime? to}) {
    final t = _today;
    final (f, e) = switch (r) {
      _Range.all => (null, null),
      _Range.today => (t, t),
      _Range.week => (t.subtract(const Duration(days: 6)), t),
      _Range.month => (t.subtract(const Duration(days: 29)), t),
      _Range.custom => (from, to),
    };
    _range = r;
    _setFilter(_filter.withRange(f, e));
  }

  Future<void> _pickRange() async {
    final t = _today;
    final from = await showGhinaDatePicker(
      context,
      initial: _filter.from ?? t,
      title: 'Dari tanggal',
      lastDate: t,
      today: t,
    );
    if (from == null || !mounted) return;
    final to = await showGhinaDatePicker(
      context,
      initial: _filter.to != null && !_filter.to!.isBefore(from)
          ? _filter.to!
          : from,
      title: 'Sampai tanggal',
      firstDate: from,
      lastDate: t,
      today: t,
    );
    if (!mounted) return;
    _setRange(
      _Range.custom,
      from: startOfDay(from),
      to: startOfDay(to ?? from),
    );
  }

  void _pickDay(DateTime day) {
    final d = startOfDay(day);
    if (_filter.from == d && _filter.to == d) {
      _setRange(_Range.all); // second tap on the same bar = back to all
    } else if (d == _today) {
      _setRange(_Range.today);
    } else {
      _setRange(_Range.custom, from: d, to: d);
    }
  }

  String get _rangeLabel {
    final f = _filter.from, t = _filter.to;
    if (_range != _Range.custom || f == null) return _range.label;
    final a = Fmt.relativeDay(f, now: _today);
    if (t == null || t == f) return a;
    return '$a – ${Fmt.relativeDay(t, now: _today)}';
  }

  void _showApp(String packageName) {
    _setFilter(_filter.withPackage(packageName));
    setState(() => _view = _View.timeline);
  }

  Future<void> _clear(List<NotificationSource> sources) async {
    final pkg = _filter.packageName;
    final app = sources.where((s) => s.packageName == pkg).firstOrNull;
    final ok = await showChunkyConfirm(
      context,
      title: pkg == null
          ? 'Hapus semua log notifikasi?'
          : 'Hapus log dari ${app?.displayAppName ?? pkg}?',
      message: pkg == null
          ? 'Semua tanggal & aplikasi, bukan cuma yang tampil. '
                'Transaksi yang sudah tercatat tetap aman.'
          : 'Semua tanggal dari aplikasi ini. '
                'Transaksi yang sudah tercatat tetap aman.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(clearCapturedNotificationsProvider)(
      packageName: pkg,
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        _setFilter(_filter.withPackage(null));
        showOkToast(context, '$value notifikasi dihapus');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _export() async {
    final r = await ref.read(exportCapturedNotificationsProvider)(_filter);
    if (!mounted) return;
    switch (r) {
      case Err(:final failure):
        showFailureToast(context, failure);
      case Ok(value: (:final json, :final count)):
        if (count == 0) {
          showErrorToast(context, 'Nggak ada notifikasi buat diekspor');
          return;
        }
        final stamp = DateTime.now()
            .toIso8601String()
            .substring(0, 16)
            .replaceAll(RegExp('[-:]'), '')
            .replaceFirst('T', '-');
        final Uri? saved;
        try {
          saved = await FilePicker.saveFile(
            dialogTitle: 'Simpan log notifikasi',
            fileName: 'ghina-log-notifikasi-$stamp.json',
            bytes: utf8.encode(json),
            mimeType: 'application/json',
          );
        } catch (e) {
          if (mounted) showErrorToast(context, 'Gagal menyimpan file');
          return;
        }
        if (mounted && saved != null) {
          showOkToast(context, '$count notifikasi diekspor');
        }
    }
  }

  Future<void> _openAppActions(NotificationSource s) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: s.displayAppName,
      showClose: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              dense: true,
              leading: const Icon(Icons.view_agenda_rounded),
              title: 'Lihat notifikasinya',
              subtitle: '${Fmt.number(s.count)} sesuai filter',
              showChevron: true,
              onTap: () => Navigator.of(c).pop('show'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              dense: true,
              leading: const Icon(Icons.rule_rounded),
              title: 'Buat rule untuk aplikasi ini',
              showChevron: true,
              onTap: () => Navigator.of(c).pop('rule'),
            ),
          ),
          ChunkyTile(
            dense: true,
            leading: Icon(
              Icons.delete_sweep_rounded,
              color: GhinaColors.red.base,
            ),
            title: 'Hapus log aplikasi ini',
            onTap: () => Navigator.of(c).pop('clear'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'show':
        _showApp(s.packageName);
      case 'rule':
        context.push(
          '/notification-log/rules/new',
          extra: NotificationRuleDraft(
            packageName: s.packageName,
            appName: s.appName,
          ),
        );
      case 'clear':
        _setFilter(_filter.withPackage(s.packageName));
        await _clear([s]);
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
          if (_filter.packageName != n.packageName)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChunkyTile(
                key: const ValueKey('notif-only-app'),
                dense: true,
                leading: const Icon(Icons.filter_alt_rounded),
                title: 'Hanya dari ${n.displayAppName}',
                onTap: () => Navigator.of(c).pop('app'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              dense: true,
              leading: const Icon(Icons.copy_rounded),
              title: 'Salin teks',
              onTap: () => Navigator.of(c).pop('copy'),
            ),
          ),
          ChunkyTile(
            key: const ValueKey('notif-delete-one'),
            dense: true,
            leading: Icon(Icons.delete_rounded, color: GhinaColors.red.base),
            title: 'Hapus notifikasi ini',
            onTap: () => Navigator.of(c).pop('delete'),
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
      case 'app':
        _showApp(n.packageName);
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: [n.title, n.body].join('\n').trim()),
        );
        if (mounted) showOkToast(context, 'Teks disalin');
      case 'delete':
        final r = await ref.read(deleteCapturedNotificationProvider)(n.id);
        if (!mounted) return;
        switch (r) {
          case Ok():
            showOkToast(context, 'Notifikasi dihapus');
          case Err(:final failure):
            showFailureToast(context, failure);
        }
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
    // Apps and the strip ignore the app filter / the date range, so the
    // breakdown and the strip stay useful while one is picked.
    final sources =
        ref.watch(watchNotificationSourcesProvider(_filter)).value ??
        const <NotificationSource>[];
    final strip =
        ref
            .watch(
              watchNotificationDayCountsProvider(_filter.withRange(null, null)),
            )
            .value ??
        const <NotificationDayCount>[];
    final perDay = {
      for (final d
          in ref.watch(watchNotificationDayCountsProvider(_filter)).value ??
              const <NotificationDayCount>[])
        startOfDay(d.day): d.count,
    };
    final pkg = _filter.packageName;
    final selectedApp = sources.where((s) => s.packageName == pkg).firstOrNull;
    final allCount = sources.fold<int>(0, (a, s) => a + s.count);
    final total = pkg == null ? allCount : (selectedApp?.count ?? 0);
    final hasAny = allCount > 0 || _filter.narrows || pkg != null;

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
            key: const ValueKey('notif-export'),
            tooltip: 'Export (sesuai filter)',
            icon: const Icon(Icons.file_download_rounded),
            onPressed: total == 0 ? null : _export,
          ),
          IconButton(
            key: const ValueKey('notif-clear'),
            tooltip: 'Hapus log',
            icon: Icon(Icons.delete_sweep_rounded, color: GhinaColors.red.base),
            onPressed: hasAny ? () => _clear(sources) : null,
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
                  onChanged: (v) => _setFilter(_filter.withSearch(v)),
                  suffix: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _setFilter(_filter.withSearch(null));
                          },
                        ),
                ),
                const SizedBox(height: GhinaSpace.md),
                SingleChildScrollView(
                  key: const ValueKey('notif-range'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final r in _Range.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChunkyChip(
                            key: ValueKey('notif-range-${r.name}'),
                            label: r == _Range.custom && _range == r
                                ? _rangeLabel
                                : r.label,
                            icon: r == _Range.custom
                                ? Icons.calendar_month_rounded
                                : null,
                            selected: _range == r,
                            onTap: () => r == _Range.custom
                                ? _pickRange()
                                : _setRange(r),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: GhinaSpace.sm),
                ChunkyChoiceChips<NotificationLogKind>(
                  key: const ValueKey('notif-kind'),
                  scrollable: true,
                  options: [
                    for (final k in NotificationLogKind.values)
                      ChunkyChoice(
                        value: k,
                        label: k.label,
                        icon: switch (k) {
                          NotificationLogKind.all => null,
                          NotificationLogKind.money => Icons.payments_rounded,
                          NotificationLogKind.transaction =>
                            Icons.receipt_long_rounded,
                        },
                        color: k == NotificationLogKind.all
                            ? GhinaColors.blue
                            : GhinaColors.green,
                      ),
                  ],
                  selected: {_filter.kind},
                  onChanged: (v) => _setFilter(_filter.withKind(v.first)),
                ),
                if (pkg != null) ...[
                  const SizedBox(height: GhinaSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ChunkyChip(
                      key: const ValueKey('notif-app-chip'),
                      label: 'Hanya ${selectedApp?.displayAppName ?? pkg}  ✕',
                      icon: Icons.apps_rounded,
                      color: GhinaColors.purple,
                      selected: true,
                      onTap: () => _setFilter(_filter.withPackage(null)),
                    ),
                  ),
                ],
                const SizedBox(height: GhinaSpace.md),
                LogOverviewCard(
                  total: total,
                  apps: pkg == null ? sources.length : (total > 0 ? 1 : 0),
                  days: strip,
                  from: _filter.from,
                  to: _filter.to,
                  today: _today,
                  onPickDay: _pickDay,
                ),
                const SizedBox(height: GhinaSpace.md),
                ChunkySegmented<_View>(
                  key: const ValueKey('notif-view'),
                  height: 40,
                  segments: const [
                    ChunkySegment(
                      value: _View.timeline,
                      label: 'Timeline',
                      icon: Icons.view_agenda_rounded,
                    ),
                    ChunkySegment(
                      value: _View.apps,
                      label: 'Per aplikasi',
                      icon: Icons.apps_rounded,
                      color: GhinaColors.purple,
                    ),
                  ],
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
                const SizedBox(height: GhinaSpace.xs),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              0,
              GhinaSpace.page,
              GhinaSpace.xxxl,
            ),
            sliver: switch (_view) {
              _View.timeline => _timeline(perDay),
              _View.apps => _apps(sources, allCount),
            },
          ),
        ],
      ),
    );
  }

  Widget _empty() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(top: GhinaSpace.xl),
      child: EmptyState(
        compact: true,
        title: _filter.narrows || _filter.packageName != null
            ? 'Nggak ada yang cocok'
            : 'Belum ada notifikasi',
        message: _filter.narrows || _filter.packageName != null
            ? 'Coba ubah tanggal, jenis, atau kata kuncinya.'
            : 'Nyalakan "Catat notifikasi" di atas, nanti notifikasi baru muncul di sini.',
      ),
    ),
  );

  Widget _apps(List<NotificationSource> sources, int total) {
    if (sources.isEmpty) return _empty();
    return SliverList.separated(
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: GhinaSpace.sm),
      itemBuilder: (context, i) {
        final s = sources[i];
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? GhinaSpace.sm : 0),
          child: LogAppCard(
            source: s,
            total: total,
            onTap: () => _showApp(s.packageName),
            onLongPress: () => _openAppActions(s),
          ),
        );
      },
    );
  }

  Widget _timeline(Map<DateTime, int> perDay) {
    final query = (filter: _filter, limit: _limit);
    final async = ref.watch(watchCapturedNotificationsProvider(query));
    return switch (async) {
      AsyncValue(:final value?) when value.isEmpty => _empty(),
      AsyncValue(:final value?) => _timelineList(value, perDay),
      AsyncValue(hasError: true) => SliverToBoxAdapter(
        child: ErrorRetry(
          onRetry: () =>
              ref.invalidate(watchCapturedNotificationsProvider(query)),
        ),
      ),
      _ => const SliverToBoxAdapter(child: SkeletonList(count: 4)),
    };
  }

  Widget _timelineList(
    List<CapturedNotification> rows,
    Map<DateTime, int> perDay,
  ) {
    // Flatten into day headers + rows.
    final items = <Object>[];
    DateTime? day;
    for (final n in rows) {
      final d = startOfDay(n.postedAt);
      if (d != day) {
        items.add(d);
        day = d;
      }
      items.add(n);
    }
    final more = rows.length >= _limit;
    return SliverList.builder(
      itemCount: items.length + (more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: GhinaSpace.lg),
            child: ChunkyButton(
              key: const ValueKey('notif-more'),
              label: 'Muat lagi',
              icon: Icons.expand_more_rounded,
              variant: ChunkyButtonVariant.outline,
              size: ChunkyButtonSize.medium,
              uppercase: false,
              onPressed: () => setState(() => _limit += _page),
            ),
          );
        }
        final it = items[i];
        if (it is DateTime) {
          return LogDayHeader(day: it, count: perDay[it], today: _today);
        }
        final n = it as CapturedNotification;
        return Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: _NotificationRow(item: n, onTap: () => _openActions(n)),
        );
      },
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
