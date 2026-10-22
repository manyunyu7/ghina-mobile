import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'kantor_feed.dart';

class AskOption {
  const AskOption(this.label, this.desc);
  final String label;
  final String desc;
}

class AskQuestion {
  const AskQuestion(this.question, this.multi, this.options);
  final String question;
  final bool multi;
  final List<AskOption> options;
}

class AskParse {
  const AskParse(this.questions, {this.partial = false, this.many = false});
  final List<AskQuestion> questions;

  /// The summary was cut at 400 characters, so only labels could be rescued.
  final bool partial;
  final bool many;

  /// A single, single-choice question with options can be answered by tapping.
  bool get tappable =>
      !many &&
      questions.length == 1 &&
      !questions[0].multi &&
      questions[0].options.isNotEmpty;
}

/// AskUserQuestion arrives as the permission summary: JSON, sometimes cut off.
AskParse parseAsk(String summary) {
  try {
    final qs = asJsonList(asJson(jsonDecode(summary))['questions']);
    return AskParse([
      for (final q in qs)
        AskQuestion(
          '${q['question'] ?? q['header'] ?? ''}',
          q['multiSelect'] == true,
          [
            for (final o in asJsonList(q['options']))
              AskOption('${o['label'] ?? ''}', '${o['description'] ?? ''}'),
          ],
        ),
    ]);
  } catch (_) {
    String un(String s) {
      try {
        return jsonDecode('"$s"') as String;
      } catch (_) {
        return s;
      }
    }

    final q = [
      for (final m in RegExp(
        r'"question"\s*:\s*"((?:[^"\\]|\\.)*)"',
      ).allMatches(summary))
        un(m[1]!),
    ];
    final labels = [
      for (final m in RegExp(
        r'"label"\s*:\s*"((?:[^"\\]|\\.)*)"',
      ).allMatches(summary))
        un(m[1]!),
    ];
    return AskParse(
      [
        AskQuestion(q.isEmpty ? '' : q.first, false, [
          for (final l in labels) AskOption(l, ''),
        ]),
      ],
      partial: true,
      many: q.length > 1,
    );
  }
}

/// A pending permission of a session: Izinkan / Tolak, or the question
/// Claude asked with its options as buttons.
class KantorPermissionCard extends StatelessWidget {
  const KantorPermissionCard({
    super.key,
    required this.item,
    required this.onDecide,
    required this.onAnswer,
    this.onSubmit,
    this.who,
    this.onOpen,
  });

  /// Inbox item: `{id, sid, tool, summary, held, who}`.
  final Json item;
  final String? who;
  final void Function(String behavior) onDecide;

  /// 1-based option number of an AskUserQuestion.
  final void Function(int n) onAnswer;

  /// Full answer of a held AskUserQuestion: `[{q, choice|choices, text, note}]`
  /// for POST /api/inbox/:id/answer. Null falls back to [onAnswer].
  final Future<void> Function(List<Json> answers)? onSubmit;

  /// Set where the card is a teaser (agents tab) instead of a full card.
  final VoidCallback? onOpen;

