import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/kantor_downloads.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart';
import 'package:ghina/data/models/kantor_pratinjau.dart';
import 'package:ghina/presentation/features/kantor/pratinjau/pratinjau_downloads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var rows = <Map<String, dynamic>>[];
  var fail = false;
  setUp(() {
    calls.clear();
    rows = [];
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KantorDownloads.channel, (call) async {
          calls.add(call);
          if (fail) throw PlatformException(code: 'offline');
          return switch (call.method) {
            'list' => rows,
            'enqueue' => 42,
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KantorDownloads.channel, null),
  );
  Map<String, dynamic> task(String status, {int reason = 0, int total = 100}) =>
      {
        'id': 42,
        'name': 'rancangan.pdf',
        'description': 'Review · kantor.test',
        'location': 'Download/Ravel/123-rancangan.pdf',
        'status': status,
        'received': 50,
        'total': total,
        'reason': reason,
      };

  test(
    'validates signed preview URL and never sends bearer credentials',
    () async {
      final id = await KantorDownloads.instance.enqueue(
        url: Uri.parse('https://kantor.test/pv/office/id/file?key=signed'),
        name: 'asli.pdf',
        mime: 'application/pdf',
        description: 'Pratinjau',
      );
      expect(id, 42);
      expect((calls.single.arguments as Map).containsKey('headers'), isFalse);
      for (final url in [
        'file:///pv/a',
        'https://u:secret@kantor.test/pv/a',
        'https://kantor.test/api/private',
      ]) {
        await expectLater(
          KantorDownloads.instance.enqueue(
            url: Uri.parse(url),
            name: 'a',
            mime: '',
            description: '',
          ),
          throwsFormatException,
        );
      }
      expect(calls.length, 1);
    },
  );

  test(
    'progress and actionable network/storage errors handle unknown size',
    () {
      expect(KantorDownload.fromMap(task('running')).progress, .5);
      expect(
        KantorDownload.fromMap(task('running', total: -1)).progress,
        isNull,
      );
      expect(
        KantorDownload.fromMap(task('waiting', reason: 2)).label,
        'Menunggu koneksi',
      );
      expect(
        KantorDownload.fromMap(task('failed', reason: 1006)).label,
        contains('penyimpanan'),
      );
      expect(
        KantorDownload.fromMap(task('failed', reason: 403)).label,
        contains('Buka ulang'),
      );
    },
  );

  testWidgets(
    'downloads survives page reopen and exposes progress, cancel, retry, open and share',
    (t) async {
      rows = [task('running')];
      await t.pumpWidget(const MaterialApp(home: KantorDownloadsPage()));
      await t.pump();
      expect(find.text('Mengunduh'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await t.tap(find.text('Batalkan'));
      await t.pump();
      expect(
        calls.any(
          (c) => c.method == 'cancel' && (c.arguments as Map)['id'] == 42,
        ),
        isTrue,
      );
      rows = [task('failed')];
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      await t.tap(find.text('Coba lagi'));
      await t.pump();
      expect(calls.any((c) => c.method == 'retry'), isTrue);
      await t.pumpWidget(const SizedBox());
      rows = [task('complete')];
      await t.pumpWidget(const MaterialApp(home: KantorDownloadsPage()));
      await t.pump();
      expect(find.text('Selesai'), findsOneWidget);
      expect(find.text('Download/Ravel/123-rancangan.pdf'), findsOneWidget);
      await t.tap(find.text('Buka'));
      await t.pump();
      await t.tap(find.text('Bagikan'));
      await t.pump();
      expect(calls.any((c) => c.method == 'open'), isTrue);
      expect(calls.any((c) => c.method == 'share'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty and unavailable bridge remain recoverable', (t) async {
    await t.pumpWidget(const MaterialApp(home: KantorDownloadsPage()));
    await t.pump();
    expect(find.text('Belum ada unduhan'), findsOneWidget);
    fail = true;
    await t.tap(find.byTooltip('Muat ulang'));
    await t.pump();
    expect(find.textContaining('Tidak bisa membaca unduhan'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'preview exposes original/all downloads and rejects foreign host',
    (t) async {
      final api = KantorApi(
        const KantorConfig(baseUrl: 'https://kantor.test', token: 'private'),
      );
      PratinjauItem item(String url) => PratinjauItem.fromJson({
        'id': 'p1',
        'office': 'my-pc',
        'title': 'Desain',
        'files': [
          for (var i = 0; i < 2; i++)
            {
              'id': '$i',
              'name': 'file$i.png',
              'mime': 'image/png',
              'size': 1024,
              'url': url,
              'kind': 'image',
            },
        ],
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PratinjauDownloadActions(
              api: api,
              item: item('/pv/my-pc/p1/f0?key=signed'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Unduh semua (2)'));
      await t.pump();
      expect(calls.where((c) => c.method == 'enqueue').length, 2);
      expect(find.textContaining('2 berkas masuk antrean'), findsOneWidget);
      calls.clear();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PratinjauDownloadActions(
              key: const ValueKey('external'),
              api: api,
              item: item('https://foreign.test/pv/a'),
            ),
          ),
        ),
      );
      await t.tap(find.textContaining('Unduh asli'));
      await t.pump();
      expect(calls.where((c) => c.method == 'enqueue'), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
}
