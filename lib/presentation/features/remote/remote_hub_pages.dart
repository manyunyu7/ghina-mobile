import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/datasources/remote/kantor_api.dart';
import '../../design_system/design_system.dart';
import '../kantor/widgets/kantor_wide.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'remote_auth.dart';
import 'remote_hubs.dart';
import 'remote_pairing.dart';

/// Pairing for one hub. Kantor hubs ask with the app's Kantor token; relay
/// hubs first need the relay owner token (`kcowner_…`, printed by the relay
/// CLI), stored per hub, then the same 6-digit code flow.
class RemoteHubPairing extends StatefulWidget {
  const RemoteHubPairing({
    super.key,
    required this.hub,
    required this.store,
    required this.kantorToken,
    required this.onPaired,
    this.notice,
    this.kantor,
  });

  /// The app's Kantor connection, to fetch the relay owner token from
  /// `GET /api/remote/relay-owner` when Kantor offers it.
  final KantorApi? kantor;

  final RemoteHub hub;
  final RemoteHubStore store;

  /// Token of the app's Kantor connection (for kantor hubs).
  final String? kantorToken;
  final ValueChanged<String> onPaired;
  final String? notice;

  @override
  State<RemoteHubPairing> createState() => _RemoteHubPairingState();
}

class _RemoteHubPairingState extends State<RemoteHubPairing> {
  String? _owner;
  bool _loaded = false;
  String? _ownerError;
  final _ownerCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(RemoteHubPairing old) {
    super.didUpdateWidget(old);
    if (old.hub.id != widget.hub.id) {
      _loaded = false;
      _owner = null;
      _init();
    }
  }

