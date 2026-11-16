import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/archive/kantor_archive_tab.dart';
import 'package:ghina/presentation/features/kantor/archive/kantor_transcript_screen.dart';
import 'package:ghina/presentation/features/kantor/files/kantor_file_viewer.dart';
import 'package:ghina/presentation/features/kantor/files/kantor_files_model.dart';
import 'package:ghina/presentation/features/kantor/files/kantor_files_tab.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role.dart';

Widget _app(List<Override> overrides, Widget child) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: child),
  ),
);

Future<void> _size(WidgetTester t, double w) async {
  t.view.physicalSize = Size(w, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

// Viewer/transkrip tetap "memuat" (animasi terus), jadi tidak bisa
// pumpAndSettle; maju beberapa frame cukup untuk efek tekan + transisi.
Future<void> _step(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

KantorFolder _folder(String path, List<Map<String, dynamic>> entries) =>
    KantorFolder.fromJson({'path': path, 'root': '/x', 'entries': entries});

List<Override> _filesOverrides() => [
  kantorOfficeProvider(
    'o',
  ).overrideWith((_) async => KantorOffice.fromJson({'id': 'o', 'name': 'O'})),
  kantorFolderProvider((office: 'o', path: '', all: false)).overrideWith(
    (_) async => _folder('', [
      {'name': 'docs', 'path': 'docs', 'dir': true},
      {'name': 'a.md', 'path': 'a.md', 'dir': false, 'size': 10},
    ]),
  ),
  kantorFolderProvider((office: 'o', path: 'docs', all: false)).overrideWith(
    (_) async => _folder('docs', [
      {'name': 'b.txt', 'path': 'docs/b.txt', 'dir': false, 'size': 5},
    ]),
  ),
];

List<Override> _archiveOverrides() => [
  kantorArchiveProvider('o').overrideWith(
    (_) async => [
      KantorArchiveRow.fromJson({
        'sid': 'a1',
        'title': 'Perbaiki login',
        'active': false,
      }),
      KantorArchiveRow.fromJson({
        'sid': 'b2',
        'title': 'Sesi lain',
        'active': false,
      }),
    ],
  ),
  kantorRolesProvider('o').overrideWith((_) async => const <KantorRole>[]),
  kantorOfficeProvider(
    'o',
  ).overrideWith((_) async => KantorOffice.fromJson({'id': 'o', 'name': 'O'})),
];

// Tile/kartu yang tersorot (tinted) menandai item yang terbuka di kanan.
bool _tileTinted(WidgetTester t, String title) =>
    t.widget<ChunkyTile>(find.widgetWithText(ChunkyTile, title).first).tinted !=
    null;

void main() {
  // Tanpa token: kantorApiProvider null, viewer/transkrip tetap di "memuat".
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('File, layar lebar: daftar kiri + file terbuka di kanan', (
    t,
  ) async {
    await _size(t, 900);
    await t.pumpWidget(
      _app(_filesOverrides(), const KantorFilesTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('Pilih file di kiri untuk membukanya.'), findsOneWidget);

    await t.tap(find.text('a.md'));
    await _step(t);
    // Dua panel: daftar tetap terlihat, viewer di kanan.
    expect(find.byType(KantorFileViewerScreen), findsOneWidget);
    expect(find.text('Cari nama file'), findsOneWidget);
    expect(_tileTinted(t, 'a.md'), isTrue);
    expect(_tileTinted(t, 'docs'), isFalse);

    // Navigasi folder tetap di panel kiri; file yang terbuka tidak tertutup.
    await t.tap(find.text('docs'));
    await _step(t);
    expect(find.text('b.txt'), findsOneWidget);
    expect(find.byType(KantorFileViewerScreen), findsOneWidget);
  });

  testWidgets('File, layar sempit: file dibuka halaman penuh', (t) async {
    await _size(t, 400);
    await t.pumpWidget(
      _app(_filesOverrides(), const KantorFilesTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.text('Pilih file di kiri untuk membukanya.'), findsNothing);

    await t.tap(find.text('a.md'));
    await _step(t);
    expect(find.byType(KantorFileViewerScreen), findsOneWidget);
    // Daftar tertutup halaman viewer (satu panel).
    expect(find.text('Cari nama file'), findsNothing);
  });

  testWidgets('Arsip, layar lebar: daftar sesi kiri + transkrip kanan', (
    t,
  ) async {
    await _size(t, 900);
    await t.pumpWidget(
      _app(_archiveOverrides(), const KantorArchiveTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(
      find.text('Pilih sesi di kiri untuk membaca transkripnya.'),
      findsOneWidget,
    );

    await t.tap(find.text('Perbaiki login'));
    await _step(t);
    expect(find.byType(KantorTranscriptScreen), findsOneWidget);
    // Daftar tetap terlihat; judul muncul di kartu + AppBar transkrip.
    expect(find.text('Sesi lain'), findsOneWidget);
    expect(find.text('Perbaiki login'), findsNWidgets(2));

    // Tombol "Transkrip" sesi lain mengganti isi panel kanan.
    await t.tap(find.text('TRANSKRIP').last);
    await _step(t);
    expect(find.byType(KantorTranscriptScreen), findsOneWidget);
    expect(find.text('Sesi lain'), findsNWidgets(2));
    expect(find.text('Perbaiki login'), findsOneWidget);
  });

  testWidgets('Arsip, layar sempit: transkrip dibuka halaman penuh', (t) async {
    await _size(t, 400);
    await t.pumpWidget(
      _app(_archiveOverrides(), const KantorArchiveTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsNothing);

    await t.tap(find.text('Perbaiki login'));
    await _step(t);
    expect(find.byType(KantorTranscriptScreen), findsOneWidget);
    expect(find.text('Arsip sesi'), findsNothing);
  });
}