  bool get _ask => item['tool'] == 'AskUserQuestion';
  bool get _held => item['held'] == true;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final summary = '${item['summary'] ?? ''}';
    final children = <Widget>[
      Row(
        children: [
          Icon(
            _ask ? Icons.help_outline_rounded : Icons.shield_outlined,
            size: 18,
            color: GhinaColors.orange.edge,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _ask
                  ? '${who ?? 'Claude'} bertanya'
                  : '${who ?? 'Sesi'} minta izin ${item['tool'] ?? ''}',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
      const SizedBox(height: GhinaSpace.sm),
    ];

    final a = _ask ? parseAsk(summary) : null;
    final form = _ask &&
        _held &&
        onOpen == null &&
        onSubmit != null &&
        !a!.partial &&
        a.questions.isNotEmpty;
    if (form) {
      children.add(
        _AskForm(
          key: ValueKey('ask-${item['id']}'),
          parsed: a,
          onSubmit: onSubmit!,
        ),
      );
    } else if (_ask) {
      for (final q in a!.questions) {
        if (q.question.isNotEmpty) {
          children.add(
            Text(
              q.question,
              style: GhinaType.body.copyWith(color: g.textPrimary),
            ),
          );
          children.add(const SizedBox(height: GhinaSpace.sm));
        }
        for (var i = 0; i < q.options.length; i++) {
          final o = q.options[i];
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _AskOptionTile(
                n: i + 1,
                option: o,
                onTap: a.tappable && onOpen == null
                    ? () => onAnswer(i + 1)
                    : null,
              ),
            ),
          );
        }
      }
      if (onOpen == null) {
        children.add(
          Text(
            a.tappable
                ? 'Tombol mengetik nomor opsi ke terminal sesinya.'
                : 'Pertanyaan ini perlu dijawab di tab Terminal.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        );
      }
    } else {
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(GhinaSpace.sm),
          decoration: BoxDecoration(
            color: g.surfaceAlt,
            borderRadius: GhinaRadii.rMd,
          ),
          child: Text(
            clip(summary, onOpen == null ? 600 : 160),
            style: GhinaType.bodyS.copyWith(
              fontFamily: 'monospace',
              color: g.textPrimary,
            ),
          ),
        ),
      );
    }

    if (!_ask) {
      children.add(const SizedBox(height: GhinaSpace.md));
      children.add(
        _held
            ? Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: 'Izinkan',
                      size: ChunkyButtonSize.small,
                      onPressed: () => onDecide('allow'),
                    ),
                  ),
                  const SizedBox(width: GhinaSpace.sm),
                  Expanded(
                    child: ChunkyButton(
                      label: 'Tolak',
                      variant: ChunkyButtonVariant.outline,
                      size: ChunkyButtonSize.small,
                      onPressed: () => onDecide('deny'),
                    ),
                  ),
                ],
              )
            : Text(
                'Sudah pindah ke terminal sesinya. Jawab dari tab Terminal.',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
      );
    }

    final card = ChunkyCard(
      tinted: GhinaColors.orange,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
    return card;
  }
}

/// One answer of a question: number, label and the option's description,
/// wrapping instead of being cut to one line.
class _AskOptionTile extends StatelessWidget {
  const _AskOptionTile({
    required this.n,
    required this.option,
    this.onTap,
    this.selected = false,
  });

