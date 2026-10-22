import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../roles/kantor_role.dart' show KantorRole, kantorRolesProvider;
import '../roles/kantor_shift_sheet.dart' show kantorPermModes;
import '../roles/kantor_ui.dart';

const _hosts = {
  'vscode': 'VS Code',
  'terminal': 'Terminal',
  'iterm': 'iTerm2',
  'tmux': 'tmux',
  'lain': 'aplikasi terminal lain',
};

/// What "move to the office" does to the original terminal session.
String kantorAdoptWarning(String? host) {
  final where = _hosts[host] ?? 'Terminal';
  if (host == 'vscode' || host == 'lain') {
    return 'Kantor menghentikan proses Claude di terminal $where (hanya kalau '
        'sedang tidak bekerja), lalu melanjutkan sesi yang sama di tmux kantor '
        'pada folder yang sama. Sesi $where tidak bisa diketik dari kantor, '
        'jadi yang terjadi adalah salinan resume: percakapannya tetap ada, '
        'tetapi tab $where boleh kamu tutup setelahnya.';
  }
  return 'Kantor mengetik /exit di tab $where-nya, lalu melanjutkan sesi yang '
      'sama (claude --resume) di tmux kantor pada folder yang sama. Sesi '
      'aslinya diminta keluar. Isi percakapannya tetap ada.';
}

typedef _Choice = ({
  String role,
  String perm,
  String boss,
  String newName,
  String newTitle,
  bool isNew,
});

/// "Pindahkan ke kantor": picks a role (existing, new under a boss, or none),
/// confirms the warning, then `POST /api/sessions/<sid>/adopt`. Returns whether
/// the session was moved.
Future<bool> adoptKantorSession(
  BuildContext context,
  WidgetRef ref, {
  required String officeId,
  required String sid,
  String? host,
  String? currentBoss,
}) async {
  final api = ref.read(kantorApiProvider);
  if (api == null) return false;
  final roles =
      (ref.read(kantorRolesProvider(officeId)).value ?? const <KantorRole>[])
          .where((r) => !r.archived)
          .toList();
  final c = await showChunkyBottomSheet<_Choice>(
    context,
    title: 'Pindahkan ke kantor',
    builder: (_) =>
        _AdoptForm(roles: roles, host: host, currentBoss: currentBoss),
  );
  if (c == null || !context.mounted) return false;
  final yes = await showChunkyConfirm(
    context,
    title: 'Pindahkan sesi ini?',
    message: kantorAdoptWarning(host),
    confirmLabel: 'Pindahkan',
    destructive: true,
  );
  if (!yes || !context.mounted) return false;
  final boss = c.boss.isEmpty ? null : c.boss;
  final ok = await kantorGuard(
    context,
    () => api.post('/api/sessions/${Uri.encodeComponent(sid)}/adopt', {
      'role': c.isNew || c.role.isEmpty ? null : c.role,
      'permissionMode': c.perm.isEmpty ? null : c.perm,
      'newRole': c.isNew
          ? {'name': c.newName, 'title': c.newTitle, 'reportsTo': boss}
          : null,
      'boss': c.role.isEmpty || c.isNew ? (c.isNew ? null : boss) : null,
    }),
  );
  if (ok) {
    ref.invalidate(kantorOfficeProvider(officeId));
    ref.invalidate(kantorRolesProvider(officeId));
    ref.invalidate(kantorStateProvider);
    if (context.mounted) kantorToast(context, 'Sesi sekarang jalan di kantor');
  }
  return ok;
}

class _AdoptForm extends StatefulWidget {
  const _AdoptForm({required this.roles, this.host, this.currentBoss});
  final List<KantorRole> roles;
  final String? host, currentBoss;

  @override
  State<_AdoptForm> createState() => _AdoptFormState();
}

