import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_shift_sheet.dart' show kantorPermModes;
import '../roles/kantor_ui.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import 'kantor_transcript_screen.dart';

/// One archived (or running) session of the office.
final class KantorArchiveRow {
  const KantorArchiveRow({
    required this.sid,
    required this.role,
    required this.room,
    required this.title,
    required this.firstPrompt,
    required this.startedAt,
    required this.lastSeen,
    required this.cost,
    required this.active,
  });

  factory KantorArchiveRow.fromJson(Map<String, dynamic> j) => KantorArchiveRow(
    sid: j['sid'] as String? ?? '',
    role: j['role'] as String?,
    room: j['room'] as String?,
    title: j['title'] as String? ?? '',
    firstPrompt: j['first_prompt'] as String? ?? '',
    startedAt: j['started_at'] as String? ?? '',
    lastSeen: (j['last_seen'] ?? j['ended_at']) as String? ?? '',
    cost: (j['cost'] as num?)?.toDouble() ?? 0,
    active: j['active'] == true,
  );

  final String sid;
  final String? role;
  final String? room;
  final String title;
  final String firstPrompt;
  final String startedAt;
  final String lastSeen;
  final double cost;
  final bool active;

  String get label => title.isNotEmpty
      ? title
      : (firstPrompt.isNotEmpty ? firstPrompt : 'Sesi tanpa judul');
}

final kantorArchiveProvider = FutureProvider.autoDispose
    .family<List<KantorArchiveRow>, String>((ref, officeId) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null)
        throw const KantorException(
          KantorFailure.unauthorized,
          'Belum ada token',
        );
      final j = await api.get(
        '/api/offices/${Uri.encodeComponent(officeId)}/archive',
      );
      return [
        for (final r in (j as List))
          if (r is Map) KantorArchiveRow.fromJson(r.cast<String, dynamic>()),
      ];
    });

/// Tab "Arsip": every session of the office, with transcript and resume.
class KantorArchiveTab extends ConsumerStatefulWidget {
  const KantorArchiveTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorArchiveTab> createState() => _KantorArchiveTabState();
}

class _KantorArchiveTabState extends ConsumerState<KantorArchiveTab> {
  String _role = '';
  String _q = '';
  bool _paid = false;

  static const _manual = '__none';

  List<KantorArchiveRow> _filter(List<KantorArchiveRow> rows) {
    final needle = _q.trim().toLowerCase();
    return [
      for (final a in rows)
        if ((_role.isEmpty ||
                (_role == _manual ? a.role == null : a.role == _role)) &&
            (!_paid || a.cost > 0) &&
            (needle.isEmpty ||
                '${a.title} ${a.firstPrompt}'.toLowerCase().contains(needle)))
          a,
    ];
  }

  Future<void> _resume(KantorArchiveRow a, List<KantorRole> roles) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final role = roles.where((r) => r.id == a.role).firstOrNull;
    final router = GoRouter.of(context);
    final office = Uri.encodeComponent(widget.officeId);
    if (role != null) {
      final ok = await showChunkyConfirm(
        context,
        title: 'Panggil lagi?',
        message:
            '${role.name} melanjutkan sesi ini dengan konteks yang sama. Shift baru memakai model sungguhan.',
        confirmLabel: 'Panggil lagi',
      );
      if (!ok || !mounted) return;
      String? sid;
      final done = await kantorGuard(context, () async {
        final r = await api.post(
          '/api/offices/$office/roles/${Uri.encodeComponent(role.id)}/start',
          {'resumeSid': a.sid},
        );
        sid = (r as Map)['sid'] as String?;
      });
      if (!done || !mounted) return;
      kantorToast(context, 'Sesi dilanjutkan');
      ref.invalidate(kantorArchiveProvider(widget.officeId));
      if (sid != null) router.push('/kantor/o/${widget.officeId}/s/$sid');
      return;
    }
    // manual session: pick the role to continue as, and a permission mode
    final picked = await showChunkyBottomSheet<({String role, String perm})>(
      context,
      title: 'Lanjutkan sesi manual',
      builder: (_) => _ManualResume(
        roles: [
          for (final r in roles)
            if (!r.archived) r,
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final done = await kantorGuard(context, () async {
      await api.post('/api/sessions/${Uri.encodeComponent(a.sid)}/adopt', {
        'role': picked.role.isEmpty ? null : picked.role,
        'permissionMode': picked.perm.isEmpty ? null : picked.perm,
      });
    });
    if (!done || !mounted) return;
    kantorToast(context, 'Sesi dilanjutkan');
    ref.invalidate(kantorArchiveProvider(widget.officeId));
    router.push('/kantor/o/${widget.officeId}/s/${a.sid}');
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.officeId;
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null) return;
      if (m['t'] == 'session-gone' ||
          (m['t'] == 'session' &&
              (m['session'] as Map?)?['status'] == 'ended')) {
        ref.invalidate(kantorArchiveProvider(id));
      }
    });
    final g = context.ghina;
    final rows = ref.watch(kantorArchiveProvider(id));
    final roles =
        ref.watch(kantorRolesProvider(id)).value ?? const <KantorRole>[];
    final office = ref.watch(kantorOfficeProvider(id)).value;

