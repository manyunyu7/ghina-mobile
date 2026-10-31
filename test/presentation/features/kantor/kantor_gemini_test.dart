import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/codex/kantor_codex.dart';
import 'package:ghina/presentation/features/kantor/engines/kantor_engines.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role.dart';

void main() {
  test('Gemini role round trip and effective session engine', () {
    final role = KantorRole.fromJson({
      'engine': 'antigravity',
      'model': 'gemini-flash',
    });
    expect(role.engine, 'antigravity');
    expect(role.modelText, 'gemini-flash');
    expect(KantorEngineSel.initial(role.look).body(role.look), {
      'model': 'gemini-flash',
      'permissionMode': 'default',
    });
    expect(kantorEngineIsGemini({'engine': 'claude'}, role.look), false);
    expect(
      kantorSessionModelText(
        {'engine': 'claude', 'model': 'opus'},
        {'engine': 'antigravity', 'model': 'gemini-flash'},
      ),
      'gemini-flash',
    );
  });

  testWidgets(
    'Gemini selection sends native model and permission, without Claude effort',
    (t) async {
      KantorEngineSel? selected;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorEngineCatalogProvider.overrideWith(
              (ref) async => KantorEngineCatalog.fromJson({
                'engines': [
                  {
                    'id': 'claude',
                    'name': 'Claude Code',
                    'available': true,
                    'models': [
                      {'slug': 'opus', 'name': 'Opus'},
                    ],
                  },
                  {
                    'id': 'antigravity',
                    'name': 'Gemini (Antigravity)',
                    'available': true,
                    'defaultPermissionMode': 'default',
                    'permissionModes': [
                      {'id': 'default', 'name': 'Tanya dulu'},
                      {'id': 'acceptEdits', 'name': 'Edit file otomatis'},
                    ],
                    'models': [
                      {'slug': 'gemini-flash', 'name': 'Gemini Flash'},
                    ],
                  },
                ],
              }),
            ),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: KantorEngineFields(
                  role: const {'engine': 'claude', 'model': 'opus'},
                  onChanged: (s) => selected = s,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Gemini (Antigravity)'));
      await t.pumpAndSettle();
      expect(find.text('Model Gemini (Antigravity)'), findsOneWidget);
      expect(find.text('Edit file otomatis'), findsOneWidget);
      expect(selected!.body(const {'engine': 'claude', 'model': 'opus'}), {
        'engine': 'antigravity',
        'permissionMode': 'default',
      });
      expect(selected!.managed, true);
      final body = selected!
          .copy(model: 'gemini-flash', perm: 'plan', effort: 'high')
          .body(const {'engine': 'claude', 'model': 'opus'});
      expect(body, {
        'engine': 'antigravity',
        'model': 'gemini-flash',
        'permissionMode': 'plan',
      });
      await t.tap(find.text('Claude Code'));
      await t.pumpAndSettle();
      expect(selected!.managed, true);
      expect(selected!.body(const {'engine': 'claude'}), {
        'engine': 'claude',
        'model': 'opus',
      });
    },
  );
}