class _AdoptFormState extends State<_AdoptForm> {
  static const _new = '__new';
  String _role = '';
  String _perm = 'bypassPermissions';
  late String _boss = widget.roles.any((r) => r.id == widget.currentBoss)
      ? widget.currentBoss!
      : '';
  final _name = TextEditingController();
  final _title = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final isNew = _role == _new;
    if (isNew && _name.text.trim().isEmpty) {
      kantorToast(context, 'Isi nama role barunya', warn: true);
      return;
    }
    Navigator.of(context).pop<_Choice>((
      role: isNew ? '' : _role,
      perm: _perm,
      boss: _boss,
      newName: _name.text.trim(),
      newTitle: _title.text.trim(),
      isNew: isNew,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final existing = _role.isNotEmpty && _role != _new;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyCard(
          tinted: GhinaColors.orange,
          padding: const EdgeInsets.all(GhinaSpace.md),
          child: Text(
            kantorAdoptWarning(widget.host),
            style: GhinaType.bodyS.copyWith(color: g.textPrimary),
          ),
        ),
        const SizedBox(height: GhinaSpace.md),
        KantorPickField<String>(
          label: 'Sesi ini jadi siapa?',
          value: _role,
          options: [
            const KantorChoice('', 'Tetap sesi tanpa role'),
            const KantorChoice(_new, '+ Role baru', 'beri nama dan atasan'),
            for (final r in widget.roles) KantorChoice(r.id, r.name, r.title),
          ],
          onChanged: (v) => setState(() => _role = v),
        ),
        if (_role == _new) ...[
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            label: 'Nama',
            hint: 'mis. Gilang',
            controller: _name,
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            label: 'Jabatan',
            hint: 'mis. Asisten Laravel',
            controller: _title,
          ),
        ],
        if (!existing) ...[
          const SizedBox(height: GhinaSpace.md),
          KantorPickField<String>(
            label: 'Anak buah dari',
            value: _boss,
            options: [
              const KantorChoice('', 'Tidak ada', 'langsung di bawah manager'),
              for (final r in widget.roles) KantorChoice(r.id, r.name, r.title),
            ],
            onChanged: (v) => setState(() => _boss = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _role == _new
                  ? 'Role baru ini jadi anak buah pilihanmu, tercatat permanen di profilnya.'
                  : 'Sesi tetap anonim dan sementara, tapi tahu atasannya: dia melapor lewat komentar kartu.',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ),
        ],
        const SizedBox(height: GhinaSpace.md),
        KantorPickField<String>(
          label: 'Mode izin di kantor',
          value: _perm,
          options: [for (final m in kantorPermModes) KantorChoice(m.$1, m.$2)],
          onChanged: (v) => setState(() => _perm = v),
        ),
        const SizedBox(height: GhinaSpace.lg),
        ChunkyButton(label: 'Lanjut', onPressed: _submit),
      ],
    );
  }
}

/// Details of a session that belongs to no office (`loose` in `/api/state`).
/// The daemon can only move sessions it knows an office for, so this explains
/// instead of offering a move that would fail.
Future<void> showKantorLooseSheet(
  BuildContext context,
  Map<String, dynamic> s,
) {
  final host = _hosts[s['host']] ?? '${s['host'] ?? 'Terminal'}';
  final cwd = '${s['cwd'] ?? ''}'.replaceFirst(RegExp(r'^/Users/[^/]+'), '~');
  return showChunkyBottomSheet<void>(
    context,
    title: '${s['title'] ?? 'Sesi'}',
    showClose: true,
    builder: (c) {
      final g = c.ghina;
      Widget row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(
                k,
                style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Folder', cwd.isEmpty ? '-' : cwd),
          row('Terminal', host),
          row('Status', '${s['status'] ?? '-'}'),
          const SizedBox(height: GhinaSpace.sm),
          Text(
            'Sesi ini jalan di luar folder kantor mana pun, jadi belum bisa '
            'dijadikan role atau dipindahkan ke tmux kantor. Buka Claude dari '
            'folder project kantor; sesinya lalu muncul di tab Agen kantor itu '
            'dan bisa dipindahkan dari tab Terminalnya.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ],
      );
    },
  );
}
