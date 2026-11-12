import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/compact_card.dart';
import 'package:ghina/presentation/features/kantor/session/compact_summary.dart';

const _sum =
    'This session is being continued from a previous conversation that ran out of context. The summary below covers the earlier portion of the conversation.\n\n'
    '<system-reminder>\nx\n</system-reminder>\nSummary:\n'
    '1. Primary Request and Intent:\n   - Pemilik minta cek **foto** yang lolos.\n\n'
    '2. Key Technical Concepts:\n   - Laravel';

void main() {
  test(
    'pengantar dan system-reminder dibuang, pratinjau dari permintaan utama',
    () {
      final c = compactSummary(_sum)!;
      expect(c.body.startsWith('1. Primary Request and Intent:'), isTrue);
      expect(c.body.contains('system-reminder'), isFalse);
      expect(c.preview, 'Pemilik minta cek foto yang lolos.');
      expect(c.rest, '');
      expect(compactSummary('tolong cek foto'), isNull);
    },
  );

  test('ditempel setelah kalimat pemilik: kalimatnya tetap jadi pesan', () {
    final c = compactSummary(
      'ini juga baiknya jadi kartu\n\n<pasted_content id="1">\n$_sum\n</pasted_content>',
    )!;
    expect(c.rest, 'ini juga baiknya jadi kartu');
    expect(c.preview, 'Pemilik minta cek foto yang lolos.');
  });

  testWidgets('kartu: judul, pratinjau, ringkasan dilipat', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: GhinaTheme.light(),
        home: Scaffold(
          body: CompactCard(
            msg: compactSummary(_sum)!,
            at: '2026-11-12T09:41:00Z',
            view: const ChatViewPrefs(),
          ),
        ),
      ),
    );
    expect(find.text('Percakapan dilanjutkan'), findsOneWidget);
    expect(find.text('KONTEKS DIRINGKAS OTOMATIS'), findsOneWidget);
    expect(find.text('Pemilik minta cek foto yang lolos.'), findsOneWidget);
    expect(
      find.textContaining('Key Technical', findRichText: true),
      findsNothing,
    );
    await t.tap(find.byKey(const ValueKey('compact-toggle')));
    await t.pump();
    expect(
      find.textContaining('Key Technical', findRichText: true),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
