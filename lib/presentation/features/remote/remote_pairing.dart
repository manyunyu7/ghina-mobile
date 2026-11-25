import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/datasources/remote/kantor_api.dart';
import '../../design_system/design_system.dart';
import '../kantor/widgets/kantor_wide.dart';
import 'remote_auth.dart';

/// Default name this phone/tablet asks to be paired as.
String remoteDefaultDeviceName() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final shortest =
      math.min(view.physicalSize.width, view.physicalSize.height) /
      view.devicePixelRatio;
  return shortest >= 600 ? 'Ravel tablet' : 'Ravel HP';
}

/// "Pasangkan perangkat ini": asks Kantor for a pairing, then takes the
/// 6-digit code shown on the Mac (or waits for approval from another paired
/// device). Calls [onPaired] with the viewer token.
class RemotePairingView extends StatefulWidget {
  const RemotePairingView({
    super.key,
    required this.owner,
    required this.onPaired,
    this.notice,
  });

  final KantorApi owner;
  final ValueChanged<String> onPaired;

  /// Why pairing is shown again (e.g. the old token was revoked).
  final String? notice;

  @override
  State<RemotePairingView> createState() => _RemotePairingViewState();
}

class _RemotePairingViewState extends State<RemotePairingView> {
  final _name = TextEditingController(text: remoteDefaultDeviceName());
  final _code = TextEditingController();
  RemotePairRequest? _req;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  Timer? _tick;

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final req = await RemoteAuth.requestPair(
        widget.owner,
        _name.text.trim().isEmpty ? remoteDefaultDeviceName() : _name.text,
      );
      if (!mounted) return;
      setState(() {
        _req = req;
        _code.clear();
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _claim());
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_req != null && DateTime.now().isAfter(_req!.expiresAt)) {
          _poll?.cancel();
          _tick?.cancel();
          setState(() {
            _req = null;
            _error = 'Permintaan kedaluwarsa. Minta ulang.';
          });
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim() async {
    final req = _req;
    if (req == null || _busy) return;
    try {
      final token = await RemoteAuth.claim(widget.owner, req);
      if (token != null && mounted) _done(token);
    } on KantorException catch (e) {
      if (e.kind == KantorFailure.notFound && mounted) {
        _poll?.cancel();
        setState(() {
          _req = null;
          _error = e.message;
        });
      }
    } catch (_) {}
  }

  Future<void> _approve() async {
    final req = _req;
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (req == null || code.length != 6) {
      setState(() => _error = 'Kode terdiri dari 6 angka.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await RemoteAuth.approveWithCode(widget.owner, req, code);
      if (mounted) _done(token);
    } catch (e) {
      if (!mounted) return;
      final msg = _message(e);
      setState(() {
        _error = msg;
        // too many wrong codes or expired: start over
        if (msg.contains('ulang') || msg.contains('kedaluwarsa')) _req = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done(String token) {
    _poll?.cancel();
    _tick?.cancel();
    HapticFeedback.mediumImpact();
    widget.onPaired(token);
  }

  static String _message(Object e) {
    if (e is KantorException) {
      if (e.kind == KantorFailure.unauthorized &&
          e.message.contains('pairing')) {
        return 'Hanya token pemilik Kantor yang boleh meminta pairing.';
      }
      return e.message;
    }
    return '$e';
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final req = _req;
    final left = req?.expiresAt.difference(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        KantorReadable(
          maxWidth: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: GhinaSpace.lg),
              Icon(Icons.phonelink_lock_rounded, size: 56, color: g.textMuted),
              const SizedBox(height: GhinaSpace.lg),
              Text(
                'Pasangkan perangkat ini',
                textAlign: TextAlign.center,
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
              const SizedBox(height: GhinaSpace.sm),
              Text(
                'Remote Mac butuh izin khusus per perangkat. Setelah diminta, '
                'Mac yang online menampilkan kode 6 angka. Ketik kodenya di sini, '
                'atau setujui dari perangkat lain yang sudah terpasang.',
                textAlign: TextAlign.center,
                style: GhinaType.body.copyWith(color: g.textSecondary),
              ),
              if (widget.notice != null) ...[
                const SizedBox(height: GhinaSpace.md),
                Text(
                  widget.notice!,
                  textAlign: TextAlign.center,
                  style: GhinaType.bodyS.copyWith(
                    color: GhinaColors.orange.edge,
                  ),
                ),
              ],
              const SizedBox(height: GhinaSpace.xl),
              if (req == null) ...[
                TextField(
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nama perangkat',
                    helperText: 'Tampil di Mac saat tersambung',
                  ),
                ),
                const SizedBox(height: GhinaSpace.md),
                FilledButton.icon(
                  onPressed: _busy ? null : _request,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(_busy ? 'Meminta…' : 'Minta pairing'),
                ),
              ] else ...[
                Text(
                  req.hostsNotified > 0
                      ? 'Kode dikirim ke ${req.hostsNotified} Mac. Lihat notifikasi ravel-host.'
                      : 'Tidak ada Mac online yang bisa menampilkan kode. '
                            'Setujui dari perangkat lain yang sudah terpasang, '
                            'atau nyalakan ravel-host lalu minta ulang.',
                  textAlign: TextAlign.center,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: GhinaSpace.md),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GhinaType.h2.copyWith(letterSpacing: 8),
                  decoration: const InputDecoration(
                    hintText: '000000',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _approve(),
                ),
                const SizedBox(height: GhinaSpace.md),
                FilledButton(
                  onPressed: _busy ? null : _approve,
                  child: Text(_busy ? 'Memeriksa…' : 'Pasangkan'),
                ),
                const SizedBox(height: GhinaSpace.sm),
                Text(
                  left == null || left.isNegative
                      ? ''
                      : 'Berlaku ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')} lagi',
                  textAlign: TextAlign.center,
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
                TextButton(
                  onPressed: _busy ? null : _request,
                  child: const Text('Minta kode baru'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: GhinaSpace.md),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet: paired devices (revoke) and requests waiting for approval.
Future<void> showRemoteDevicesSheet(
  BuildContext context, {
  required KantorApi viewer,
  required VoidCallback onRevokedSelf,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _DevicesSheet(viewer: viewer, onRevokedSelf: onRevokedSelf),
);

class _DevicesSheet extends StatefulWidget {
  const _DevicesSheet({required this.viewer, required this.onRevokedSelf});

  final KantorApi viewer;
  final VoidCallback onRevokedSelf;

  @override
  State<_DevicesSheet> createState() => _DevicesSheetState();
}

class _DevicesSheetState extends State<_DevicesSheet> {
  List<RemoteDevice>? _devices;
  List<RemotePendingPair> _pending = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await RemoteAuth.devices(widget.viewer);
      final p = await RemoteAuth.pending(widget.viewer);
      if (mounted) {
        setState(() {
          _devices = d;
          _pending = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _revoke(RemoteDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cabut "${d.device}"?'),
        content: Text(
          d.current
              ? 'Ini perangkat yang sedang kamu pakai. Remote Mac perlu dipasangkan ulang.'
              : 'Perangkat itu tidak bisa membuka Remote Mac lagi, sesi aktifnya diputus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cabut'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RemoteAuth.revoke(widget.viewer, d.id);
      if (d.current) {
        if (mounted) Navigator.pop(context);
        widget.onRevokedSelf();
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _approve(RemotePendingPair p) async {
    try {
      await RemoteAuth.approveOther(widget.viewer, p.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final devices = _devices;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (_pending.isNotEmpty) ...[
              Text('Menunggu persetujuan', style: GhinaType.h3),
              for (final p in _pending)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phonelink_ring_rounded),
                  title: Text(p.device),
                  subtitle: p.ip == null ? null : Text(p.ip!),
                  trailing: FilledButton(
                    onPressed: () => _approve(p),
                    child: const Text('Setujui'),
                  ),
                ),
              const Divider(),
            ],
            Text('Perangkat terpasang', style: GhinaType.h3),
            if (devices == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final d in devices ?? const <RemoteDevice>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  d.current ? Icons.smartphone_rounded : Icons.devices_rounded,
                ),
                title: Text(d.current ? '${d.device} (ini)' : d.device),
                subtitle: Text(
                  [
                    if (d.lastUsed != null)
                      'Terakhir ${MaterialLocalizations.of(context).formatShortDate(d.lastUsed!)}',
                    if (d.via != null) 'lewat ${d.via}',
                  ].join(' · '),
                  style: TextStyle(color: g.textSecondary),
                ),
                trailing: IconButton(
                  tooltip: 'Cabut',
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: () => _revoke(d),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: GhinaColors.red.base),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
