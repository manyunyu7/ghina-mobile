import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_states.dart';
import 'kantor_role.dart';
import 'kantor_ui.dart';

/// Playbooks: wiki pages a role follows. Agents only propose changes; the
/// owner accepts or rejects them here.

final class KantorPlaybook {
  const KantorPlaybook({
    required this.slug,
    required this.title,
    required this.icon,
    required this.roles,
    required this.when,
    required this.always,
    required this.approval,
  });

  factory KantorPlaybook.fromJson(Map<String, dynamic> j) => KantorPlaybook(
    slug: j['slug'] as String? ?? '',
    title: j['title'] as String? ?? '',
    icon: j['icon'] as String? ?? '',
    roles: [for (final r in (j['roles'] as List?) ?? const []) '$r'],
    when: j['when'] as String? ?? '',
    always: j['always'] == true,
    approval: j['approval'] == true,
  );

  final String slug;
  final String title;
  final String icon;
  final List<String> roles;
  final String when;
  final bool always;
  final bool approval;
}

final class KantorProposal {
  const KantorProposal({
    required this.id,
    required this.slug,
    required this.title,
    required this.reason,
    required this.by,
    required this.at,
  });

  factory KantorProposal.fromJson(Map<String, dynamic> j) => KantorProposal(
    id: j['id'] as String? ?? '',
    slug: j['slug'] as String? ?? '',
    title: (j['page'] ?? j['title'] ?? '') as String,
    reason: j['reason'] as String? ?? '',
    by: j['by'] as String? ?? '',
    at: j['at'] as String? ?? '',
  );

  final String id;
  final String slug;
  final String title;
  final String reason;
  final String by;
  final String at;
}

String _o(String officeId) => '/api/offices/${Uri.encodeComponent(officeId)}';

KantorApi _api(Ref ref) {
  final api = ref.watch(kantorApiProvider);
  if (api == null) {
    throw const KantorException(KantorFailure.unauthorized, 'Belum ada token');
  }
  return api;
}

final kantorPlaybooksProvider = FutureProvider.autoDispose
    .family<List<KantorPlaybook>, String>((ref, officeId) async {
      final j = await _api(ref).get('${_o(officeId)}/playbooks');
      return [
        for (final p in (j as List? ?? const []))
          if (p is Map) KantorPlaybook.fromJson(p.cast<String, dynamic>()),
      ];
    });

final kantorProposalsProvider = FutureProvider.autoDispose
    .family<List<KantorProposal>, String>((ref, officeId) async {
      final j = await _api(ref).get('${_o(officeId)}/wiki-proposals');
      return [
        for (final p in (j as List? ?? const []))
          if (p is Map) KantorProposal.fromJson(p.cast<String, dynamic>()),
      ];
    });

const kantorPlaybookTemplate = '''## Kapan dipakai
Situasi yang memicu prosedur ini.

## Sebelum mulai
- [ ] Prasyarat pertama
- [ ] Prasyarat kedua

## Langkah
1. Langkah pertama
2. Langkah kedua
3. Langkah ketiga

## Cek sesudahnya
- [ ] Apa yang harus dipastikan sudah beres

## Kalau gagal (rollback)
Cara membatalkan dan siapa yang dikabari.
''';

/// Playbooks held by [role], with a button to add one.
class KantorRolePlaybooks extends ConsumerWidget {
  const KantorRolePlaybooks({
    super.key,
    required this.officeId,
    required this.role,
  });

