import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/kantor_providers.dart';
import '../../design_system/design_system.dart';
import '../kantor/widgets/kantor_states.dart';
import '../kantor/widgets/kantor_wide.dart';
import 'remote_auth.dart';
import 'remote_pairing.dart';
import 'remote_hubs.dart';
import 'remote_protocol.dart';
import 'remote_security.dart';
import 'remote_session_page.dart';

/// "Remote Mac": the Macs that run ravel-host (`GET /api/remote/hosts`).
/// Tap an online Mac to open a remote-desktop session. Live via the
/// `remote-hosts` event on `/ws`, plus a poll every 15 s while visible.
class RemoteHostsPage extends ConsumerStatefulWidget {
  const RemoteHostsPage({super.key, this.load, this.lock});

  /// Override for tests; defaults to `GET /api/remote/hosts`.
  final Future<List<RemoteHost>> Function()? load;

  /// Biometric gate before a session (override for tests).
  final RemoteLock? lock;

  @override
  ConsumerState<RemoteHostsPage> createState() => _RemoteHostsPageState();
}

class _RemoteHostsPageState extends ConsumerState<RemoteHostsPage>
    with WidgetsBindingObserver {
  final _store = RemoteDeviceStore();
  late final RemoteLock _lock = widget.lock ?? RemoteLock();
  RemoteLockPolicy _policy = RemoteLockPolicy.everySession;
  List<RemoteHost>? _hosts;
  List<RemotePendingPair> _pending = const [];
  Object? _error;
  Timer? _timer;
  bool _loading = false;

  /// This device's viewer client (`kcview_` token), null until paired.
  RemoteHubClient? _viewer;
  final _hubList = RemoteHubList();
  bool _tokenChecked = false;
  String? _pairNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAuth();
    _start();
    _lock.policy().then((p) {
      if (mounted) setState(() => _policy = p);
    });
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

  Future<void> _initAuth() async {
    final owner = ref.read(kantorApiProvider);
    if (widget.load == null && owner != null) {
      final token = await _store.read(owner.config.baseUrl);
      if (!mounted) return;
      _viewer = token == null ? null : await _hubsFor(owner, token);
      if (!mounted) return;
    }
    setState(() => _tokenChecked = true);
    _load();
  }

  /// Viewer client over every hub address of this Kantor.
  Future<RemoteHubClient> _hubsFor(KantorApi owner, String token) async {
    final primary = owner.config.baseUrl;
    return RemoteHubClient(
      id: RemoteHubList.originOf(primary),
      urls: await _hubList.ordered(primary),
      token: token,
      onWorking: (u) => _hubList.remember(primary, u),
    );
  }

  Future<void> _editHubs() async {
    final owner = ref.read(kantorApiProvider);
    final viewer = _viewer;
    if (owner == null || viewer == null) return;
    final primary = owner.config.baseUrl;
    final ctl = TextEditingController(
      text: (await _hubList.extras(primary)).join('\n'),
    );
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Alamat hub tambahan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Utama: ${RemoteHubList.originOf(primary)}\n'
              'Alamat lain ke Kantor yang sama (satu per baris), dicoba '
              'bergantian kalau yang dipakai tidak terjangkau.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              minLines: 2,
              maxLines: 6,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://hub.example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final lines = ctl.text.split(RegExp(r'[\s,]+'));
    ctl.dispose();
    if (save != true) return;
    final bad = lines.where(
      (l) => l.trim().isNotEmpty && RemoteHubList.parse(l) == null,
    );
    await _hubList.setExtras(primary, lines);
    final hubs = await _hubsFor(owner, viewer.token);
    if (!mounted) return;
    setState(() => _viewer = hubs);
    if (bad.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Diabaikan (bukan http/https): ${bad.join(', ')}'),
        ),
      );
    }
    _load();
  }

  Future<void> _paired(String token) async {
    final owner = ref.read(kantorApiProvider);
    if (owner == null) return;
    await _store.write(owner.config.baseUrl, token);
    final hubs = await _hubsFor(owner, token);
    if (!mounted) return;
    setState(() {
      _viewer = hubs;
      _pairNotice = null;
      _hosts = null;
      _error = null;
    });
    _load();
  }

  Future<void> _unpair(String notice) async {
    final owner = ref.read(kantorApiProvider);
    if (owner != null) await _store.clear(owner.config.baseUrl);
    if (!mounted) return;
    setState(() {
      _viewer = null;
      _hosts = null;
      _pending = const [];
      _pairNotice = notice;
    });
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      // a session page on top owns the screen; skip polling meanwhile
      if (ModalRoute.of(context)?.isCurrent ?? true) _load();
    });
  }

  Future<void> _load() async {
    final load = widget.load;
    final viewer = _viewer;
    if ((viewer == null && load == null) || _loading) return;
    _loading = true;
    try {
      final hosts = load != null
          ? await load()
          : RemoteHost.listFromJson(
              await viewer!.run((a) => a.get('/api/remote/hosts')),
            );
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _error = null;
      });
      if (viewer != null) {
        final pending = await viewer
            .run(RemoteAuth.pending)
            .catchError((_) => const <RemotePendingPair>[]);
        if (mounted) setState(() => _pending = pending);
      }
    } on KantorException catch (e) {
      if (!mounted) return;
      if (e.kind == KantorFailure.unauthorized && load == null) {
        await _unpair(
          'Izin perangkat ini sudah dicabut atau tidak berlaku. Pasangkan ulang.',
        );
      } else {
        setState(() => _error = e);
      }
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
    final unlocked = await _lock.unlock(h.name);
    if (!mounted) return;
    if (unlocked != RemoteUnlock.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(switch (unlocked) {
            RemoteUnlock.lockedOut =>
              'Terlalu banyak percobaan. Coba lagi sebentar lagi.',
            RemoteUnlock.failed => 'Verifikasi gagal.',
            _ => 'Verifikasi dibatalkan.',
          }),
        ),
      );
      return;
    }
    await RemoteSessionPage.open(context, h, hubs: _viewer);
    if (mounted) _load();
  }

  void _devices() {
    final viewer = _viewer;
    if (viewer == null) return;
    showRemoteDevicesSheet(
      context,
      viewer: viewer,
      onRevokedSelf: () => _unpair('Perangkat ini sudah dicabut.'),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final owner = ref.watch(kantorApiProvider);
    // live updates: kantor-claude pushes {t:'remote-hosts', hosts:[…]} on /ws
    ref.listen(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e == null || e['t'] != 'remote-hosts' || e['hosts'] is! List) return;
      if (widget.load != null || _viewer == null) return;
      setState(() => _hosts = RemoteHost.listFromJson(e['hosts']));
    });
    final hosts = _hosts;
    final paired = widget.load != null || _viewer != null;
    Widget body;
    if (!_tokenChecked) {
      body = const KantorLoading(count: 3);
    } else if (!paired && owner == null) {
      body = const KantorErrorView(
        error: KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        ),
      );
    } else if (!paired) {
      body = RemotePairingView(
        owner: owner!,
        onPaired: _paired,
        notice: _pairNotice,
      );
    } else if (hosts == null && _error != null) {
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
          if (paired) ...[
            IconButton(
              tooltip: 'Perangkat terpasang',
              icon: Badge(
                isLabelVisible: _pending.isNotEmpty,
                label: Text('${_pending.length}'),
                child: const Icon(Icons.devices_rounded),
              ),
              onPressed: _viewer == null ? null : _devices,
            ),
            IconButton(
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
            PopupMenuButton<RemoteLockPolicy>(
              tooltip: 'Kunci biometrik',
              icon: const Icon(Icons.fingerprint_rounded),
              onSelected: (p) {
                setState(() => _policy = p);
                _lock.setPolicy(p);
              },
              itemBuilder: (_) => [
                const PopupMenuItem<RemoteLockPolicy>(
                  enabled: false,
                  child: Text('Sidik jari / PIN sebelum sesi'),
                ),
                for (final p in RemoteLockPolicy.values)
                  CheckedPopupMenuItem(
                    value: p,
                    checked: p == _policy,
                    child: Text(p.label),
                  ),
              ],
            ),
            if (_viewer != null)
              IconButton(
                tooltip: 'Alamat hub',
                icon: Badge(
                  isLabelVisible: _viewer!.apis.length > 1,
                  label: Text('${_viewer!.apis.length}'),
                  child: const Icon(Icons.hub_rounded),
                ),
                onPressed: _editHubs,
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_pending.isNotEmpty)
            MaterialBanner(
              content: Text(
                _pending.length == 1
                    ? '"${_pending.first.device}" minta izin membuka Remote Mac.'
                    : '${_pending.length} perangkat minta izin membuka Remote Mac.',
              ),
              leading: const Icon(Icons.phonelink_ring_rounded),
              actions: [
                TextButton(onPressed: _devices, child: const Text('Tinjau')),
              ],
            ),
          Expanded(
            child: paired
                ? RefreshIndicator(onRefresh: _load, child: body)
                : body,
          ),
        ],
      ),
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
