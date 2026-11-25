import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/kantor_providers.dart';
import '../../design_system/design_system.dart';
import '../kantor/widgets/kantor_states.dart';
import '../kantor/widgets/kantor_wide.dart';
import 'remote_auth.dart';
import 'remote_hub_pages.dart';
import 'remote_pairing.dart';
import 'remote_hubs.dart';
import 'remote_protocol.dart';
import 'remote_security.dart';
import 'remote_session_page.dart';

/// "Remote Mac": the Macs that run ravel-host (`GET /api/remote/hosts`).
/// Tap an online Mac to open a remote-desktop session. Hosts come from every
/// paired hub (kantor-claude and/or relays; each hub has its own pairing)
/// and are merged by machine id. Live via `remote-hosts` on the Kantor `/ws`,
/// plus a poll every 15 s while visible.
class RemoteHostsPage extends ConsumerStatefulWidget {
  const RemoteHostsPage({super.key, this.load, this.lock, this.hubStore});

  /// Override for tests; defaults to `GET /api/remote/hosts`.
  final Future<List<RemoteHost>> Function()? load;

  /// Biometric gate before a session (override for tests).
  final RemoteLock? lock;

  /// Hub list and per-hub tokens (override for tests).
  final RemoteHubStore? hubStore;

  @override
  ConsumerState<RemoteHostsPage> createState() => _RemoteHostsPageState();
}

