import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/konten/konten_data.dart';
import 'package:ghina/presentation/features/kantor/konten/konten_media.dart';
import 'package:ghina/presentation/features/kantor/konten/konten_model.dart';
import 'package:ghina/presentation/features/kantor/konten/konten_package_page.dart';
import 'package:ghina/presentation/features/kantor/konten/konten_tab.dart';

Map<String, dynamic> _raw(String id, String tahap, [Map<String, dynamic>? x]) =>
    {
      'id': id,
      'title': 'Post $id dengan judul yang cukup panjang supaya terpotong rapi',
      'tahap': tahap,
      'tahapNama': tahap == 'review' ? 'Review kamu' : tahap,
      'jenis': 'carousel',
      'coverUrl': null,
      'platforms': <String, dynamic>{},
      ...?x,
    };

class FakeRepo implements KontenRepo {
  FakeRepo({this.unsupported = false});
  final bool unsupported;
  final calls = <String>[];
  var items = [
    _raw('a', 'review', {'updatedAt': '2026-11-02T10:00:00Z', 'sensitif': 1}),
    _raw('b', 'siap'),
    _raw('c', 'terjadwal', {
      'publishAt': '2026-11-10',
      'jam': '19:00',
      'jadwalStatus': 'usulan',
    }),
  ];

  @override
  Uri uri(String url) => Uri.parse('http://x.test').resolve(url);
  @override
  Map<String, String> get headers => const {'Authorization': 'Bearer t'};
  @override
  Uri webUrl(String office, String sub) => Uri.parse('http://x.test/#/$sub');

  @override
  Future<KontenList> list(String office) async => unsupported
      ? const KontenList(unsupported: true)
      : KontenList.fromJson({
          'items': items,
          'stages': [
            {'id': 'review', 'name': 'Review kamu', 'n': 1},
            {'id': 'siap', 'name': 'Siap tayang', 'n': 1},
          ],
        });

  @override
  Future<KontenItem> get(String office, String id) async =>
      KontenItem.fromJson({
        ..._raw(id, 'siap'),
        'media': {
          'slides': [
            {'rel': 'out/slide-1.png', 'name': 'slide-1.png', 'url': '/f1'},
            {'rel': 'out/slide-2.png', 'name': 'slide-2.png', 'url': '/f2'},
          ],
        },
        'captions': {'instagram': 'Caption IG', 'threads': null},
        'platformTarget': ['instagram', 'threads'],
        'lagu': 'Lagu santai',
      });

  @override
  Future<KontenJadwal> jadwal(String office) async => unsupported
      ? const KontenJadwal(unsupported: true)
      : KontenJadwal.fromJson({
          'items': [items[2]],
          'peringatan': [
            {'kode': 'tanpa-caption', 'pesan': 'Satu post belum punya caption'},
          ],
          'minggu': [
            {'mulai': '2026-11-09', 'n': 1, 'target': 5},
          ],
        });

  @override
  Future<void> review(
    String office,
    String id, {
    required bool setuju,
    String? catatan,
  }) async => calls.add('review:$id:$setuju:$catatan');
  @override
  Future<void> setujuiJadwal(String office, List<String> ids) async =>
      calls.add('setujui:${ids.join(',')}');
  @override
  Future<void> setTanggal(
    String office,
    String id, {
    String? publishAt,
    String? jam,
  }) async => calls.add('tanggal:$id:$publishAt');
  @override
  Future<List<String>> tayang(
    String office,
    String id,
    String platform, {
    String? link,
  }) async {
    calls.add('tayang:$id:$platform:$link');
    return const [];
  }

  @override
  Future<void> performa(
    String office,
    String id,
    String platform,
    Map<String, int> angka,
  ) async => calls.add('performa:$platform:${angka['reach']}');
}

class FakeMedia implements KontenMedia {
  final log = <String>[];
  @override
  Future<List<String>> fetchAll(
    KontenRepo repo,
    String cid,
    List<KontenFile> files, {
    void Function(int, int)? onProgress,
  }) async {
    log.add('fetch:${files.length}');
    return [for (final f in files) '/tmp/${f.name}'];
  }

  @override
  Future<bool> saveToGallery(List<String> paths) async {
    log.add('gallery:${paths.length}');
    return true;
  }

  @override
  Future<void> share(List<String> paths, {String? text}) async =>
      log.add('share:${paths.length}');
}

Widget _app(KontenRepo repo, Widget home, {FakeMedia? media}) => ProviderScope(
  overrides: [
    kontenRepoProvider.overrideWithValue(repo),
    kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
    if (media != null) kontenMediaProvider.overrideWithValue(media),
  ],
  child: MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: home),
  ),
);

