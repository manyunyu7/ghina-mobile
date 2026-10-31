import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/codex/kantor_codex.dart';
import 'package:ghina/presentation/features/kantor/engines/kantor_engines.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role.dart';

void main() {
  testWidgets(
    'unknown server engine appears, submits model/effort/mode and refreshes without a client engine list',
    (t) async {
      var name = 'Mesin Masa Depan';
      KantorEngineSel? selected;
      late BuildContext formContext;
      await t.pumpWidget(
        ProviderScope(
          retry: (count, error) => null,
          overrides: [
            kantorEngineCatalogProvider.overrideWith(
              (ref) async => KantorEngineCatalog.fromJson({
                'engines': [
                  {'id': 'claude', 'name': 'Claude Code', 'available': true},
                  {
                    'id': 'future-cli',
                    'name': name,
                    'available': true,
                    'supportsEffort': true,
                    'defaultPermissionMode': 'review',
                    'permissionModes': [
                      {'id': 'review', 'name': 'Periksa dulu'},
                      {'id': 'safe', 'name': 'Mode aman baru'},
                    ],
                    'models': [
                      {
                        'slug': 'future-v7',
                        'name': 'Future Seven',
                        'efforts': [
                          {'effort': 'deep'},
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'missing-cli',
                    'name': 'Belum Terpasang',
                    'available': false,
                  },
                ],
              }),
            ),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  formContext = context;
                  return SingleChildScrollView(
                    child: KantorEngineFields(
                      role: const {'engine': 'claude', 'model': 'opus'},
                      onChanged: (s) => selected = s,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Belum Terpasang'), findsNothing);
      await t.tap(find.text(name));
      await t.pumpAndSettle();
      expect(find.text('Model $name'), findsOneWidget);
      await t.tap(find.text('Bawaan $name').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Future Seven').last);
      await t.pumpAndSettle();
      await t.tap(find.text('deep'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mode aman baru'));
      await t.pumpAndSettle();
      expect(selected!.body(const {'engine': 'claude'}), {
        'engine': 'future-cli',
        'model': 'future-v7',
        'effort': 'deep',
        'permissionMode': 'safe',
      });
      final role = KantorRole.fromJson({
        'engine': 'future-cli',
        'model': 'future-v7',
      });
      expect(role.engine, 'future-cli');
      name = 'Nama dari server berubah';
      ProviderScope.containerOf(
        formContext,
      ).invalidate(kantorEngineCatalogProvider);
      await t.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
    },
  );

  testWidgets('catalog error offers retry rather than a static list', (
    t,
  ) async {
    var attempts = 0;
    await t.pumpWidget(
      ProviderScope(
        retry: (count, error) => null,
        overrides: [
          kantorEngineCatalogProvider.overrideWith((ref) async {
            attempts++;
            throw Exception('offline');
          }),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: KantorEngineFields(
              role: const {'engine': 'claude'},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Gemini (Antigravity)'), findsNothing);
    await t.tap(find.text('Coba lagi'));
    await t.pumpAndSettle();
    expect(attempts, 2);
  });
}
