import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../email_state.dart';

/// "Aturan Killa" (`/email/rules`): senders / subject keywords that are
/// always important or always skipped. Killa adds rules here too when asked
/// in chat.
class EmailRulesPage extends ConsumerStatefulWidget {
  const EmailRulesPage({super.key});

  @override
  ConsumerState<EmailRulesPage> createState() => _EmailRulesPageState();
}

class _EmailRulesPageState extends ConsumerState<EmailRulesPage> {
  /// Rules deleted here and not refetched yet.
  final Set<String> _hidden = {};
  bool _adding = false;

  Future<void> _add() async {
    final input = await showChunkyBottomSheet<EmailRuleInput>(
      context,
      title: 'Aturan baru',
      showClose: true,
      builder: (_) => const _RuleSheet(),
    );
    if (input == null || !mounted) return;
    await _create(input, toast: 'Aturan disimpan');
  }

  Future<void> _create(EmailRuleInput input, {String? toast}) async {
    setState(() => _adding = true);
    try {
      await ref.read(addEmailRuleProvider)(input);
      if (!mounted) return;
      if (toast != null) showOkToast(context, toast);
      ref.invalidate(emailRulesProvider);
    } on EmailException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(EmailTriageRule r) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(r.id));
    try {
      await ref.read(deleteEmailRuleProvider)(r.id);
    } on EmailException catch (e) {
      if (!mounted) return;
      setState(() => _hidden.remove(r.id));
      showErrorToast(context, e.message);
      return;
    }
    if (!mounted) return;
    ref.invalidate(emailRulesProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Aturan "${r.pattern}" dihapus'),
        duration: const Duration(seconds: 4),
        persist: false,
        action: SnackBarAction(
          label: 'BATAL',
          // The server gives the restored rule a new id.
          onPressed: () => _create(
            EmailRuleInput(
              kind: r.kind,
              match: r.match,
              pattern: r.pattern,
              note: r.note,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(emailRulesProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Aturan Killa')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('rules-add'),
        onPressed: _adding ? null : _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah aturan'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _hidden.clear();
          return ref.refresh(emailRulesProvider.future);
        },
        child: switch (async) {
          AsyncData(:final value) => _list([
            for (final r in value)
              if (!_hidden.contains(r.id)) r,
          ]),
          AsyncError(:final error) => EmailErrorView(
            error: error,
            onRetry: () => ref.invalidate(emailRulesProvider),
          ),
          _ => const LoadingListView(hero: false, tiles: 3),
        },
      ),
    );
  }

  Widget _list(List<EmailTriageRule> rules) {
    final g = context.ghina;
    final intro = Text(
      'Killa nilai tiap email sendiri. Aturan ini menang: "Selalu penting" '
      'minimal masuk Penting, "Abaikan" dilewati tanpa dibaca AI.',
      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
    );
    if (rules.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          8,
          GhinaSpace.page,
          96,
        ),
        children: [
          intro,
          const SizedBox(height: 8),
          const EmptyState(
            key: Key('rules-empty'),
            compact: true,
            mascotSize: 90,
            title: 'Belum ada aturan',
            message:
                'Contoh:\n'
                '• Selalu penting: kampus.ac.id\n'
                '• Selalu penting: kata kunci "tagihan"\n'
                '• Abaikan: newsletter@tokopedia.com\n\n'
                'Bisa juga bilang ke Killa: "email dari X nggak usah '
                'dikabari".',
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        96,
      ),
      children: [
        intro,
        const SizedBox(height: 12),
        for (final r in rules) ...[
          _RuleTile(rule: r, onDelete: () => _delete(r)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule, required this.onDelete});

  final EmailTriageRule rule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = rule;
    final always = r.kind == EmailRuleKind.always;
    final sw = always ? GhinaColors.orange : GhinaColors.gray;
    final note = r.note;
    return ChunkyCard(
      key: Key('rule-${r.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryAvatar(
            icon: always
                ? Icons.priority_high_rounded
                : Icons.notifications_off_rounded,
            color: sw.base,
            size: 40,
            soft: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.pattern,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ChunkyPill(
                      label: r.kind.label,
                      color: sw,
                      soft: true,
                      uppercase: false,
                    ),
                    ChunkyPill(
                      label: r.match.label,
                      icon: r.match == EmailRuleMatch.sender
                          ? Icons.alternate_email_rounded
                          : Icons.title_rounded,
                      color: GhinaColors.blue,
                      soft: true,
                      uppercase: false,
                    ),
                  ],
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: Key('rule-delete-${r.id}'),
            tooltip: 'Hapus',
            icon: Icon(Icons.delete_outline_rounded, color: g.textMuted),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// The add-rule sheet: always / never, sender / keyword, the pattern and an
/// optional note. Pops an [EmailRuleInput].
class _RuleSheet extends StatefulWidget {
  const _RuleSheet();

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  EmailRuleKind _kind = EmailRuleKind.always;
  EmailRuleMatch _match = EmailRuleMatch.sender;
  final _pattern = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pattern.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) {
      setState(
        () => _error = _match == EmailRuleMatch.sender
            ? 'Isi alamat atau domain pengirimnya.'
            : 'Isi kata kuncinya.',
      );
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(
      EmailRuleInput(
        kind: _kind,
        match: _match,
        pattern: pattern,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sender = _match == EmailRuleMatch.sender;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChunkySegmented<EmailRuleKind>(
          key: const Key('rule-kind'),
          segments: const [
            ChunkySegment(
              value: EmailRuleKind.always,
              label: 'Selalu penting',
              color: GhinaColors.orange,
            ),
            ChunkySegment(
              value: EmailRuleKind.never,
              label: 'Abaikan',
              color: GhinaColors.gray,
            ),
          ],
          value: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 12),
        ChunkySegmented<EmailRuleMatch>(
          key: const Key('rule-match'),
          segments: [
            ChunkySegment(
              value: EmailRuleMatch.sender,
              label: 'Pengirim',
              icon: Icons.alternate_email_rounded,
              color: g.accent,
            ),
            ChunkySegment(
              value: EmailRuleMatch.keyword,
              label: 'Kata kunci',
              icon: Icons.title_rounded,
              color: g.accent,
            ),
          ],
          value: _match,
          onChanged: (m) => setState(() {
            _match = m;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        ChunkyTextField(
          key: const Key('rule-pattern'),
          controller: _pattern,
          label: sender ? 'Alamat atau domain' : 'Kata kunci di subjek',
          hint: sender ? 'mis. kampus.ac.id' : 'mis. tagihan',
          keyboardType: sender ? TextInputType.emailAddress : null,
          maxLength: 200,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const Key('rule-note'),
          controller: _note,
          label: 'Catatan (opsional)',
          hint: 'mis. email dosen pembimbing',
          maxLength: 200,
        ),
        const SizedBox(height: 8),
        Text(
          _kind == EmailRuleKind.always
              ? 'Email yang cocok minimal masuk "Penting".'
              : 'Email yang cocok dilewati, nggak dibaca dan nggak dikabari.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          key: const Key('rule-submit'),
          label: 'Simpan aturan',
          onPressed: _submit,
        ),
      ],
    );
  }
}