  final String officeId;
  final KantorRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final pbs = ref.watch(kantorPlaybooksProvider(officeId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pbs.when(
          loading: () => const Skeleton(height: 56),
          error: (e, _) => Text(
            kantorErrorText(e),
            style: GhinaType.bodyS.copyWith(color: g.textMuted),
          ),
          data: (all) {
            final mine = [
              for (final p in all)
                if (p.roles.contains(role.id)) p,
            ];
            if (mine.isEmpty) {
              return Text(
                '${role.name} belum memegang playbook.',
                style: GhinaType.body.copyWith(color: g.textMuted),
              );
            }
            return Column(
              children: [
                for (final p in mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                    child: ChunkyTile(
                      title: '${p.icon.isEmpty ? '' : '${p.icon} '}${p.title}',
                      subtitle: p.when.isEmpty ? null : p.when,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (p.always)
                            const ChunkyPill(
                              label: 'Selalu',
                              color: GhinaColors.blue,
                              soft: true,
                              uppercase: false,
                            ),
                          if (p.approval)
                            const ChunkyPill(
                              label: 'Persetujuan',
                              color: GhinaColors.orange,
                              soft: true,
                              uppercase: false,
                            ),
                        ],
                      ),
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => KantorPlaybookScreen(
                            officeId: officeId,
                            slug: p.slug,
                            title: p.title,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: GhinaSpace.sm),
        ChunkyButton(
          label: 'Playbook untuk ${role.name}',
          icon: Icons.add_rounded,
          variant: ChunkyButtonVariant.outline,
          size: ChunkyButtonSize.small,
          onPressed: () => _create(context, ref),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final title = await showChunkyDialog<String>(
      context,
      builder: (d) => ChunkyDialog(
        title: 'Playbook baru untuk ${role.name}',
        message:
            'Halaman dibuat dari template (kapan dipakai, langkah, rollback).',
        content: ChunkyTextField(
          label: 'Judul',
          hint: 'mis. Deploy web',
          controller: c,
          autofocus: true,
          maxLength: 80,
        ),
        actions: [
          ChunkyButton(
            label: 'Buat',
            onPressed: () => Navigator.of(d).pop(c.text.trim()),
          ),
          ChunkyButton(
            label: 'Batal',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(d).pop(),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !context.mounted) return;
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    String? slug;
    final ok = await kantorGuard(context, () async {
      final page = await api.post('${_o(officeId)}/wiki', {
        'title': title,
        'body': kantorPlaybookTemplate,
        'msg': 'Playbook baru dari template',
      });
      slug = (page as Map)['slug'] as String;
      await api.post('${_o(officeId)}/wiki-playbook', {
        'slug': slug,
        'roles': [role.id],
        'when': '',
        'always': false,
        'approval': false,
      });
    });
    ref.invalidate(kantorPlaybooksProvider(officeId));
    if (!ok || !context.mounted) return;
    kantorToast(context, 'Playbook dibuat. Isi langkahnya.');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            KantorPlaybookScreen(officeId: officeId, slug: slug!, title: title),
      ),
    );
    ref.invalidate(kantorPlaybooksProvider(officeId));
  }
}

/// Reads one playbook page; "Ubah" opens a plain-text editor.
class KantorPlaybookScreen extends ConsumerStatefulWidget {
  const KantorPlaybookScreen({
    super.key,
    required this.officeId,
    required this.slug,
    required this.title,
  });

  final String officeId;
  final String slug;
  final String title;

  @override
  ConsumerState<KantorPlaybookScreen> createState() => _PlaybookScreenState();
}

class _PlaybookScreenState extends ConsumerState<KantorPlaybookScreen> {
  Map<String, dynamic>? _page;
  Object? _error;
  bool _editing = false;
  bool _saving = false;
  final _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final j = await api.get(
        '${_o(widget.officeId)}/wiki/page',
        query: {'ref': widget.slug},
      );
      if (!mounted) return;
      setState(() {
        _page = (j as Map?)?.cast<String, dynamic>();
        _error = j == null
            ? const KantorException(KantorFailure.notFound, 'Halaman tidak ada')
            : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    final api = ref.read(kantorApiProvider);
    final page = _page;
    if (api == null || page == null) return;
    setState(() => _saving = true);
    final ok = await kantorGuard(context, () async {
      final r = await api.post('${_o(widget.officeId)}/wiki', {
        'title': page['title'],
        'body': _body.text,
        'msg': 'Diubah dari HP',
        'prevSlug': widget.slug,
      });
      _page = (r as Map).cast<String, dynamic>();
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _editing = false;
    });
    if (ok) kantorToast(context, 'Tersimpan');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final page = _page;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (page != null && !_editing)
            TextButton(
              onPressed: () => setState(() {
                _body.text = page['body'] as String? ?? '';
                _editing = true;
              }),
              child: const Text('Ubah'),
            ),
        ],
      ),
      body: _error != null
          ? KantorErrorView(error: _error!, onRetry: _load)
          : page == null
          ? const KantorLoading(count: 4)
          : _editing
          ? ListView(
              padding: const EdgeInsets.all(GhinaSpace.page),
              children: [
                ChunkyTextField(
                  controller: _body,
                  minLines: 12,
                  maxLines: 30,
                  label: 'Isi (markdown)',
                ),
                const SizedBox(height: GhinaSpace.lg),
                ChunkyButton(
                  label: 'Simpan',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: GhinaSpace.sm),
                ChunkyButton(
                  label: 'Batal',
                  variant: ChunkyButtonVariant.ghost,
                  onPressed: () => setState(() => _editing = false),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(GhinaSpace.page),
              children: [
                KantorMarkdown(page['body'] as String? ?? '', selectable: true),
              ],
            ),
    );
  }
}

/// New proposals from agents, with accept / reject.
class KantorProposalsSection extends ConsumerWidget {
  const KantorProposalsSection({super.key, required this.officeId});

  final String officeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(kantorProposalsProvider(officeId)).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Usulan playbook',
          subtitle: '${list.length} menunggu keputusanmu',
        ),
        for (final p in list)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
            child: ChunkyTile(
              title: p.title,
              subtitle: '${p.by}${p.reason.isEmpty ? '' : ': ${p.reason}'}',
              showChevron: true,
              tinted: GhinaColors.orange,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      KantorProposalScreen(officeId: officeId, proposal: p),
                ),
              ),
            ),
          ),
        const SizedBox(height: GhinaSpace.md),
      ],
    );
  }
}