/// Maskot keadaan kosong beranimasi terus, jadi pumpAndSettle tidak selesai.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  test('parsing tahan field kosong, hilang, dan bertipe lain', () {
    final empty = KontenItem.fromJson(const {});
    expect(empty.title, 'Tanpa judul');
    expect(empty.media.isEmpty, isTrue);
    expect(empty.targets, contains('youtube'));

    final odd = KontenItem.fromJson({
      'id': 7,
      'title': null,
      'jenis': 'carousel',
      'sensitif': 1,
      'platforms': {
        'instagram': {'link': '', 'at': null},
      },
      'perf': {
        'instagram': {'reach': 12, 'like': 'x'},
      },
      'media': {
        'slides': [
          null,
          {'rel': 'a/b.png'},
        ],
        'video': 'bukan map',
      },
      'captions': {'instagram': '', 'tiktok': 'tt'},
      'publishAt': '2026-11-10T00:00:00Z',
    });
    expect(odd.id, '7');
    expect(odd.sensitif, isTrue);
    expect(odd.platforms['instagram']!.link, isNull);
    expect(odd.perf['instagram'], {'reach': 12});
    expect(odd.media.slides.single.name, 'b.png');
    expect(odd.media.video, isNull);
    expect(odd.captions, {'tiktok': 'tt'});
    expect(odd.tanggal, DateTime(2026, 11, 10));
    expect(odd.targets, isNot(contains('youtube')));

    expect(KontenList.fromJson(null).items, isEmpty);
    expect(KontenJadwal.fromJson('x').peringatan, isEmpty);
  });

  testWidgets('galeri 360dp tanpa overflow, filter tahap, buka paket', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(FakeRepo(), const KantorKontenTab(officeId: 'o')),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('konten-a')), findsOneWidget);
    expect(find.text('Review 1'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('tahap-review')),
      const Offset(-300, 0),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('tahap-siap')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('konten-a')), findsNothing);
    expect(find.byKey(const ValueKey('konten-b')), findsOneWidget);

    await tester.tap(find.text('Review 1'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('konten-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('konten-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server lama (404) tampil sebagai keadaan kosong ramah', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(FakeRepo(unsupported: true), const KantorKontenTab(officeId: 'o')),
    );
    await _settle(tester);
    expect(find.text('Konten belum aktif di kantor ini'), findsOneWidget);
    await tester.tap(find.text('Jadwal'));
    await _settle(tester);
    expect(find.text('Konten belum aktif di kantor ini'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jadwal: peringatan, usulan, setujui, ganti tanggal', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepo();
    await tester.pumpWidget(_app(repo, const KantorKontenTab(officeId: 'o')));
    await _settle(tester);
    await tester.tap(find.text('Jadwal'));
    await _settle(tester);
    expect(find.text('Satu post belum punya caption'), findsOneWidget);
    expect(find.text('USULAN'), findsOneWidget);
    expect(find.text('SETUJUI 1 USULAN'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('setujui-semua')));
    await _settle(tester);
    expect(repo.calls, contains('setujui:c'));

    await tester.tap(find.byKey(const ValueKey('tanggal-c')));
    await _settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(repo.calls.where((c) => c.startsWith('tanggal:c:')), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paket posting: simpan galeri, bagikan, salin, tandai tayang', (
    tester,
  ) async {
    _phone(tester);
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = FakeRepo();
    final media = FakeMedia();
    await tester.pumpWidget(
      _app(
        repo,
        const KontenPackagePage(officeId: 'o', itemId: 'b'),
        media: media,
      ),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Slide 1 dari 2'), findsOneWidget);

    await tester.tap(find.text('SIMPAN SEMUA KE GALERI'));
    await _settle(tester);
    expect(media.log, ['fetch:2', 'gallery:2']);
    expect(find.text('2 berkas masuk galeri'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.text('BAGIKAN'));
    await _settle(tester);
    expect(media.log.last, 'share:2');

    await tester.scrollUntilVisible(
      find.text('Saran lagu: Lagu santai'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final salin = find.byKey(const ValueKey('salin-instagram'));
    await tester.scrollUntilVisible(
      salin,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Caption IG'), findsOneWidget);
    await tester.tap(salin);
    await _settle(tester);
    expect(clip, 'Caption IG');
    expect(find.text('Caption Instagram disalin'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    final tandai = find.byKey(const ValueKey('tandai-instagram'));
    await tester.scrollUntilVisible(
      tandai,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tandai);
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('konten-note')),
      'https://instagram.com/p/abc',
    );
    await tester.tap(find.byKey(const ValueKey('konten-note-ok')));
    await _settle(tester);
    expect(
      repo.calls,
      contains('tayang:b:instagram:https://instagram.com/p/abc'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tandai tayang tanpa link, dan review revisi dengan catatan', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepo();
    await tester.pumpWidget(
      _app(
        repo,
        KontenPackageBody(
          officeId: 'o',
          item: KontenItem.fromJson(_raw('a', 'review')),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('REVISI'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('konten-note')),
      'Ganti slide 3',
    );
    await tester.tap(find.byKey(const ValueKey('konten-note-ok')));
    await _settle(tester);
    expect(repo.calls, contains('review:a:false:Ganti slide 3'));

    await tester.tap(find.text('SETUJU'));
    await _settle(tester);
    expect(repo.calls, contains('review:a:true:null'));
    expect(tester.takeException(), isNull);
  });
}
