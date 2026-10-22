import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/archive/kantor_archive_tab.dart';
import 'package:ghina/presentation/features/kantor/files/kantor_files_model.dart';
import 'package:ghina/presentation/features/kantor/meetings/kantor_meeting.dart';
import 'package:ghina/presentation/features/kantor/meetings/kantor_meetings_tab.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_look.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_playbooks.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role.dart';
import 'package:ghina/presentation/features/kantor/meetings/kantor_meeting_form.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role_editor.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_roles_tab.dart';

const _role = {
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

Widget _app(List<Override> overrides, Widget child) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: child),
  ),
);

void main() {
  // No token saved: the events stream stays empty and no socket is opened.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('KantorLook round-trips and keeps a hijab free of caps', () {
    final look = KantorLook.fromJson({
      'hairStyle': 'hijab',
      'acc': 'topi',
      'color': '#BC3B34',
    });
    look.normalize();
    expect(look.acc, '');
    expect(KantorLook.fromJson(look.toJson()).color, '#BC3B34');
    for (var i = 0; i < 50; i++) {
      final r = kantorRandomLook();
      expect(r.hairStyle == 'hijab' && r.acc == 'topi', isFalse);
    }
  });

  test('meeting JSON parses and counts turns', () {
    final m = KantorMeeting.fromJson({
      'id': 'm1',
      'topic': 'Rilis',
      'status': 'gagal',
      'participants': ['a', 'b'],
      'cost': 0.5,
      'actions': [
        {'title': 'Tulis catatan', 'card': 'k1'},
        {'title': 'Cek', 'card': ''},
      ],
      'messages': [
        {'id': 3, 'who': 'A', 'text': 'hai', 'kind': 'bicara'},
      ],
    });
    expect(m.interrupted, isTrue);
    expect(m.actions.first.card, 'k1');
    expect(m.actions.last.card, isNull);
    expect(m.messages.single.id, '3');
    expect(kantorMeetingTurns(3, 2), 7);
  });

  test('folder listing parses entries', () {
    final f = KantorFolder.fromJson({
      'path': 'docs',
      'root': '/x',
      'hidden': 2,
      'entries': [
        {
          'name': 'a.png',
          'path': 'docs/a.png',
          'dir': false,
          'size': 2048,
          'mtime': 1000,
        },
      ],
    });
    expect(f.entries.single.isImage, isTrue);
    expect(kantorFileSize(f.entries.single.size), '2.0 KB');
  });

  testWidgets('roles tab shows roles with live status', (t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app([
        kantorRolesProvider(
          'o',
        ).overrideWith((_) async => [KantorRole.fromJson(_role)]),
        kantorOfficeProvider('o').overrideWith(
          (_) async => KantorOffice.fromJson({
            'id': 'o',
            'name': 'O',
            'plan': {
              'rooms': [
                {'id': 'api', 'name': 'Ruang API', 'kind': 'kode'},
              ],
            },
            'sessions': [
              {'sid': 's1', 'role': 'dina', 'status': 'working', 'title': 'x'},
            ],
          }),
        ),
        kantorPlaybooksProvider('o').overrideWith((_) async => const []),
        kantorProposalsProvider('o').overrideWith((_) async => const []),
      ], const KantorRolesTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.text('Dina'), findsOneWidget);
    expect(find.text('Bekerja'), findsOneWidget);
    expect(find.textContaining('Ruang API'), findsOneWidget);
  });

  testWidgets('meetings tab lists meetings', (t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app([
        kantorMeetingsProvider('o').overrideWith(
          (_) async => [
            KantorMeetingBrief.fromJson({
              'id': 'm1',
              'topic': 'Bahas rilis',
              'status': 'selesai',
              'participants': ['dina', 'x'],
              'cost': 1.234,
            }),
          ],
        ),
        kantorRolesProvider(
          'o',
        ).overrideWith((_) async => [KantorRole.fromJson(_role)]),
      ], const KantorMeetingsTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.text('Bahas rilis'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(find.textContaining('\$1.234'), findsOneWidget);
  });

  testWidgets('archive tab filters by search', (t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app([
        kantorArchiveProvider('o').overrideWith(
          (_) async => [
            KantorArchiveRow.fromJson({
              'sid': 'a1',
              'role': 'dina',
              'title': 'Perbaiki login',
              'cost': 2.0,
              'active': false,
            }),
            KantorArchiveRow.fromJson({
              'sid': 'b2',
              'title': 'Sesi lain',
              'active': false,
            }),
          ],
        ),
        kantorRolesProvider(
          'o',
        ).overrideWith((_) async => [KantorRole.fromJson(_role)]),
        kantorOfficeProvider('o').overrideWith(
          (_) async => KantorOffice.fromJson({'id': 'o', 'name': 'O'}),
        ),
      ], const KantorArchiveTab(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.text('Perbaiki login'), findsOneWidget);
    expect(find.text('Sesi lain'), findsOneWidget);
    expect(find.text('PANGGIL LAGI'), findsNWidgets(2));
    await t.enterText(find.byType(TextField).first, 'login');
    await t.pump();
    expect(find.text('Sesi lain'), findsNothing);
  });

  testWidgets('role editor and meeting form build without layout errors', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final overrides = <Override>[
      kantorRolesProvider('o').overrideWith(
        (_) async => [
          KantorRole.fromJson(_role),
          KantorRole.fromJson({..._role, 'id': 'b', 'name': 'Bayu'}),
        ],
      ),
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
    ];
    await t.pumpWidget(
      _app(overrides, const KantorRoleEditorScreen(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.text('Tambah role'), findsOneWidget);
    expect(find.text('BUAT ROLE'), findsOneWidget);
    await t.pumpWidget(
      _app(overrides, const KantorMeetingFormScreen(officeId: 'o')),
    );
    await t.pumpAndSettle();
    expect(find.text('Bayu'), findsWidgets);
    expect(find.textContaining('giliran'), findsWidgets);
  });
}