  final int n;
  final bool selected;
  final AskOption option;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final accent = GhinaColors.orange;
    return Material(
      color: g.surface,
      borderRadius: GhinaRadii.rMd,
      child: InkWell(
        borderRadius: GhinaRadii.rMd,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: GhinaSpace.sm,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: GhinaRadii.rMd,
            color: selected ? accent.base.withValues(alpha: .14) : null,
            border: Border.all(
              color: selected
                  ? accent.base
                  : onTap == null
                      ? g.border
                      : accent.base.withValues(alpha: .55),
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.base.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$n',
                  style: GhinaType.bodyS.w(800).copyWith(color: accent.edge),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: GhinaType.body
                          .w(700)
                          .copyWith(color: g.textPrimary),
                    ),
                    if (option.desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        option.desc,
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle_rounded, size: 20, color: accent.edge),
              ] else if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Answer form of a held AskUserQuestion: options (single or multiple), a free
/// "other" answer, an optional note per question, then one send button.
class _AskForm extends StatefulWidget {
  const _AskForm({super.key, required this.parsed, required this.onSubmit});

  final AskParse parsed;
  final Future<void> Function(List<Json> answers) onSubmit;

  @override
  State<_AskForm> createState() => _AskFormState();
}

class _AskFormState extends State<_AskForm> {
  late final List<Set<int>> _sel;
  late final List<TextEditingController> _text;
  late final List<TextEditingController> _note;
  late final List<bool> _noteOpen;
  bool _busy = false;

  List<AskQuestion> get _qs => widget.parsed.questions;

  @override
  void initState() {
    super.initState();
    _sel = [for (final _ in _qs) <int>{}];
    _text = [for (final _ in _qs) TextEditingController()];
    _note = [for (final _ in _qs) TextEditingController()];
    _noteOpen = [for (final _ in _qs) false];
  }

  @override
  void dispose() {
    for (final c in [..._text, ..._note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pick(int qi, int k) {
    setState(() {
      final s = _sel[qi];
      if (_qs[qi].multi) {
        s.contains(k) ? s.remove(k) : s.add(k);
      } else if (s.contains(k)) {
        s.clear();
      } else {
        s
          ..clear()
          ..add(k);
        _text[qi].clear();
      }
    });
  }

  bool get _ready => [
    for (var i = 0; i < _qs.length; i++)
      _sel[i].isNotEmpty || _text[i].text.trim().isNotEmpty,
  ].every((x) => x);

  Future<void> _send() async {
    final answers = <Json>[
      for (var i = 0; i < _qs.length; i++)
        {
          'q': i,
          if (_qs[i].multi)
            'choices': ([..._sel[i]]..sort()).map((k) => k + 1).toList()
          else if (_sel[i].isNotEmpty)
            'choice': _sel[i].first + 1,
          'text': _text[i].text.trim(),
          'note': _note[i].text.trim(),
        },
    ];
    setState(() => _busy = true);
    try {
      await widget.onSubmit(answers);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(BuildContext context, String hint) {
    final g = context.ghina;
    return InputDecoration(
      hintText: hint,
      hintStyle: GhinaType.bodyS.copyWith(color: g.textMuted),
      isDense: true,
      filled: true,
      fillColor: g.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.sm,
        vertical: 10,
      ),
      border: OutlineInputBorder(
        borderRadius: GhinaRadii.rMd,
        borderSide: BorderSide(color: g.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: GhinaRadii.rMd,
        borderSide: BorderSide(color: g.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: GhinaRadii.rMd,
        borderSide: BorderSide(color: GhinaColors.orange.base, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var qi = 0; qi < _qs.length; qi++) ...[
          if (qi > 0) const SizedBox(height: GhinaSpace.md),
          if (_qs[qi].question.isNotEmpty)
            Text(
              _qs[qi].multi
                  ? '${_qs[qi].question} (boleh pilih lebih dari satu)'
                  : _qs[qi].question,
              style: GhinaType.body.copyWith(color: g.textPrimary),
            ),
          const SizedBox(height: GhinaSpace.sm),
          for (var k = 0; k < _qs[qi].options.length; k++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _AskOptionTile(
                n: k + 1,
                option: _qs[qi].options[k],
                selected: _sel[qi].contains(k),
                onTap: _busy ? null : () => _pick(qi, k),
              ),
            ),
          TextField(
            controller: _text[qi],
            enabled: !_busy,
            style: GhinaType.bodyS.copyWith(color: g.textPrimary),
            decoration: _deco(context, 'Jawaban lain (ketik sendiri)'),
            onChanged: (v) => setState(() {
              if (v.isNotEmpty && !_qs[qi].multi) _sel[qi].clear();
            }),
          ),
          const SizedBox(height: 6),
          if (_noteOpen[qi])
            TextField(
              controller: _note[qi],
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              decoration: _deco(context, 'Catatan tambahan (opsional)'),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => setState(() => _noteOpen[qi] = true),
                child: Text(
                  '+ Tambah catatan',
                  style: GhinaType.caption.copyWith(
                    color: g.textMuted,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: GhinaSpace.md),
        SizedBox(
          width: double.infinity,
          child: ChunkyButton(
            label: _busy ? 'Mengirim...' : 'Kirim jawaban',
            size: ChunkyButtonSize.small,
            onPressed: _ready && !_busy ? _send : null,
          ),
        ),
      ],
    );
  }
}
