import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/meetings/kantor_meeting.dart';
import 'package:ghina/presentation/features/kantor/meetings/kantor_meeting_detail.dart';
import 'package:ghina/presentation/features/kantor/meetings/kantor_meetings_tab.dart';
import 'package:ghina/presentation/features/kantor/notes/kantor_notes_tab.dart';
import 'package:ghina/presentation/features/kantor/notes/note_editor_screen.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_playbooks.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role_detail.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_roles_tab.dart';
import 'package:ghina/presentation/features/kantor/widgets/kantor_wide.dart';

const _dina = {
  'id': 'dina',
  'name': 'Dina',
  'title': 'Backend',
  'model': 'sonnet',
  'room': 'api',
  'color': '#2F5D9E',
  'hair': '#2B1D14',
  'skin': '#F1C9A5',
  'hairStyle': 'hijab',
  'persona': 'Teliti.',
  'skills': ['backend'],
};

const _wide = Size(900, 800);
const _narrow = Size(400, 800);

void main() {
  late HttpServer server;
  var noteGets = 0;

  // Daemon palsu: daftar catatan dan detail rapat.
  setUpAll(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      final p = req.uri.path;
      Object out = {'ok': true};
      if (p == '/api/offices/o/notes' && req.method == 'GET') {
        noteGets++;
        out = {
          'notes': [
            for (var i = 0; i < 6; i++)
              {
                'id': 'n$i',
                'title': 'Catatan $i',
                'body': 'isi $i',
                'color': 'kuning',
                'author': 'pemilik',
              },
          ],
          'tags': <dynamic>[],
        };
      } else if (p == '/api/offices/o/meetings/m1') {
        out = {
          'id': 'm1',
          'topic': 'Bahas rilis',
          'status': 'selesai',
          'participants': ['dina'],
          'chair': 'dina',
          'messages': <dynamic>[],
        };
      }
      req.response.headers.set('connection', 'close');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(out));
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(() {
    noteGets = 0;
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pump(
    WidgetTester t,
    Size size,
    Widget child, [
    List<Override> overrides = const [],
  ]) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorApiProvider.overrideWithValue(
            KantorApi(
              KantorConfig(
                baseUrl: 'http://127.0.0.1:${server.port}',
                token: 't',
              ),
            ),
          ),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
          ...overrides,
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await settle(t);
  }

  List<Override> roleOverrides(void Function() onFetch) => [
    kantorRolesProvider('o').overrideWith((_) async {
      onFetch();
      return [
        KantorRole.fromJson(_dina),
        KantorRole.fromJson({..._dina, 'id': 'bayu', 'name': 'Bayu'}),
      ];
    }),
    kantorOfficeProvider('o').overrideWith(
      (_) async => KantorOffice.fromJson({
        'id': 'o',
        'name': 'O',
        'plan': {
          'rooms': [
            {'id': 'api', 'name': 'Ruang API', 'kind': 'kode'},
          ],
        },
      }),
    ),
    kantorPlaybooksProvider('o').overrideWith((_) async => const []),
    kantorProposalsProvider('o').overrideWith((_) async => const []),
  ];

  Finder highlighted() => find.byWidgetPredicate(
    (w) => w is ChunkyCard && w.tinted == GhinaColors.blue,
  );

  group('Role', () {
    testWidgets('lebar: daftar kiri, detail kanan, item tersorot', (t) async {
      var fetches = 0;
      await pump(
        t,
        _wide,
        const KantorRolesTab(officeId: 'o'),
        roleOverrides(() => fetches++),
      );
      expect(find.byType(KantorPaneEmpty), findsOneWidget);
      expect(highlighted(), findsNothing);

      await t.tap(find.text('Dina'));
      await settle(t);
      final detail = find.byType(KantorRoleDetailScreen);
      expect(detail, findsOneWidget);
      // detail di panel kanan, daftar tetap terlihat
      expect(t.getTopLeft(detail).dx, greaterThan(300));
      expect(find.text('Bayu'), findsOneWidget);
      expect(highlighted(), findsOneWidget);

      // ganti role: detail berganti dan daftar dimuat ulang
      final before = fetches;
      await t.tap(find.text('Bayu'));
      await settle(t);
      expect(find.byType(KantorRoleDetailScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Bayu'), findsOneWidget);
      expect(fetches, greaterThan(before));
    });

    testWidgets('sempit: detail halaman penuh, reload saat kembali', (t) async {
      var fetches = 0;
      await pump(
        t,
        _narrow,
        const KantorRolesTab(officeId: 'o'),
        roleOverrides(() => fetches++),
      );
      expect(find.byType(KantorPaneEmpty), findsNothing);
      await t.tap(find.text('Dina'));
      await settle(t);
      final detail = find.byType(KantorRoleDetailScreen);
      expect(detail, findsOneWidget);
      expect(t.getTopLeft(detail).dx, 0);
      expect(find.text('Bayu'), findsNothing); // daftar tertutup halaman
      final before = fetches;
      await t.pageBack();
      await settle(t);
      expect(find.byType(KantorRoleDetailScreen), findsNothing);
      expect(fetches, greaterThan(before));
    });
  });

  group('Notes', () {
    // posisi x kiri tiap kartu catatan, untuk menghitung jumlah kolom
    Set<double> columns(WidgetTester t) => {
      for (var i = 0; i < 6; i++) t.getTopLeft(find.text('Catatan $i')).dx,
    };

    test('jumlah kolom: 2 di HP, lebih banyak di layar lebar', () {
      expect(kantorNoteColumns(360), 2);
      expect(kantorNoteColumns(560), 2);
      expect(kantorNoteColumns(790), 3);
      expect(kantorNoteColumns(1300), 5);
    });

    testWidgets('lebar: grid beberapa kolom, editor di panel samping', (
      t,
    ) async {
      await pump(t, _wide, const KantorNotesTab(officeId: 'o'));
      expect(columns(t).length, 3);

      await t.tap(find.text('Catatan 1'));
      await settle(t);
      final editor = find.byType(NoteEditorScreen);
      expect(editor, findsOneWidget);
      expect(t.getTopLeft(editor).dx, greaterThan(300));

      final before = noteGets;
      await t.tap(find.byType(BackButton));
      await settle(t);
      expect(find.byType(NoteEditorScreen), findsNothing);
      expect(noteGets, greaterThan(before));

      // ketuk di luar panel: tetap lewat _close (PopScope) lalu tertutup
      await t.tap(find.text('Catatan 2'));
      await settle(t);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      await t.tapAt(const Offset(40, 400));
      await settle(t);
      expect(find.byType(NoteEditorScreen), findsNothing);
    });

    testWidgets('sempit: tetap 2 kolom, editor halaman penuh', (t) async {
      await pump(t, _narrow, const KantorNotesTab(officeId: 'o'));
      expect(columns(t).length, 2);

      await t.tap(find.text('Catatan 1'));
      await settle(t);
      final editor = find.byType(NoteEditorScreen);
      expect(editor, findsOneWidget);
      expect(t.getTopLeft(editor).dx, 0);

      final before = noteGets;
      await t.tap(find.byType(BackButton));
      await settle(t);
      expect(find.byType(NoteEditorScreen), findsNothing);
      expect(noteGets, greaterThan(before));
    });
  });

  group('Rapat', () {
    List<Override> meetingOverrides(void Function() onFetch) => [
      kantorMeetingsProvider('o').overrideWith((_) async {
        onFetch();
        return [
          KantorMeetingBrief.fromJson({
            'id': 'm1',
            'topic': 'Bahas rilis',
            'status': 'selesai',
            'participants': ['dina'],
          }),
        ];
      }),
      kantorRolesProvider(
        'o',
      ).overrideWith((_) async => [KantorRole.fromJson(_dina)]),
    ];

    testWidgets('lebar: daftar kiri, detail rapat kanan', (t) async {
      await pump(
        t,
        _wide,
        const KantorMeetingsTab(officeId: 'o'),
        meetingOverrides(() {}),
      );
      expect(find.byType(KantorPaneEmpty), findsOneWidget);
      await t.tap(find.text('Bahas rilis'));
      await settle(t);
      final detail = find.byType(KantorMeetingDetailScreen);
      expect(detail, findsOneWidget);
      expect(t.getTopLeft(detail).dx, greaterThan(300));
      expect(highlighted(), findsOneWidget);
      expect(find.text('Notulen'), findsOneWidget);
    });

    testWidgets('sempit: detail halaman penuh, reload saat kembali', (t) async {
      var fetches = 0;
      await pump(
        t,
        _narrow,
        const KantorMeetingsTab(officeId: 'o'),
        meetingOverrides(() => fetches++),
      );
      await t.tap(find.text('Bahas rilis'));
      await settle(t);
      final detail = find.byType(KantorMeetingDetailScreen);
      expect(detail, findsOneWidget);
      expect(t.getTopLeft(detail).dx, 0);
      final before = fetches;
      await t.pageBack();
      await settle(t);
      expect(find.byType(KantorMeetingDetailScreen), findsNothing);
      expect(fetches, greaterThan(before));
    });
  });
}
