import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../pratinjau/pratinjau_storage_settings.dart';
import '../wizard/kantor_wizard.dart';

/// Settings of the daemon itself (`settings` in `GET /api/state`, saved with
/// `POST /api/settings`), like `web/js/settings.js`. Shows nothing until the
/// daemon answers. The daemon's and Ghina's tokens never appear here: the
/// daemon only reports whether the Ghina push is on.
class KantorDaemonSettings extends ConsumerStatefulWidget {
  const KantorDaemonSettings({super.key});

  @override
  ConsumerState<KantorDaemonSettings> createState() =>
      _KantorDaemonSettingsState();
}

class _KantorDaemonSettingsState extends ConsumerState<KantorDaemonSettings> {
  final _holdKantor = TextEditingController();
  final _holdManual = TextEditingController();
  final _musicDir = TextEditingController();
  String _perm = '';
  bool _loaded = false;
  bool _saving = false;
  String? _message;
  bool _ok = true;

  @override
  void dispose() {
    _holdKantor.dispose();
    _holdManual.dispose();
    _musicDir.dispose();
    super.dispose();
  }

  void _fill(Map<String, dynamic> settings) {
    final a = settings['approvals'] as Map? ?? const {};
    _holdKantor.text = '${a['holdKantorSec'] ?? 0}';
    _holdManual.text = '${a['holdManualSec'] ?? 0}';
    _musicDir.text = '${settings['musicDir'] ?? ''}';
    final p = '${settings['defaultPermissionMode'] ?? ''}';
    _perm = kantorPermModes.any((m) => m.$1 == p) ? p : '';
    _loaded = true;
  }

  Future<void> _save(Map<String, dynamic> body, String done) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await api.post('/api/settings', body);
      ref.invalidate(kantorStateProvider);
      setState(() {
        _ok = true;
        _message = done;
      });
    } on KantorException catch (e) {
      setState(() {
        _ok = false;
        _message = e.message;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveApprovals() {
    final k = int.tryParse(_holdKantor.text.trim());
    final m = int.tryParse(_holdManual.text.trim());
    if (k == null || m == null || k < 0 || m < 0) {
      setState(() {
        _ok = false;
        _message = 'Isi detik dengan angka 0 atau lebih.';
      });
      return;
    }
    _save({
      'approvals': {'holdKantorSec': k, 'holdManualSec': m},
      'defaultPermissionMode': _perm,
    }, 'Pengaturan izin disimpan.');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final st = ref.watch(kantorStateProvider).value;
    final settings = st?['settings'];
    if (st == null || settings is! Map) return const SizedBox.shrink();
    final s = Map<String, dynamic>.from(settings);
    if (!_loaded) _fill(s);
    final notify = s['ghinaNotify'] as Map?;
    final hosts = [for (final h in s['extraHosts'] as List? ?? const []) '$h'];
    final roots = [for (final r in s['roots'] as List? ?? const []) '$r'];

    Widget flag(String label, bool? ok, String yes, String no) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GhinaType.body)),
          ChunkyPill(
            label: ok == true ? yes : no,
            color: ok == true ? GhinaColors.green : GhinaColors.orange,
            soft: true,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Daemon Kantor'),
        ChunkyCard(
          padding: const EdgeInsets.all(GhinaSpace.md),
          child: Column(
            children: [
              flag('tmux', st['tmux'] as bool?, 'Tersedia', 'Tidak ada'),
              flag(
                'Claude CLI',
                st['claude'] as bool?,
                'Ditemukan',
                'Tidak ada',
              ),
              flag('Hooks global', st['hooks'] as bool?, 'Terpasang', 'Belum'),
              if (notify != null)
                flag(
                  'Notifikasi ke Ghina',
                  notify['enabled'] == true && notify['ready'] == true,
                  'Aktif',
                  notify['enabled'] == false ? 'Mati' : 'Belum diatur',
                ),
            ],
          ),
        ),
        const SectionHeader(title: 'Persetujuan izin'),
        Text(
          'Berapa lama permintaan izin Claude ditahan supaya bisa dijawab dari '
          'Kotak masuk. 0 = tidak ditahan; terminal langsung bertanya.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: GhinaSpace.sm),
        ChunkyTextField(
          label: 'Tahan untuk shift kantor (detik)',
          controller: _holdKantor,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: GhinaSpace.md),
        ChunkyTextField(
          label: 'Tahan untuk sesi manual (detik)',
          controller: _holdManual,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: GhinaSpace.md),
        DropdownButtonFormField<String>(
          initialValue: _perm,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Mode izin bawaan shift kantor',
          ),
          items: [
            for (final (v, l) in kantorPermModes)
              DropdownMenuItem(value: v, child: Text(l)),
          ],
          onChanged: (v) => setState(() => _perm = v ?? ''),
        ),
        const SizedBox(height: GhinaSpace.md),
        ChunkyButton(
          label: 'Simpan izin',
          variant: ChunkyButtonVariant.outline,
          loading: _saving,
          onPressed: _saving ? null : _saveApprovals,
        ),
        const SectionHeader(title: 'Musik'),
        ChunkyTextField(
          label: 'Folder musik di komputer kantor',
          controller: _musicDir,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: GhinaSpace.md),
        ChunkyButton(
          label: 'Simpan folder musik',
          variant: ChunkyButtonVariant.outline,
          onPressed: _saving
              ? null
              : () => _save({
                  'musicDir': _musicDir.text.trim(),
                }, 'Folder musik disimpan.'),
        ),
        if (_message != null) ...[
          const SizedBox(height: GhinaSpace.md),
          ChunkyCard(
            tinted: _ok ? GhinaColors.green : GhinaColors.red,
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Text(
              _message!,
              key: const ValueKey('daemon-settings-message'),
              style: GhinaType.body.copyWith(color: g.textPrimary),
            ),
          ),
        ],
        const SectionHeader(title: 'Folder induk dan akses'),
        Text(
          'Folder induk yang boleh dipakai kantor baru: '
          '${roots.isEmpty ? '-' : roots.map(kantorTilde).join(', ')}.\n'
          'Host tambahan: ${hosts.isEmpty ? 'belum ada' : hosts.join(', ')}.\n'
          'Keduanya diubah di config.json daemon, lalu mulai ulang daemon.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const PratinjauStorageSettings(),
        const SizedBox(height: GhinaSpace.lg),
      ],
    );
  }
}
