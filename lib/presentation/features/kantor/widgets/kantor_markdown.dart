import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../design_system/design_system.dart';

/// Intrinsic table column that never breaks a word (min = longest word) and
/// wraps text beyond [cap]; wider tables scroll horizontally in their own box
/// (flutter_markdown wraps `IntrinsicColumnWidth` tables in a horizontal
/// scroll view).
class KantorColumnWidth extends IntrinsicColumnWidth {
  const KantorColumnWidth({this.cap = 260});

  final double cap;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final max = super.maxIntrinsicWidth(cells, containerWidth);
    final min = minIntrinsicWidth(cells, containerWidth);
    return max > cap ? (cap < min ? min : cap) : max;
  }
}

/// Table look shared by every Kantor markdown renderer: bold header, tidy
/// borders, scrollable intrinsic columns.
MarkdownStyleSheet kantorTableSheet(
  MarkdownStyleSheet sheet,
  GhinaTokens g,
  TextStyle body,
) => sheet.copyWith(
  tableBody: body,
  tableHead: body.copyWith(fontWeight: FontWeight.w800),
  tableHeadAlign: TextAlign.left,
  tableBorder: TableBorder.all(color: g.border, width: 1),
  tableColumnWidth: const KantorColumnWidth(),
  tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  tableHeadCellsDecoration: BoxDecoration(color: g.surfaceAlt),
  tableScrollbarThumbVisibility: true,
  tablePadding: const EdgeInsets.only(bottom: 4),
);

/// Markdown body for wiki pages, notes and cards. `[[Judul]]` wiki links are
/// shown as plain emphasised text.
class KantorMarkdown extends StatelessWidget {
  const KantorMarkdown(
    this.text, {
    super.key,
    this.selectable = false,
    this.lineHeight = 1.45,
    this.codeScale = 1,
    this.wrapCode = false,
  });

  final String text;
  final bool selectable;

  /// Line height of paragraphs and lists.
  final double lineHeight;

  /// Multiplier for inline code and code blocks on top of the text scale.
  final double codeScale;

  /// Code blocks wrap long lines instead of scrolling sideways.
  final bool wrapCode;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final base = Theme.of(context).textTheme;
    final body = GhinaType.body.copyWith(color: g.textPrimary, height: lineHeight);
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      h1: GhinaType.h2.copyWith(color: g.textPrimary),
      h2: GhinaType.h3.copyWith(color: g.textPrimary),
      h3: GhinaType.body.w(800).copyWith(color: g.textPrimary),
      listBullet: body,
      blockquote: body.copyWith(color: g.textSecondary),
      code: (base.bodyMedium ?? body).copyWith(
        fontFamily: 'monospace',
        fontSize: 13 * codeScale,
        color: g.textPrimary,
        backgroundColor: g.surfaceAlt,
      ),
      codeblockDecoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: g.border),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: g.border, width: 3)),
      ),
    );
    final styled = kantorTableSheet(sheet, g, body);
    final src = text.replaceAllMapped(
      RegExp(r'\[\[([^\]]+)\]\]'),
      (m) => '**${m[1]}**',
    );
    return MarkdownBody(
      data: src,
      styleSheet: styled,
      selectable: selectable,
      shrinkWrap: true,
      builders: wrapCode
          ? {'pre': _WrapCodeBuilder(styled, selectable)}
          : const {},
    );
  }
}

/// Code block that wraps long lines (the default scrolls sideways).
class _WrapCodeBuilder extends MarkdownElementBuilder {
  _WrapCodeBuilder(this.sheet, this.selectable);

  final MarkdownStyleSheet sheet;
  final bool selectable;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    // md.Element; the markdown package is not a direct dependency
    Object element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var code = '${(element as dynamic).textContent}';
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    final style = sheet.code?.copyWith(backgroundColor: Colors.transparent);
    return Container(
      width: double.infinity,
      padding: sheet.codeblockPadding ?? const EdgeInsets.all(8),
      decoration: sheet.codeblockDecoration,
      child: selectable
          ? SelectableText(code, style: style)
          : Text(code, style: style, softWrap: true),
    );
  }
}
