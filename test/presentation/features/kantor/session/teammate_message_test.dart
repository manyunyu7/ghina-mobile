import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/teammate_card.dart';
import 'package:ghina/presentation/features/kantor/session/teammate_message.dart';

void main() {
  group('teammateMsgs', () {
    test('ordinary text is not an inter-session message', () {
      expect(teammateMsgs('halo, tolong cek ini'), isNull);
      expect(teammateMsgs(null), isNull);
      expect(teammateMsgs(''), isNull);
    });

    test('plain body: sender, color, summary from the tag', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="budi-contoh" color="blue" summary="Hasil cek">Semua lolos.</teammate-message>',
      )!;
      expect(m, hasLength(1));
      expect(m.single.from, 'budi-contoh');
      expect(m.single.color, 'blue');
      expect(m.single.summary, 'Hasil cek');
      expect(m.single.body, 'Semua lolos.');
      expect(m.single.kind, 'pesan');
    });

    test('without a summary the first line of the body is the preview', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="sari-contoh">\n\n## **Ringkasan** `tes`\nIsi panjang\n</teammate-message>',
      )!.single;
      expect(m.summary, 'Ringkasan tes');
      expect(m.body, startsWith('## **Ringkasan**'));
    });

    test('the preview is cut at 160 characters', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="a">${'x' * 400}</teammate-message>',
      )!.single;
      expect(m.summary.length, 160);
    });

    test('JSON idle_notification: kind, summary and result', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="agen-1" color="green">'
        '{"type":"idle_notification","from":"Dewi Contoh","summary":"Selesai rapikan","result":"Sudah dirapikan semua."}'
        '</teammate-message>',
      )!.single;
      expect(m.from, 'Dewi Contoh');
      expect(m.kind, 'selesai');
      expect(m.summary, 'Selesai rapikan');
      expect(m.body, 'Sudah dirapikan semua.');
      expect(m.color, 'green');
    });

    test('known and unknown JSON types become Indonesian / spaced words', () {
      String kind(String type) => teammateMsgs(
        '<teammate-message teammate_id="a">{"type":"$type","message":"x"}</teammate-message>',
      )!.single.kind;
      expect(kind('shutdown_request'), 'minta berhenti');
      expect(kind('shutdown_response'), 'berhenti');
      expect(kind('task_assignment'), 'tugas baru');
      expect(kind('plan_approval_request'), 'plan approval request');
    });

    test('a non-string JSON body is pretty printed', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="a">{"type":"x","content":{"a":1}}</teammate-message>',
      )!.single;
      expect(m.body, '{\n  "a": 1\n}');
    });

    test('cut-off JSON and an unclosed tag are shown as they are', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="a">{"type":"idle_notif',
      )!.single;
      expect(m.body, '{"type":"idle_notif');
      expect(m.kind, 'pesan');
    });

    test('several messages in one prompt', () {
      final m = teammateMsgs(
        '<teammate-message teammate_id="a">satu</teammate-message>\n'
        '<teammate-message teammate_id="b">dua</teammate-message>',
      )!;
      expect([for (final x in m) x.from], ['a', 'b']);
    });

    test('no teammate_id falls back to "sesi lain"', () {
      expect(
        teammateMsgs('<teammate-message>hai</teammate-message>')!.single.from,
        'sesi lain',
      );
    });
  });

  group('teammateRest', () {
    test('owner words outside the tag stay', () {
      expect(
        teammateRest(
          '<teammate-message teammate_id="a">isi</teammate-message>\n\nTolong lanjutkan ya',
        ),
        'Tolong lanjutkan ya',
      );
    });

    test('nothing left when the prompt is only the message', () {
      expect(
        teammateRest(
          'Another Claude session sent a message:\n<teammate-message teammate_id="a">isi</teammate-message>',
        ),
        '',
      );
    });

    test('pasted_content wrappers are dropped', () {
      expect(
        teammateRest(
          '<pasted_content>Catatan Budi Contoh</pasted_content> <teammate-message teammate_id="a">x</teammate-message>',
        ),
        'Catatan Budi Contoh',
      );
    });

    test('plain text is returned trimmed', () {
      expect(teammateRest('  halo  '), 'halo');
    });
  });

  testWidgets('TeammateCard: sender, kind and summary; body opens and closes', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final msg = teammateMsgs(
      '<teammate-message teammate_id="budi-contoh" color="purple">'
      '{"type":"idle_notification","summary":"Selesai uji","result":"Detail **lengkap** hasil uji."}'
      '</teammate-message>',
    )!.single;
    await t.pumpWidget(
      MaterialApp(
        theme: GhinaTheme.light(),
        home: Scaffold(
          body: TeammateCard(
            msg: msg,
            at: '2026-11-12T09:41:00Z',
            view: const ChatViewPrefs(),
          ),
        ),
      ),
    );
    expect(find.text('budi-contoh'), findsOneWidget);
    expect(find.text('SELESAI'), findsOneWidget);
    expect(find.text('Selesai uji'), findsOneWidget);
    expect(find.textContaining('Detail'), findsNothing);
    await t.tap(find.byKey(const ValueKey('teammate-toggle')));
    await t.pump();
    expect(find.textContaining('Detail', findRichText: true), findsOneWidget);
    expect(find.text('Tutup isi'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('teammate-toggle')));
    await t.pump();
    expect(find.textContaining('Detail', findRichText: true), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('TeammateCard on a narrow screen with a long summary', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final msg = TeammateMsg(
      from: 'nama-sesi-yang-sangat-panjang-sekali-contoh',
      color: '',
      summary: 'Ringkasan ' * 30,
      body: 'isi',
      kind: 'pesan',
    );
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: TeammateCard(
              msg: msg,
              at: '',
              view: const ChatViewPrefs(bubbleWidth: ChatBubbleWidth.wide),
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
