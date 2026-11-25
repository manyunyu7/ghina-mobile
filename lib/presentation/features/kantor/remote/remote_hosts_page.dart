import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import '../widgets/kantor_wide.dart';
import 'remote_protocol.dart';
import 'remote_session_page.dart';

/// "Remote Mac": the Macs that run ravel-host (`GET /api/remote/hosts`).
/// Tap an online Mac to open a remote-desktop session. Refreshes every 8 s
/// while visible.
class RemoteHostsPage extends ConsumerStatefulWidget {
  const RemoteHostsPage({super.key, this.load});

  /// Override for tests; defaults to `GET /api/remote/hosts`.
  final Future<List<RemoteHost>> Function()? load;

  @override
  ConsumerState<RemoteHostsPage> createState() => _RemoteHostsPageState();
}

class _RemoteHostsPageState extends ConsumerState<RemoteHostsPage>
    with WidgetsBindingObserver {
  List<RemoteHost>? _hosts;
  Object? _error;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _start();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      // a session page on top owns the screen; skip polling meanwhile
      if (ModalRoute.of(context)?.isCurrent ?? true) _load();
    });
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    final load = widget.load;
    if ((api == null && load == null) || _loading) return;
    _loading = true;
    try {
      final hosts = load != null
          ? await load()
          : RemoteHost.listFromJson(await api!.get('/api/remote/hosts'));
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  Future<void> _open(RemoteHost h) async {
    if (!h.online) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${h.name} offline. Nyalakan Mac dan pastikan ravel-host berjalan.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await RemoteSessionPage.open(context, h);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final hosts = _hosts;
    Widget body;
    if (hosts == null && _error != null) {
      body = KantorErrorView(error: _error!, onRetry: _load);
    } else if (hosts == null) {
      body = const KantorLoading(count: 3);
    } else if (hosts.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.desktop_mac_rounded, size: 56, color: g.textMuted),
          const SizedBox(height: GhinaSpace.lg),
          Text(
            'Belum ada Mac terdaftar',
            textAlign: TextAlign.center,
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: GhinaSpace.sm),
          Text(
            'Pasang dan jalankan ravel-host di Mac, lalu Mac akan muncul di sini.',
            textAlign: TextAlign.center,
            style: GhinaType.body.copyWith(color: g.textSecondary),
          ),
        ],
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) {
          final cols = kantorGridColumns(c.maxWidth, minTile: 300, max: 3);
          const pad = EdgeInsets.all(GhinaSpace.lg);
          if (cols == 1) {
            return ListView.separated(
              padding: pad,
              itemCount: hosts.length,
              separatorBuilder: (_, _) => const SizedBox(height: GhinaSpace.md),
              itemBuilder: (_, i) => _HostCard(host: hosts[i], onTap: _open),
            );
          }
          return GridView.builder(
            padding: pad,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: GhinaSpace.md,
              crossAxisSpacing: GhinaSpace.md,
              mainAxisExtent: 132,
            ),
            itemCount: hosts.length,
            itemBuilder: (_, i) => _HostCard(host: hosts[i], onTap: _open),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Remote Mac'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host, required this.onTap});

  final RemoteHost host;
  final ValueChanged<RemoteHost> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final online = host.online;
    final dot = online ? GhinaColors.green.base : g.textMuted;
    final displays = host.displays;
    final screens = displays.isEmpty
        ? null
        : displays.length == 1
        ? displays.first.sizeLabel
        : '${displays.length} layar';
    return Material(
      color: g.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(host),
        child: Container(
          padding: const EdgeInsets.all(GhinaSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: g.border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: online ? GhinaColors.blue.light : g.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.desktop_mac_rounded,
                  color: online ? GhinaColors.blue.base : g.textMuted,
                  size: 28,
                ),
              ),
              const SizedBox(width: GhinaSpace.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            [
                              online
                                  ? (host.busy
                                        ? 'Online · sedang dipakai'
                                        : 'Online')
                                  : 'Offline',
                              ?screens,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (host.version.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ravel-host ${host.version}',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                online ? Icons.chevron_right_rounded : Icons.power_off_rounded,
                color: g.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
