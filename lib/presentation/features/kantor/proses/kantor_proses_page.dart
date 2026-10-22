import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_states.dart';
import 'kantor_proses_data.dart';
import 'kantor_proses_log.dart';

/// The office dock: processes agents or the owner run per room (dev servers,
/// watchers). Same API as the web dock (`/api/offices/<id>/procs`).
Future<void> openKantorProses(
  BuildContext context, {
  required String officeId,
  String? room,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => KantorProsesPage(officeId: officeId, room: room),
  ),
);

class KantorProsesPage extends ConsumerWidget {
  const KantorProsesPage({super.key, required this.officeId, this.room});

  final String officeId;

  /// Room to put first (opened from a room on the floor).
  final String? room;

  String get _base => '/api/offices/${Uri.encodeComponent(officeId)}/procs';

  Future<void> _call(
    BuildContext context,
    WidgetRef ref,
    String path, {
    Object? body,
    String? ok,
  }) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final done = await kantorGuard(context, () => api.post(path, body));
    ref.invalidate(kantorProcsProvider(officeId));
    if (done && ok != null && context.mounted) kantorToast(context, ok);
  }

  Future<void> _stop(BuildContext c, WidgetRef ref, KantorProc p) async {
    final yes = await showChunkyConfirm(
      c,
      title: 'Hentikan proses?',
      message: '"${p.name}" akan dihentikan (${p.cmd}).',
      confirmLabel: 'Hentikan',
      destructive: true,
    );
    if (yes && c.mounted) {
      await _call(c, ref, '$_base/${p.id}/stop', ok: 'Dihentikan');
    }
  }

  Future<void> _restart(BuildContext c, WidgetRef ref, KantorProc p) async {
    final yes = await showChunkyConfirm(
      c,
      title: 'Jalankan ulang?',
      message: '"${p.name}" dihentikan lalu dijalankan lagi.',
      confirmLabel: 'Ulang',
    );
    if (yes && c.mounted) {
      await _call(c, ref, '$_base/${p.id}/restart', ok: 'Dimulai ulang');
    }
  }

  Future<void> _start(BuildContext c, WidgetRef ref, KantorProc p) async {
    final yes = await showChunkyConfirm(
      c,
      title: 'Jalankan perintah?',
      message:
          '${p.cmd}\n\nDijalankan lewat zsh di folder ruangan ${p.roomName}.',
      confirmLabel: 'Jalankan',
    );
    if (yes && c.mounted) {
      await _call(c, ref, '$_base/${p.id}/start', ok: 'Dijalankan');
    }
  }

  Future<void> _approve(
    BuildContext c,
    WidgetRef ref,
    KantorProc p, {
    required bool start,
  }) async {
    final yes = await showChunkyConfirm(
      c,
      title: start ? 'Setujui dan jalankan?' : 'Setujui perintah?',
      message: 'Agen mengusulkan:\n${p.cmd}',
      confirmLabel: start ? 'Setujui & jalankan' : 'Setujui',
    );
    if (yes && c.mounted) {
      await _call(
        c,
        ref,
        '$_base/${p.id}/approve',
        body: {'start': start},
        ok: 'Disetujui',
      );
    }
  }

  Future<void> _remove(BuildContext c, WidgetRef ref, KantorProc p) async {
    final yes = await showChunkyConfirm(
      c,
      title: p.pending ? 'Tolak usulan?' : 'Hapus dari daftar?',
      message: p.running
          ? '"${p.name}" sedang jalan dan akan dihentikan.'
          : '"${p.name}" dihapus dari daftar proses.',
      confirmLabel: p.pending ? 'Tolak' : 'Hapus',
      destructive: true,
    );
    if (!yes || !c.mounted) return;
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    await kantorGuard(
      c,
      () => api.delete('$_base/${Uri.encodeComponent(p.id)}'),
    );
    ref.invalidate(kantorProcsProvider(officeId));
  }

  Future<void> _add(
    BuildContext c,
    WidgetRef ref,
    List<Map<String, dynamic>> rooms, {
    String? roomId,
    String cmd = '',
    String name = '',
  }) async {
    final res = await showChunkyBottomSheet<_NewProc>(
      c,
      title: 'Perintah baru',
      builder: (_) =>
          _NewProcForm(rooms: rooms, room: roomId, cmd: cmd, name: name),
    );
    if (res == null || !c.mounted) return;
    final yes = await showChunkyConfirm(
      c,
      title: res.start ? 'Tambah dan jalankan?' : 'Tambah perintah?',
      message:
          '${res.cmd}\n\nDijalankan lewat zsh di folder ruangan ${res.roomName}.',
      confirmLabel: res.start ? 'Tambah & jalankan' : 'Tambah',
    );
    if (!yes || !c.mounted) return;
    await _call(
      c,
      ref,
      _base,
      body: {
        'room': res.room,
        'name': res.name,
        'cmd': res.cmd,
        'start': res.start,
      },
      ok: res.start ? 'Ditambah dan dijalankan' : 'Ditambah',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final procs = ref.watch(kantorProcsProvider(officeId));
    final office = ref.watch(kantorOfficeProvider(officeId)).value;
    final rooms = [
      for (final r
          in ((office?['plan'] as Map?)?['rooms'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    final addable = [
      for (final r in rooms)
        if (r['path'] != null) r,
    ];
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text('Proses · ${office?['name'] ?? officeId}'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(kantorProcsProvider(officeId)),
          ),
        ],
      ),
      floatingActionButton: addable.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context, ref, addable, roomId: room),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Perintah'),
            ),
      body: procs.when(
        loading: () => const KantorLoading(),
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kantorProcsProvider(officeId)),
        ),
        data: (d) {
          final names = {for (final r in rooms) '${r['id']}': '${r['name']}'};
          final ids = <String>{
            ...d.procs.map((p) => p.room),
            ...d.suggestions.map((s) => s.room),
            ?room,
          };
          final order = [
            ?room,
            for (final r in rooms)
              if (ids.contains('${r['id']}') && r['id'] != room) '${r['id']}',
            for (final i in ids)
              if (!names.containsKey(i) && i != room) i,
          ];
          if (order.isEmpty) {
            return const EmptyState(
              title: 'Belum ada proses',
              message:
                  'Tambahkan perintah seperti npm run dev lewat tombol di bawah.',
              compact: true,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(kantorProcsProvider(officeId));
              await ref.read(kantorProcsProvider(officeId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.sm,
                GhinaSpace.page,
                96,
              ),
              children: [
                for (final rid in order) ...[
                  SectionHeader(
                    title: names[rid] ?? rid,
                    actionLabel: names.containsKey(rid) ? 'Tambah' : null,
                    onAction: names.containsKey(rid)
                        ? () => _add(context, ref, addable, roomId: rid)
                        : null,
                  ),
                  for (final p in d.procs.where((p) => p.room == rid))
                    _ProcCard(
                      proc: p,
                      onLog: () => openKantorProcLog(
                        context,
                        officeId: officeId,
                        procId: p.id,
                      ),
                      onStop: () => _stop(context, ref, p),
                      onStart: () => _start(context, ref, p),
                      onRestart: () => _restart(context, ref, p),
                      onRemove: () => _remove(context, ref, p),
                      onApprove: (s) => _approve(context, ref, p, start: s),
                    ),
                  for (final s in d.suggestions.where((s) => s.room == rid))
                    Padding(
                      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                      child: ChunkyTile(
                        dense: true,
                        title: s.cmd,
                        subtitle: 'Saran: ${s.why}',
                        trailing: const Icon(Icons.add_rounded),
                        onTap: () => _add(
                          context,
                          ref,
                          addable,
                          roomId: rid,
                          cmd: s.cmd,
                          name: s.name,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProcCard extends StatelessWidget {
  const _ProcCard({
    required this.proc,
    required this.onLog,
    required this.onStop,
    required this.onStart,
    required this.onRestart,
    required this.onRemove,
    required this.onApprove,
  });

  final KantorProc proc;
  final VoidCallback onLog, onStop, onStart, onRestart, onRemove;
  final ValueChanged<bool> onApprove;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = proc;
    final (label, color) = kantorProcStatus(p);
    final dur = p.running ? kantorDuration(p.since) : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyCard(
        onTap: p.pending ? null : onLog,
        padding: const EdgeInsets.all(GhinaSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                ),
                Text(
                  label,
                  style: GhinaType.caption.w(800).copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.cmd,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.copyWith(
                color: g.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                p.origin,
                p.roomName,
                if (dur.isNotEmpty) 'jalan $dur',
                if (p.port != null) 'port ${p.port}',
              ].join(' · '),
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
            const SizedBox(height: GhinaSpace.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: p.pending
                  ? [
                      _btn('Setujui & jalankan', () => onApprove(true)),
                      _btn('Setujui', () => onApprove(false), outline: true),
                      _btn('Tolak', onRemove, danger: true),
                    ]
                  : [
                      if (p.running) ...[
                        _btn(
                          'Hentikan',
                          p.stopping ? null : onStop,
                          danger: true,
                        ),
                        _btn('Ulang', onRestart, outline: true),
                      ] else
                        _btn('Jalankan', onStart),
                      _btn('Log', onLog, outline: true),
                      _btn('Hapus', onRemove, outline: true),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(
    String label,
    VoidCallback? onTap, {
    bool outline = false,
    bool danger = false,
  }) => ChunkyButton(
    label: label,
    size: ChunkyButtonSize.small,
    expand: false,
    uppercase: false,
    variant: danger
        ? ChunkyButtonVariant.danger
        : outline
        ? ChunkyButtonVariant.outline
        : ChunkyButtonVariant.primary,
    onPressed: onTap,
  );
}

/// Status text and colour for a process ("Jalan", "Gagal · kode 1", …).
(String, Color) kantorProcStatus(KantorProc p) {
  if (p.pending) return ('Menunggu persetujuan', GhinaColors.orange.base);
  if (p.stopping) return ('Menghentikan…', GhinaColors.orange.base);
  return switch (p.status) {
    'jalan' => ('Jalan', GhinaColors.green.base),
    'gagal' => (
      'Gagal${p.code != null ? ' · kode ${p.code}' : ''}',
      GhinaColors.red.base,
    ),
    _ => (
      p.code != null ? 'Berhenti · kode ${p.code}' : 'Berhenti',
      const Color(0xFF8A8A8A),
    ),
  };
}

class _NewProc {
  const _NewProc(this.room, this.roomName, this.name, this.cmd, this.start);
  final String room, roomName, name, cmd;
  final bool start;
}

class _NewProcForm extends StatefulWidget {
  const _NewProcForm({
    required this.rooms,
    this.room,
    this.cmd = '',
    this.name = '',
  });

  final List<Map<String, dynamic>> rooms;
  final String? room;
  final String cmd, name;

  @override
  State<_NewProcForm> createState() => _NewProcFormState();
}

class _NewProcFormState extends State<_NewProcForm> {
  late String _room =
      widget.room ??
      (widget.rooms.isEmpty ? '' : '${widget.rooms.first['id']}');
  late final _name = TextEditingController(text: widget.name);
  late final _cmd = TextEditingController(text: widget.cmd);

  @override
  void dispose() {
    _name.dispose();
    _cmd.dispose();
    super.dispose();
  }

  void _submit(bool start) {
    final cmd = _cmd.text.trim();
    if (cmd.isEmpty || _room.isEmpty) {
      kantorToast(context, 'Perintah belum diisi', warn: true);
      return;
    }
    final rn = widget.rooms.firstWhere(
      (r) => '${r['id']}' == _room,
      orElse: () => {'name': _room},
    )['name'];
    Navigator.of(
      context,
    ).pop(_NewProc(_room, '$rn', _name.text.trim(), cmd, start));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KantorPickField<String>(
        label: 'Ruangan',
        value: _room,
        options: [
          for (final r in widget.rooms)
            KantorChoice('${r['id']}', '${r['name']}', '${r['path'] ?? ''}'),
        ],
        onChanged: (v) => setState(() => _room = v),
      ),
      const SizedBox(height: GhinaSpace.md),
      ChunkyTextField(
        label: 'Nama',
        hint: 'mis. Dev server',
        controller: _name,
      ),
      const SizedBox(height: GhinaSpace.md),
      ChunkyTextField(
        label: 'Perintah',
        hint: 'npm run dev',
        controller: _cmd,
        autofocus: widget.cmd.isEmpty,
        textCapitalization: TextCapitalization.none,
        helperText:
            'Dijalankan lewat zsh di folder ruangan. Port dibaca otomatis dari log.',
      ),
      const SizedBox(height: GhinaSpace.lg),
      ChunkyButton(label: 'Tambah & jalankan', onPressed: () => _submit(true)),
      const SizedBox(height: GhinaSpace.sm),
      ChunkyButton(
        label: 'Tambah saja',
        variant: ChunkyButtonVariant.outline,
        onPressed: () => _submit(false),
      ),
    ],
  );
}
