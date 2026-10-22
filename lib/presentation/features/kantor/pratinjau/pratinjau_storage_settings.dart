import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';

/// "Penyimpanan pratinjau" in the daemon settings: usage per office, the
/// auto-cleanup days (`/api/pratinjau/storage`) and a manual cleanup with a
/// dry run first (`/api/pratinjau/cleanup`).
class PratinjauStorageSettings extends ConsumerStatefulWidget {
  const PratinjauStorageSettings({super.key});

  @override
  ConsumerState<PratinjauStorageSettings> createState() => _State();
}

String _mb(num b) => '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
int _n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class _State extends ConsumerState<PratinjauStorageSettings> {
  final _days = TextEditingController();
  Map<String, dynamic>? _data;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  void _apply(Object? j) {
    final m = j is Map ? j.cast<String, dynamic>() : <String, dynamic>{};
    setState(() {
      _data = m;
      _error = null;
      _days.text = '${_n(m['cleanupDays'])}';
    });
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final j = await api.get('/api/pratinjau/storage');
      if (mounted) _apply(j);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _saveDays() async {
    final api = ref.read(kantorApiProvider);
    final d = int.tryParse(_days.text.trim());
    if (api == null || d == null || d < 0 || _busy) return;
    setState(() => _busy = true);
    await kantorGuard(context, () async {
      final j = await api.put('/api/pratinjau/storage', {'cleanupDays': d});
      if (mounted) _apply(j);
      if (mounted) {
        kantorToast(
          context,
          d == 0 ? 'Pembersihan otomatis dimatikan' : 'Disimpan: $d hari',
        );
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cleanup() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _busy) return;
    setState(() => _busy = true);
    Map<String, dynamic>? dry;
    await kantorGuard(context, () async {
      final j = await api.post('/api/pratinjau/cleanup', {'dryRun': true});
      dry = j is Map ? j.cast<String, dynamic>() : null;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    final r = dry;
    if (r == null) return;
    final items = r['items'] is List ? r['items'] as List : const [];
    if (items.isEmpty) {
      kantorToast(context, 'Tidak ada pratinjau yang bisa dibersihkan');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bersihkan pratinjau'),
        content: Text(
          'Bersihkan ${items.length} pratinjau, hemat ${_mb(_n(r['bytes']))}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await kantorGuard(context, () async {
      await api.post('/api/pratinjau/cleanup', {'dryRun': false});
      ref.invalidate(kantorPratinjauFeedProvider);
      ref.invalidate(kantorPratinjauSessionProvider);
      ref.invalidate(kantorPratinjauUsageProvider);
      if (mounted) kantorToast(context, '${items.length} pratinjau dibersihkan');
    });
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final d = _data;
    final offices = d?['offices'] is List
        ? [
            for (final o in d!['offices'] as List)
              if (o is Map) o,
          ]
        : const <Map>[];
    final days = int.tryParse(_days.text.trim()) ?? _n(d?['cleanupDays']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Penyimpanan pratinjau'),
        if (d == null)
          Text(
            _error == null ? 'Memuat…' : 'Tidak tersedia di daemon ini.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          )
        else ...[
          Text(
            'Berkas pratinjau yang sudah selesai (disetujui/dipilih/diarsip, '
            'atau info yang sudah dilihat) dibersihkan otomatis setelah '
            '${days <= 0 ? 'N' : days} hari. Yang 📌 disimpan, baru, revisi, '
            'ditunda, atau sudah jadi wiki tidak disentuh.',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.sm),
          for (final o in offices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${o['name'] ?? o['id']}: ${_mb(_n(o['bytes']))} · '
                '${_n(o['items'])} pratinjau · ${_n(o['files'])} file',
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            label: 'Bersihkan otomatis setelah (hari, 0 = mati)',
            controller: _days,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: 'Simpan',
            variant: ChunkyButtonVariant.outline,
            loading: _busy,
            onPressed: _busy ? null : _saveDays,
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: 'Bersihkan sekarang',
            icon: Icons.cleaning_services_rounded,
            variant: ChunkyButtonVariant.secondary,
            onPressed: _busy ? null : _cleanup,
          ),
        ],
      ],
    );
  }
}
