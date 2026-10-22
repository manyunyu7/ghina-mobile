import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghina/presentation/features/kantor/wiki/wiki_documents.dart';
import 'package:ghina/presentation/features/kantor/wiki/wiki_markdown.dart';

void main() {
  test('legacy pdf and markdown links become preview embeds', () {
    expect(
      WikiMarkdown.prepare('[📎 laporan.pdf](/api/offices/x/media/abc)'),
      '![laporan.pdf](/api/offices/x/media/abc.pdf)',
    );
    expect(
      WikiMarkdown.prepare('[📎 catatan.md](/api/offices/x/media/abc)'),
      '![catatan.md](/api/offices/x/media/abc.md)',
    );
    expect(
      WikiMarkdown.prepare('![dok](/api/offices/x/media/abc.pdf)'),
      '![dok](/api/offices/x/media/abc.pdf)',
    );
  });

  test('uri helpers', () {
    final pdf = Uri.parse('/api/offices/kantor/media/abc.pdf');
    expect(isPdfUri(pdf), isTrue);
    expect(isDocUri(Uri.parse('/api/offices/x/media/a.markdown')), isTrue);
    expect(isDocUri(pdf), isFalse);
    expect(officeIdOf(pdf), 'kantor');
  });

  test('title and snippet', () {
    const t =
        '# Judul Besar\n\nParagraf **satu**.\n\n- item a\n```\nkode\n```\n| a | b |';
    expect(docTitle(t, 'x.md'), 'Judul Besar');
    expect(docTitle('tanpa judul', 'x.md'), 'x.md');
    expect(docSnippet(t), 'Paragraf satu.\nitem a\na b');
  });

  testWidgets('document screen renders markdown, raw toggle, no raw html', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WikiDocScreen(
          name: 'a.md',
          text:
              '# Halo\n\n<script>alert(1)</script>\n\n[x](javascript:alert(1))',
        ),
      ),
    );
    expect(find.text('Halo'), findsOneWidget);
    expect(find.byTooltip('Jadikan halaman wiki'), findsNothing); // no api
    await tester.tap(find.byTooltip('Lihat sumber'));
    await tester.pump();
    expect(find.textContaining('# Halo', findRichText: true), findsOneWidget);
  });
}