    return rows.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kantorArchiveProvider(id)),
      ),
      data: (all) {
        final shown = _filter(all);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(kantorArchiveProvider(id));
            await ref.read(kantorArchiveProvider(id).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              96,
            ),
            children: [
              const SectionHeader(
                title: 'Arsip sesi',
                subtitle:
                    'Semua sesi di kantor ini, termasuk yang dijalankan manual. Sesi bisa dipanggil lagi.',
              ),
              ChunkyTextField(
                hint: 'Cari judul atau perintah awal',
                prefixIcon: Icons.search_rounded,
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: GhinaSpace.sm),
              KantorPickField<String>(
                label: 'Role',
                value: _role,
                options: [
                  const KantorChoice('', 'Semua role'),
                  for (final r in roles) KantorChoice(r.id, r.name, r.title),
                  const KantorChoice(_manual, 'Sesi manual (tanpa role)'),
                ],
                onChanged: (v) => setState(() => _role = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hanya yang ada biaya'),
                value: _paid,
                onChanged: (v) => setState(() => _paid = v),
              ),
              if (all.isEmpty)
                const EmptyState(
                  title: 'Belum ada sesi',
                  message: 'Belum ada sesi yang tercatat di kantor ini.',
                  compact: true,
                )
              else if (shown.isEmpty)
                const EmptyState(
                  title: 'Tidak ada yang cocok',
                  message: 'Ubah filter untuk melihat sesi lain.',
                  compact: true,
                ),
              for (final a in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: GhinaSpace.md),
                  child: _row(context, a, roles, office, g),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    KantorArchiveRow a,
    List<KantorRole> roles,
    KantorOffice? office,
    GhinaTokens g,
  ) {
    final role = roles.where((r) => r.id == a.role).firstOrNull;
    final meta = [
      role?.name ?? 'Sesi manual',
      if (a.room != null) office?.roomName(a.room) ?? a.room!,
      a.active
          ? 'mulai ${kantorWhen(a.startedAt)}'
          : '${kantorWhen(a.startedAt)} · terakhir ${kantorAgo(a.lastSeen)}',
      if (a.cost > 0) kantorUsd(a.cost),
    ].where((s) => s.isNotEmpty).join(' · ');
    return ChunkyCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => KantorTranscriptScreen(sid: a.sid, title: a.label),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KantorSprite(
                look: role?.look ?? KantorSprite.guestLook(a.sid),
                size: 44,
              ),
              const SizedBox(width: GhinaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.body
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                ),
              ),
              if (a.active) const KantorStatusPill('working'),
            ],
          ),
          const SizedBox(height: GhinaSpace.sm),
          Row(
            children: [
              ChunkyButton(
                label: 'Transkrip',
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.outline,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        KantorTranscriptScreen(sid: a.sid, title: a.label),
                  ),
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              if (a.active)
                ChunkyButton(
                  label: 'Buka',
                  size: ChunkyButtonSize.small,
                  onPressed: () =>
                      context.push('/kantor/o/${widget.officeId}/s/${a.sid}'),
                )
              else
                ChunkyButton(
                  label: 'Panggil lagi',
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.secondary,
                  onPressed: () => _resume(a, roles),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualResume extends StatefulWidget {
  const _ManualResume({required this.roles});
  final List<KantorRole> roles;

  @override
  State<_ManualResume> createState() => _ManualResumeState();
}

class _ManualResumeState extends State<_ManualResume> {
  String _role = '';
  String _perm = 'bypassPermissions';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Sesi ini dilanjutkan di terminal kantor pada folder yang sama, dengan konteks percakapan yang sama.',
        style: GhinaType.bodyS.copyWith(color: context.ghina.textSecondary),
      ),
      const SizedBox(height: GhinaSpace.md),
      KantorPickField<String>(
        label: 'Lanjutkan sebagai',
        value: _role,
        options: [
          const KantorChoice('', 'Sesi tanpa role (apa adanya)'),
          for (final r in widget.roles) KantorChoice(r.id, r.name, r.title),
        ],
        onChanged: (v) => setState(() => _role = v),
      ),
      const SizedBox(height: GhinaSpace.md),
      KantorPickField<String>(
        label: 'Mode izin',
        value: _perm,
        options: [for (final m in kantorPermModes) KantorChoice(m.$1, m.$2)],
        onChanged: (v) => setState(() => _perm = v),
      ),
      const SizedBox(height: GhinaSpace.lg),
      ChunkyButton(
        label: 'Lanjutkan',
        onPressed: () => Navigator.of(context).pop((role: _role, perm: _perm)),
      ),
    ],
  );
}