class KantorProposalScreen extends ConsumerStatefulWidget {
  const KantorProposalScreen({
    super.key,
    required this.officeId,
    required this.proposal,
  });

  final String officeId;
  final KantorProposal proposal;

  @override
  ConsumerState<KantorProposalScreen> createState() => _ProposalScreenState();
}

class _ProposalScreenState extends ConsumerState<KantorProposalScreen> {
  String? _body;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final j = await api.get(
        '${_o(widget.officeId)}/wiki-proposals/${Uri.encodeComponent(widget.proposal.id)}',
      );
      if (mounted)
        setState(() => _body = (j as Map?)?['body'] as String? ?? '');
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _decide(bool accept) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final ok = await kantorGuard(context, () async {
      await api.post(
        '${_o(widget.officeId)}/wiki-proposals/${Uri.encodeComponent(widget.proposal.id)}',
        {'accept': accept},
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    ref.invalidate(kantorProposalsProvider(widget.officeId));
    ref.invalidate(kantorPlaybooksProvider(widget.officeId));
    kantorToast(context, accept ? 'Usulan diterima' : 'Usulan ditolak');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = widget.proposal;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: Text(p.title, overflow: TextOverflow.ellipsis)),
      body: _error != null
          ? KantorErrorView(error: _error!, onRetry: _load)
          : _body == null
          ? const KantorLoading(count: 4)
          : ListView(
              padding: const EdgeInsets.all(GhinaSpace.page),
              children: [
                Text(
                  'Usulan dari ${p.by} · ${kantorWhen(p.at)}',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                if (p.reason.isNotEmpty) ...[
                  const SizedBox(height: GhinaSpace.sm),
                  Text(
                    p.reason,
                    style: GhinaType.body.copyWith(color: g.textPrimary),
                  ),
                ],
                const SizedBox(height: GhinaSpace.lg),
                ChunkyCard(child: KantorMarkdown(_body!, selectable: true)),
                const SizedBox(height: GhinaSpace.lg),
                ChunkyButton(
                  label: 'Terima usulan',
                  loading: _busy,
                  onPressed: _busy ? null : () => _decide(true),
                ),
                const SizedBox(height: GhinaSpace.sm),
                ChunkyButton(
                  label: 'Tolak',
                  variant: ChunkyButtonVariant.danger,
                  onPressed: _busy ? null : () => _decide(false),
                ),
              ],
            ),
    );
  }
}