class _RemoteHostsPageState extends ConsumerState<RemoteHostsPage>
    with WidgetsBindingObserver {
  late final RemoteLock _lock = widget.lock ?? RemoteLock();
  late final RemoteHubStore _hubStore = widget.hubStore ?? RemoteHubStore();
  RemoteLockPolicy _policy = RemoteLockPolicy.everySession;
  Timer? _timer;
  bool _loading = false;
  bool _ready = false;
  Object? _error;

  /// Every hub in list order, with its device token (null = not paired).
  List<RemoteHub> _hubs = const [];
  final Map<String, String?> _tokens = {};
  final Map<String, RemoteHubState> _states = {};

  /// Last host list per hub (live events replace one hub's part).
  final Map<String, List<RemoteHost>> _perHub = {};
  List<RemoteHostEntry>? _entries;
  List<RemotePendingPair> _pending = const [];

  /// Hub whose pairing screen is shown (none paired yet, or chosen).
  RemoteHub? _pairing;
  String? _pairNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
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

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ModalRoute.of(context)?.isCurrent ?? true) _load();
    });
  }

  bool get _fake => widget.load != null;
  Iterable<RemoteHub> get _paired => _hubs.where((h) => _tokens[h.id] != null);

  Future<void> _init() async {
    await _reloadHubs();
    if (!mounted) return;
    setState(() => _ready = true);
    _load();
  }

  Future<void> _reloadHubs() async {
    if (_fake) return;
    final owner = ref.read(kantorApiProvider);
    final hubs = await _hubStore.hubs(kantorUrl: owner?.config.baseUrl);
    final tokens = <String, String?>{
      for (final h in hubs) h.id: await _hubStore.viewerToken(h.id),
    };
    if (!mounted) return;
    setState(() {
      _hubs = hubs;
      _tokens
        ..clear()
        ..addAll(tokens);
      _states.removeWhere((id, _) => !tokens.containsKey(id));
      for (final h in hubs) {
        if (tokens[h.id] == null) {
          _states[h.id] = RemoteHubState.needsPairing;
        } else {
          _states.putIfAbsent(h.id, () => RemoteHubState.paired);
        }
        _perHub.removeWhere((id, _) => !tokens.containsKey(id));
      }
      if (_paired.isEmpty) {
        _pairing ??= hubs.isEmpty ? null : hubs.first;
      }
    });
  }

  /// Viewer client over paired hubs: last working first, then list order.
  Future<RemoteHubClient?> _client() async {
    final order = RemoteHubStore.tryOrder(
      _paired.toList(),
      await _hubStore.lastWorking(),
    );
    if (order.isEmpty) return null;
    return RemoteHubClient(
      [for (final h in order) RemoteHubConn(h, _tokens[h.id]!)],
      onWorking: (h) => _hubStore.rememberWorking(h.id),
      onUnauthorized: _markNeedsPairing,
    );
  }

  /// A hub refused this device's token (401/403): forget it there, keep
  /// using the other hubs.
  Future<void> _markNeedsPairing(RemoteHub hub) async {
    await _hubStore.setViewerToken(hub.id, null);
    if (!mounted) return;
    setState(() {
      _tokens[hub.id] = null;
      _states[hub.id] = RemoteHubState.needsPairing;
      _perHub.remove(hub.id);
      if (_paired.isEmpty) {
        _pairing = hub;
        _pairNotice =
            'Izin perangkat ini di ${hub.name} sudah dicabut atau tidak berlaku. Pasangkan ulang.';
      }
    });
  }

  Future<void> _load() async {
    if (_loading || !_ready) return;
    _loading = true;
    try {
      if (_fake) {
        final hosts = await widget.load!();
        if (!mounted) return;
        const hub = RemoteHub(
          id: 'test',
          name: 'Test',
          url: 'http://test',
          kind: RemoteHubKind.kantor,
        );
        setState(() {
          _perHub['test'] = hosts;
          _entries = mergeHosts([(hub, hosts)]);
          _error = null;
        });
        return;
      }
      final paired = _paired.toList();
      if (paired.isEmpty) return;
      // every paired hub in parallel; one hub down does not hide the others
      final results = await Future.wait([for (final h in paired) _fetchHub(h)]);
      if (!mounted) return;
      Object? firstError;
      setState(() {
        for (var k = 0; k < paired.length; k++) {
          final (hosts, err) = results[k];
          final h = paired[k];
          if (hosts != null) {
            _perHub[h.id] = hosts;
            _states[h.id] = RemoteHubState.paired;
          } else if (_tokens[h.id] != null) {
            _states[h.id] = RemoteHubState.unreachable;
            firstError ??= err;
          }
        }
        _remerge();
        _error = _entries == null || _entries!.isEmpty && firstError != null
            ? firstError
            : null;
      });
      final client = await _client();
      if (client != null) {
        final pending = await client
            .run(RemoteAuth.pending)
            .catchError((_) => const <RemotePendingPair>[]);
        if (mounted) setState(() => _pending = pending);
      }
    } finally {
      _loading = false;
    }
  }

  Future<(List<RemoteHost>?, Object?)> _fetchHub(RemoteHub h) async {
    final token = _tokens[h.id];
    if (token == null) return (null, null);
    try {
      final api = RemoteHubConn(h, token).api;
      return (
        RemoteHost.listFromJson(await api.get('/api/remote/hosts')),
        null,
      );
    } on KantorException catch (e) {
      if (e.kind == KantorFailure.unauthorized) await _markNeedsPairing(h);
      return (null, e);
    } catch (e) {
      return (null, e);
    }
  }

  void _remerge() {
    final parts = <(RemoteHub, List<RemoteHost>)>[
      for (final h in _hubs)
        if (_perHub[h.id] != null) (h, _perHub[h.id]!),
    ];
    _entries = parts.isEmpty && _entries == null ? null : mergeHosts(parts);
  }

  Future<void> _onPaired(RemoteHub hub, String token) async {
    await _hubStore.setViewerToken(hub.id, token);
    await _hubStore.rememberWorking(hub.id);
    if (!mounted) return;
    setState(() {
      _pairing = null;
      _pairNotice = null;
      _tokens[hub.id] = token;
      _states[hub.id] = RemoteHubState.paired;
    });
    _load();
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
    if (unlocked == RemoteUnlock.okWithoutLock &&
        await _lock.shouldWarnNoLock()) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.no_encryption_gmailerrorred_rounded),
          title: const Text('HP ini tanpa kunci layar'),
          content: const Text(
            'Remote Mac tidak bisa meminta sidik jari atau PIN karena HP ini '
            'belum punya kunci layar. Siapa pun yang memegang HP ini bisa '
            'membuka Mac-mu. Pasang kunci layar di Pengaturan Android supaya '
            'sesi remote terlindungi. Peringatan ini hanya muncul sekali.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    if (unlocked != RemoteUnlock.ok && unlocked != RemoteUnlock.okWithoutLock) {
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
    final entry = _entries?.firstWhere(
      (e) => e.host.machine == h.machine,
      orElse: () => RemoteHostEntry(h, const []),
    );
    final client = await _client();
    if (!mounted) return;
    await RemoteSessionPage.open(
      context,
      h,
      hubs: client?.only(entry?.hubIds ?? const []),
    );
    if (mounted) {
      await _reloadHubs();
      _load();
    }
  }

  Future<void> _devices([RemoteHub? hub]) async {
    final client = await _client();
    if (client == null || !mounted) return;
    final c = hub == null ? client : client.only([hub.id]);
    await showRemoteDevicesSheet(
      context,
      viewer: c,
      onRevokedSelf: () => _markNeedsPairing(c.current.hub),
    );
    _load();
  }

  Future<void> _manageHubs() async {
    await showRemoteHubsSheet(
      context,
      store: _hubStore,
      states: Map.of(_states),
      onPair: (h) => setState(() {
        _pairing = h;
        _pairNotice = null;
      }),
      onDevices: _devices,
    );
    await _reloadHubs();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final owner = ref.watch(kantorApiProvider);
    // live updates from kantor-claude: {t:'remote-hosts', hosts:[…]} on /ws
    // (only for the kantor hub at the app's Kantor address)
    ref.listen(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e == null || e['t'] != 'remote-hosts' || e['hosts'] is! List) return;
      final url = owner == null
          ? null
          : RemoteHubStore.parseUrl(owner.config.baseUrl);
      final hub = _paired.where(
        (h) => h.kind == RemoteHubKind.kantor && h.url == url,
      );
      if (hub.isEmpty) return;
      setState(() {
        _perHub[hub.first.id] = RemoteHost.listFromJson(e['hosts']);
        _remerge();
      });
    });
    final entries = _entries;
    final pairing = _pairing;
    final anyPaired = _fake || _paired.isNotEmpty;
    final needPair = _hubs
        .where((h) => _states[h.id] == RemoteHubState.needsPairing)
        .toList();
    Widget body;
    if (!_ready) {
      body = const KantorLoading(count: 3);
    } else if (pairing != null) {
      body = RemoteHubPairing(
        hub: pairing,
        store: _hubStore,
        kantorToken: owner?.config.token,
        kantor: owner,
        notice: _pairNotice,
        onPaired: (t) => _onPaired(pairing, t),
      );
    } else if (!anyPaired) {
      body = _hubs.isEmpty
          ? const KantorErrorView(
              error: KantorException(
                KantorFailure.unauthorized,
                'Token Kantor belum diisi.',
              ),
            )
          : const SizedBox.shrink();
    } else if (entries == null && _error != null) {
      body = KantorErrorView(error: _error!, onRetry: _load);
    } else if (entries == null) {
      body = const KantorLoading(count: 3);
    } else if (entries.isEmpty) {
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
      final hosts = [for (final e in entries) e.host];
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
        leading: pairing != null && _paired.isNotEmpty
            ? IconButton(
                tooltip: 'Kembali ke daftar Mac',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _pairing = null),
              )
            : null,
        title: const Text('Remote Mac'),
        actions: [
          if (anyPaired && pairing == null) ...[
            IconButton(
              tooltip: 'Perangkat terpasang',
              icon: Badge(
                isLabelVisible: _pending.isNotEmpty,
                label: Text('${_pending.length}'),
                child: const Icon(Icons.devices_rounded),
              ),
              onPressed: _fake ? null : () => _devices(),
            ),
            IconButton(
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
          ],
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
          if (!_fake)
            IconButton(
              tooltip: 'Hub signaling',
              icon: Badge(
                isLabelVisible: needPair.isNotEmpty,
                label: Text('${needPair.length}'),
                child: const Icon(Icons.hub_rounded),
              ),
              onPressed: _manageHubs,
            ),
        ],
      ),
      body: Column(
        children: [
          if (pairing == null && anyPaired && needPair.isNotEmpty)
            MaterialBanner(
              content: Text(
                needPair.length == 1
                    ? 'Hub "${needPair.first.name}" perlu dipasangkan.'
                    : '${needPair.length} hub perlu dipasangkan.',
              ),
              leading: const Icon(Icons.link_off_rounded),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _pairing = needPair.first),
                  child: const Text('Pasangkan'),
                ),
              ],
            ),
          if (pairing == null && _pending.isNotEmpty)
            MaterialBanner(
              content: Text(
                _pending.length == 1
                    ? '"${_pending.first.device}" minta izin membuka Remote Mac.'
                    : '${_pending.length} perangkat minta izin membuka Remote Mac.',
              ),
              leading: const Icon(Icons.phonelink_ring_rounded),
              actions: [
                TextButton(
                  onPressed: () => _devices(),
                  child: const Text('Tinjau'),
                ),
              ],
            ),
          Expanded(
            child: anyPaired && pairing == null
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
