import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_active_agents.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_konteks.dart';

Map<String, dynamic> _sess(Object? konteks, {Map<String, dynamic>? extra}) => {
  'sid': 's1',
  'status': 'working',
  'look': {'name': 'Zora'},
  if (konteks != null) 'konteks': konteks,
  ...?extra,
};

const _long =
    'Topik yang sangat panjang sekali untuk menguji pemotongan teks di layar sempit tiga ratus enam puluh dp';

void main() {
  test('parsing aman untuk konteks kosong atau rusak', () {
    expect(KantorKonteks.fromJson(null), isNull);
    expect(KantorKonteks.fromJson('x'), isNull);
    expect(KantorKonteks.fromJson(<String, dynamic>{}), isNull);
    expect(KantorKonteks.ofSession(_sess(null)), isNull);
    final k = KantorKonteks.fromJson({
      'topic': null,
      'ask': {'s': '', 'from': 'kamu'},
      'reply': 5,
      'files': {
        'names': [1, null, 'a.dart'],
        'n': 3,
      },
      'state': {'k': 'selesai'},
    })!;
    expect(k.topic, isNull);
    expect(k.ask, isNull);
    expect(k.reply, isNull);
    expect(k.fileNames, ['1', 'a.dart']);
    expect(k.fileCount, 3);
    expect(k.stateLabel, 'selesai');
  });

  test('detail per keadaan', () {
    final izin = KantorKonteks.fromJson({
      'state': {'k': 'izin', 'label': 'Nunggu izinmu'},
    })!;
    expect(
      izin.detail({
        'waiting': {'summary': 'rm -rf x'},
      }),
      'rm -rf x',
    );
    final tanya = KantorKonteks.fromJson({
      'reply': {'s': 'a', 'q': 'Lanjut?'},
      'state': {'k': 'tanya', 'label': 'x'},
    })!;
    expect(tanya.detail({}), 'Lanjut?');
    final idle = KantorKonteks.fromJson({
      'reply': {'s': 'Beres'},
      'state': {'k': 'selesai', 'label': 'x'},
    })!;
    expect(idle.detail({}), 'Beres');
  });

  for (final (withKonteks, withLabel) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      'baris 360dp tanpa overflow (konteks=$withKonteks, label=$withLabel)',
      (t) async {
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final s = _sess(
          withKonteks
              ? {
                  'topic': _long,
                  'reply': {'s': _long, 'q': _long},
                  'state': {'k': 'tanya', 'label': 'Nunggu jawabanmu'},
                  if (withLabel) 'label': {'text': '$_long $_long'},
                  if (withLabel) 'auto': _long,
                }
              : null,
        );
        final ref = KantorAgentRef({'id': 'o', 'name': 'Kantor'}, s);
        await t.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(extensions: [GhinaTokens.light]),
              home: Scaffold(
                body: ListView(
                  children: [
                    if (withKonteks) KantorKonteksBar(session: s),
                    KantorActiveAgentTile(agent: ref, onOpen: (_) {}),
                    SizedBox(
                      height: 92,
                      child: KantorKonteksLines(
                        session: s,
                        fallback: ref.doing,
                        showTopic: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (withKonteks) {
          await t.tap(find.byKey(const ValueKey('konteks-toggle')));
          await t.pump();
          expect(find.text('DIA NANYA'), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      },
    );
  }

  test('label pemilik dibaca bersama judul otomatis', () {
    final k = KantorKonteks.fromJson({
      'topic': 'Audit atap',
      'auto': 'Memeriksa atap YK',
      'label': {'text': 'Audit atap', 'scope': 'role', 'tell': true},
      'state': {'k': 'jalan', 'label': 'Lagi jalan'},
    })!;
    expect(k.label, 'Audit atap');
    expect(k.labelForRole, isTrue);
    expect(k.labelTell, isTrue);
    expect(k.auto, 'Memeriksa atap YK');
    final none = KantorKonteks.fromJson({
      'auto': 'x',
      'label': {'text': ''},
      'state': {'k': 'jalan'},
    })!;
    expect(none.label, isNull);
    expect(none.auto, isNull);
  });

  testWidgets('tombol label membuka form dan menyimpan lewat onLabel', (
    t,
  ) async {
    final s = _sess(
      {
        'topic': 'Audit atap',
        'auto': 'Memeriksa atap YK',
        'label': {'text': 'Audit atap', 'scope': 'sesi'},
        'state': {'k': 'jalan', 'label': 'Lagi jalan'},
      },
      extra: {'role': 'kuli'},
    );
    final saved = <List<Object>>[];
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(extensions: [GhinaTokens.light]),
          home: Scaffold(
            body: Column(
              children: [
                KantorKonteksBar(
                  session: s,
                  onLabel: (text, carry, tell) async =>
                      saved.add([text, carry, tell]),
                ),
                KantorKonteksLines(session: s, fallback: 'x'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(KantorLabelSticker), findsNWidgets(2));
    expect(find.text('Audit atap'), findsNWidgets(2));
    await t.tap(find.byKey(const ValueKey('konteks-toggle')));
    await t.pump();
    expect(find.text('LABEL KAMU'), findsOneWidget);
    expect(find.text('Untuk sesi ini saja'), findsOneWidget);
    expect(find.text('JUDUL OTOMATIS'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('konteks-label')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('label-carry')), findsOneWidget);
    expect(find.byKey(const ValueKey('label-delete')), findsOneWidget);
    await t.enterText(find.byType(TextField), '  Audit atap Jogja ');
    await t.tap(find.byKey(const ValueKey('label-carry')));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('label-save')));
    await t.tap(find.byKey(const ValueKey('label-save')));
    await t.pumpAndSettle();
    expect(saved, [
      ['Audit atap Jogja', true, false],
    ]);
    expect(t.takeException(), isNull);
  });
}
