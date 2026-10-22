import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import 'kantor_role.dart';
import 'kantor_ui.dart';

/// Permission modes a shift can start with (`''` = office default).
const kantorPermModes = <(String, String)>[
  ('', 'Default kantor'),
  ('ikut', 'Ikuti pengaturan Claude'),
  ('default', 'Selalu tanya'),
  ('acceptEdits', 'Edit file otomatis'),
  ('auto', 'Auto mode'),
  ('plan', 'Hanya merencanakan'),
  ('bypassPermissions', 'Lewati semua izin'),
];

/// Starts a shift for [role]; opens the session on success.
Future<void> showKantorShiftSheet(
  BuildContext context, {
  required String officeId,
  required KantorRole role,
  required int liveSessions,
}) => showChunkyBottomSheet<void>(
  context,
  title: 'Mulai shift ${role.name}',
  builder: (_) => SingleChildScrollView(
    child: KantorShiftForm(
      officeId: officeId,
      role: role,
      liveSessions: liveSessions,
    ),
  ),
);

class KantorShiftForm extends ConsumerStatefulWidget {
  const KantorShiftForm({
    super.key,
    required this.officeId,
    required this.role,
    required this.liveSessions,
  });

  final String officeId;
  final KantorRole role;
  final int liveSessions;

  @override
  ConsumerState<KantorShiftForm> createState() => _KantorShiftFormState();
}

class _KantorShiftFormState extends ConsumerState<KantorShiftForm> {
  final _task = TextEditingController();
  List<({String id, String title, bool mine})> _cards = const [];
  String _card = '';
  String _perm = '';
  late KantorEngineSel _eng = KantorEngineSel.initial(widget.role.look);
  bool _worktree = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final j = await api.get(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/board',
      );
      final cards = <({String id, String title, bool mine})>[];
      for (final c in (j as Map)['cards'] as List? ?? const []) {
        if (c is! Map) continue;
        final col = c['col'];
        final who = c['who'];
        if (col is num && col >= 4) continue;
        if (who is String && who.isNotEmpty && who != widget.role.id) continue;
        cards.add((
          id: '${c['id']}',
          title: '${c['title']}',
          mine: who == widget.role.id,
        ));
      }
      if (mounted) setState(() => _cards = cards);
    } catch (_) {
      // cards are optional: the shift can start without one
    }
  }

  Future<void> _start() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final task = _task.text.trim();
    final body = <String, dynamic>{
      if (task.isNotEmpty) 'task': task,
      if (_card.isNotEmpty) 'cardId': _card,
      if (!_eng.codex && _perm.isNotEmpty) 'permissionMode': _perm,
      if (widget.liveSessions > 0 && _worktree) 'worktree': true,
      ..._eng.body(widget.role.look),
    };
    setState(() => _busy = true);
    String? sid;
    final ok = await kantorGuard(context, () async {
      final r = await api.post(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/roles/${Uri.encodeComponent(widget.role.id)}/start',
        body,
      );
      sid = (r as Map)['sid'] as String?;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (sid != null) router.push('/kantor/o/${widget.officeId}/s/$sid');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.liveSessions > 0) ...[
          ChunkyCard(
            tinted: GhinaColors.blue,
            child: Text(
              'Ini sesi paralel ke-${widget.liveSessions + 1} untuk ${widget.role.name}.',
              style: GhinaType.body.copyWith(color: g.textPrimary),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pakai worktree terpisah'),
            subtitle: const Text(
              'Disarankan kalau dua sesi mengedit repo yang sama.',
            ),
            value: _worktree,
            onChanged: (v) => setState(() => _worktree = v),
          ),
        ],
        ChunkyTextField(
          controller: _task,
          label: 'Tugas pertama (opsional)',
          hint: 'mis. perbaiki bug login lalu jalankan tes',
          minLines: 2,
          maxLines: 5,
        ),
        const SizedBox(height: GhinaSpace.md),
        KantorPickField<String>(
          label: 'Kartu (opsional)',
          emptyLabel: 'Tanpa kartu',
          value: _card,
          options: [
            const KantorChoice('', 'Tanpa kartu'),
            for (final c in _cards)
              KantorChoice(c.id, c.title, c.mine ? null : 'Belum ditugaskan'),
          ],
          onChanged: (v) => setState(() => _card = v),
        ),
        const SizedBox(height: GhinaSpace.md),
        KantorEngineFields(
          role: widget.role.look,
          onChanged: (s) => setState(() => _eng = s),
        ),
        if (!_eng.codex) ...[
          const SizedBox(height: GhinaSpace.md),
          KantorPickField<String>(
            label: 'Mode izin',
            value: _perm,
            options: [
              for (final m in kantorPermModes) KantorChoice(m.$1, m.$2),
            ],
            onChanged: (v) => setState(() => _perm = v),
          ),
        ],
        if (!_eng.codex && _perm == 'bypassPermissions')
          Padding(
            padding: const EdgeInsets.only(top: GhinaSpace.sm),
            child: Text(
              'Role ini akan menjalankan perintah apa pun tanpa bertanya, termasuk yang menyentuh prod. Kotak masuk izin tidak dipakai.',
              style: GhinaType.bodyS.copyWith(color: GhinaColors.orange.base),
            ),
          ),
        const SizedBox(height: GhinaSpace.lg),
        ChunkyButton(
          label: 'Mulai shift',
          icon: Icons.play_arrow_rounded,
          loading: _busy,
          onPressed: _busy ? null : _start,
        ),
      ],
    );
  }
}
