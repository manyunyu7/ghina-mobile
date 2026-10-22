import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_sprite.dart';
import 'kantor_meeting.dart';

/// New meeting form. Pops the new meeting id.
class KantorMeetingFormScreen extends ConsumerStatefulWidget {
  const KantorMeetingFormScreen({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorMeetingFormScreen> createState() => _MeetingFormState();
}

class _MeetingFormState extends ConsumerState<KantorMeetingFormScreen> {
  final _topic = TextEditingController();
  final _agenda = TextEditingController();
  final _parts = <String>[];
  bool _seeded = false;
  int _rounds = 2;
  String _chair = '';
  bool _busy = false;

  @override
  void dispose() {
    _topic.dispose();
    _agenda.dispose();
    super.dispose();
  }

  void _fixChair(List<KantorRole> roles) {
    final chosen = [
      for (final r in roles)
        if (_parts.contains(r.id)) r,
    ];
    if (chosen.any((r) => r.id == _chair)) return;
    _chair =
        (chosen.where((r) => r.isManager).firstOrNull ?? chosen.firstOrNull)
            ?.id ??
        '';
  }

  Future<void> _submit() async {
    final topic = _topic.text.trim();
    if (topic.isEmpty) {
      kantorToast(context, 'Isi topik rapat dulu', warn: true);
      return;
    }
    if (_parts.length < 2) {
      kantorToast(context, 'Pilih minimal 2 peserta', warn: true);
      return;
    }
    final turns = kantorMeetingTurns(_parts.length, _rounds);
    final ok = await showChunkyConfirm(
      context,
      title: 'Mulai rapat?',
      message:
          'Sekitar $turns giliran, tiap giliran memakai model role-nya. Ini biaya nyata setara pemakaian API.',
      confirmLabel: 'Mulai rapat',
    );
    if (!ok || !mounted) return;
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    String? id;
    final done = await kantorGuard(context, () async {
      final r = await api.post(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/meetings',
        {
          'topic': topic,
          'agenda': _agenda.text.trim(),
          'participants': _parts,
          'rounds': _rounds,
          'chair': _chair,
        },
      );
      final m = r as Map;
      id = (m['id'] ?? (m['meeting'] as Map?)?['id']) as String?;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) return;
    kantorToast(context, 'Rapat dimulai');
    Navigator.of(context).pop(id ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rolesAsync = ref.watch(kantorRolesProvider(widget.officeId));
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Rapat baru')),
      body: rolesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(kantorErrorText(e))),
        data: (all) {
          final roles = [
            for (final r in all)
              if (!r.archived) r,
          ];
          if (roles.length < 2) {
            return const EmptyState(
              title: 'Role belum cukup',
              message:
                  'Rapat butuh minimal 2 role. Tambahkan role di tab Role dulu.',
            );
          }
          if (!_seeded) {
            _seeded = true;
            _parts.addAll(roles.take(3).map((r) => r.id));
          }
          _fixChair(roles);
          final chosen = [
            for (final r in roles)
              if (_parts.contains(r.id)) r,
          ];
          return ListView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            children: [
              ChunkyTextField(
                controller: _topic,
                label: 'Topik',
                hint: 'mis. Rencana rilis 1.8',
              ),
              const SizedBox(height: GhinaSpace.md),
              ChunkyTextField(
                controller: _agenda,
                label: 'Agenda / konteks',
                hint: 'Apa yang perlu diputuskan? Tautan, batasan, tenggat.',
                minLines: 3,
                maxLines: 8,
              ),
              const SizedBox(height: GhinaSpace.lg),
              const KantorFieldLabel('Peserta (minimal 2)'),
              for (final r in roles)
                Padding(
                  padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                  child: ChunkyTile(
                    title: r.name,
                    subtitle: '${r.title} · ${kantorModelName(r.model)}',
                    leading: KantorSprite(look: r.look, size: 40),
                    tinted: _parts.contains(r.id) ? GhinaColors.blue : null,
                    trailing: Icon(
                      _parts.contains(r.id)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: _parts.contains(r.id)
                          ? GhinaColors.blue.base
                          : g.textMuted,
                    ),
                    onTap: () => setState(() {
                      _parts.contains(r.id)
                          ? _parts.remove(r.id)
                          : _parts.add(r.id);
                    }),
                  ),
                ),
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Ronde'),
              ChunkyChoiceChips<int>(
                options: [
                  for (var i = 1; i <= 4; i++)
                    ChunkyChoice(value: i, label: '$i ronde'),
                ],
                selected: {_rounds},
                onChanged: (s) {
                  if (s.isNotEmpty) setState(() => _rounds = s.first);
                },
              ),
              const SizedBox(height: GhinaSpace.md),
              KantorPickField<String>(
                label: 'Ketua',
                value: _chair,
                options: [
                  for (final r in chosen) KantorChoice(r.id, r.name, r.title),
                ],
                onChanged: (v) => setState(() => _chair = v),
              ),
              const SizedBox(height: GhinaSpace.lg),
              ChunkyCard(
                tinted: GhinaColors.blue,
                child: Text(
                  '${kantorMeetingTurns(_parts.length, _rounds)} giliran (${_parts.length} peserta x $_rounds ronde + 1 notulen), tiap giliran memakai model role-nya. Biaya nyata, setara pemakaian API: rapat panjang dengan model besar bisa mencapai beberapa dolar.',
                  style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                ),
              ),
              const SizedBox(height: GhinaSpace.lg),
              ChunkyButton(
                label: 'Mulai rapat',
                loading: _busy,
                onPressed: _busy || _parts.length < 2 ? null : _submit,
              ),
              const SizedBox(height: GhinaSpace.xxl),
            ],
          );
        },
      ),
    );
  }
}