  @override
  void dispose() {
    _ownerCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    var owner = widget.hub.kind == RemoteHubKind.kantor
        ? widget.kantorToken
        : await widget.store.ownerToken(widget.hub.id);
    final kantor = widget.kantor;
    if (owner == null &&
        widget.hub.kind == RemoteHubKind.relay &&
        kantor != null) {
      // Kantor may hand out the relay owner token (planned endpoint)
      try {
        owner = await RemoteAuth.relayOwnerFromKantor(kantor, widget.hub.url);
        if (owner != null) {
          await widget.store.setOwnerToken(widget.hub.id, owner);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _owner = owner;
      _loaded = true;
    });
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (t != null) _ownerCtl.text = extractRelayOwnerToken(t) ?? t;
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const RemoteQrScanPage()));
    if (raw == null || !mounted) return;
    final t = extractRelayOwnerToken(raw);
    if (t == null) {
      setState(() => _ownerError = 'QR itu tidak berisi token owner relay.');
      return;
    }
    _ownerCtl.text = t;
    await _saveOwner();
  }

  Future<void> _saveOwner() async {
    final t = extractRelayOwnerToken(_ownerCtl.text.trim()) ?? '';
    if (t.isEmpty) {
      setState(() => _ownerError = 'Token owner relay diawali "kcowner_".');
      return;
    }
    await widget.store.setOwnerToken(widget.hub.id, t);
    if (!mounted) return;
    setState(() {
      _owner = t;
      _ownerError = null;
    });
  }

  Future<void> _ownerRejected() async {
    if (widget.hub.kind != RemoteHubKind.relay) return;
    await widget.store.setOwnerToken(widget.hub.id, null);
    if (!mounted) return;
    setState(() {
      _owner = null;
      _ownerError = 'Relay menolak token owner itu. Masukkan token yang benar.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final owner = _owner;
    if (owner != null && owner.isNotEmpty) {
      return RemotePairingView(
        key: ValueKey(widget.hub.id),
        owner: KantorApi(KantorConfig(baseUrl: widget.hub.url, token: owner)),
        hubName: widget.hub.name,
        notice: widget.notice,
        onPaired: widget.onPaired,
        onOwnerRejected: _ownerRejected,
      );
    }
    final g = context.ghina;
    return ListView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        KantorReadable(
          maxWidth: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: GhinaSpace.lg),
              Icon(Icons.vpn_key_rounded, size: 56, color: g.textMuted),
              const SizedBox(height: GhinaSpace.lg),
              Text(
                widget.hub.kind == RemoteHubKind.relay
                    ? 'Token owner relay ${widget.hub.name}'
                    : 'Kantor belum tersambung',
                textAlign: TextAlign.center,
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
              const SizedBox(height: GhinaSpace.sm),
              Text(
                widget.hub.kind == RemoteHubKind.relay
                    ? 'Sekali per HP: tempel atau pindai QR token owner dari '
                          'relay (`ravel-relay owner add`). Token ini hanya '
                          'dipakai untuk meminta pairing dan disimpan aman di HP.'
                    : 'Isi token Kantor di Pengaturan Kantor dulu.',
                textAlign: TextAlign.center,
                style: GhinaType.body.copyWith(color: g.textSecondary),
              ),
              if (widget.hub.kind == RemoteHubKind.relay) ...[
                const SizedBox(height: GhinaSpace.xl),
                TextField(
                  controller: _ownerCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Token owner (kcowner_…)',
                    errorText: _ownerError,
                    suffixIcon: IconButton(
                      tooltip: 'Tempel',
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: _paste,
                    ),
                  ),
                  onSubmitted: (_) => _saveOwner(),
                ),
                const SizedBox(height: GhinaSpace.md),
                FilledButton(
                  onPressed: _saveOwner,
                  child: const Text('Lanjut'),
                ),
                const SizedBox(height: GhinaSpace.sm),
                OutlinedButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Pindai QR'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Status of a hub as seen by the Mac list.
enum RemoteHubState { paired, needsPairing, unreachable }

/// Bottom sheet listing hubs: status, pair/re-pair, devices, edit, delete,
/// add. Returns after any change (the caller reloads).
Future<void> showRemoteHubsSheet(
  BuildContext context, {
  required RemoteHubStore store,
  required Map<String, RemoteHubState> states,
  required void Function(RemoteHub hub) onPair,
  required void Function(RemoteHub hub) onDevices,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _HubsSheet(
    store: store,
    states: states,
    onPair: onPair,
    onDevices: onDevices,
  ),
);

class _HubsSheet extends StatefulWidget {
  const _HubsSheet({
    required this.store,
    required this.states,
    required this.onPair,
    required this.onDevices,
  });

  final RemoteHubStore store;
  final Map<String, RemoteHubState> states;
  final void Function(RemoteHub hub) onPair;
  final void Function(RemoteHub hub) onDevices;

  @override
  State<_HubsSheet> createState() => _HubsSheetState();
}

class _HubsSheetState extends State<_HubsSheet> {
  List<RemoteHub>? _hubs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await widget.store.hubs();
    if (mounted) setState(() => _hubs = h);
  }

  Future<void> _edit([RemoteHub? hub]) async {
    final out = await showDialog<RemoteHub>(
      context: context,
      builder: (_) => _HubDialog(hub: hub),
    );
    if (out == null) return;
    await widget.store.upsert(out);
    await _load();
  }

  Future<void> _delete(RemoteHub hub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hapus hub "${hub.name}"?'),
        content: const Text(
          'Token perangkat untuk hub ini dihapus dari HP. Perangkat tetap '
          'terdaftar di hub sampai dicabut dari sana.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.remove(hub.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final hubs = _hubs;
    final g = context.ghina;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Hub signaling', style: GhinaType.h3),
            const SizedBox(height: 4),
            Text(
              'Dicoba berurutan: yang terakhir berhasil dulu, lalu urutan ini. '
              'Tiap hub punya pairing sendiri.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
            if (hubs == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final h in hubs ?? const <RemoteHub>[])
              _hubTile(h, widget.states[h.id]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah hub'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hubTile(RemoteHub h, RemoteHubState? state) {
    final (label, color) = switch (state) {
      RemoteHubState.paired => ('Terpasang', GhinaColors.green.base),
      RemoteHubState.needsPairing => ('Perlu pairing', GhinaColors.orange.base),
      RemoteHubState.unreachable => ('Tidak terjangkau', GhinaColors.gray.base),
      null => ('Perlu pairing', GhinaColors.orange.base),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        h.kind == RemoteHubKind.relay ? Icons.cloud_rounded : Icons.business,
      ),
      title: Text(h.name),
      subtitle: Text(
        '${h.kind == RemoteHubKind.relay ? 'Relay' : 'Kantor'} · ${h.url}\n$label',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color),
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'pair':
              Navigator.pop(context);
              widget.onPair(h);
            case 'devices':
              Navigator.pop(context);
              widget.onDevices(h);
            case 'edit':
              _edit(h);
            case 'delete':
              _delete(h);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'pair',
            child: Text(
              state == RemoteHubState.paired ? 'Pasangkan ulang' : 'Pasangkan',
            ),
          ),
          if (state == RemoteHubState.paired)
            const PopupMenuItem(value: 'devices', child: Text('Perangkat')),
          const PopupMenuItem(value: 'edit', child: Text('Ubah')),
          const PopupMenuItem(value: 'delete', child: Text('Hapus')),
        ],
      ),
    );
  }
}

class _HubDialog extends StatefulWidget {
  const _HubDialog({this.hub});
  final RemoteHub? hub;

  @override
  State<_HubDialog> createState() => _HubDialogState();
}

class _HubDialogState extends State<_HubDialog> {
  late final _name = TextEditingController(text: widget.hub?.name ?? '');
  late final _url = TextEditingController(text: widget.hub?.url ?? 'https://');
  late RemoteHubKind _kind = widget.hub?.kind ?? RemoteHubKind.relay;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final url = RemoteHubStore.parseUrl(_url.text);
    if (url == null) {
      setState(() => _error = 'Alamat harus http:// atau https://');
      return;
    }
    final name = _name.text.trim().isEmpty ? Uri.parse(url).host : _name.text;
    Navigator.pop(
      context,
      widget.hub?.copyWith(name: name.trim(), url: url, kind: _kind) ??
          RemoteHub(
            id: RemoteHubStore.newId(),
            name: name.trim(),
            url: url,
            kind: _kind,
          ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.hub == null ? 'Tambah hub' : 'Ubah hub'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<RemoteHubKind>(
            segments: const [
              ButtonSegment(
                value: RemoteHubKind.kantor,
                label: Text('Kantor'),
                icon: Icon(Icons.business),
              ),
              ButtonSegment(
                value: RemoteHubKind.relay,
                label: Text('Relay'),
                icon: Icon(Icons.cloud_rounded),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nama'),
          ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Alamat', errorText: _error),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Simpan')),
    ],
  );
}

/// Full-screen QR scanner; pops with the first code's text.
class RemoteQrScanPage extends StatefulWidget {
  const RemoteQrScanPage({super.key});

  @override
  State<RemoteQrScanPage> createState() => _RemoteQrScanPageState();
}

class _RemoteQrScanPageState extends State<RemoteQrScanPage> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Pindai QR token owner'),
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _ctl,
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && v.isNotEmpty) {
                _done = true;
                Navigator.of(context).pop(v);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Kamera tidak bisa dipakai (${error.errorCode.name}). '
                'Beri izin kamera untuk Ravel, atau tempel tokennya.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        const Align(
          alignment: Alignment(0, 0.8),
          child: Text(
            'Arahkan ke QR dari `ravel-relay owner add`',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    ),
  );
}
