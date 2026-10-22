import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/stop_choice.dart';

Future<String?> _ask(
  WidgetTester t,
  Map<String, dynamic> sess, {
  String? tap,
}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  String? result = 'unset';
  await t.pumpWidget(
    MaterialApp(
      theme: GhinaTheme.light(),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await askStopMode(c, sess),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
  if (tap != null) {
    await t.tap(find.text(tap));
    await t.pump(const Duration(milliseconds: 500));
  }
  return result;
}

void main() {
  test('kantorBgAgents prefers bgAgents, else counts running subs', () {
    expect(kantorBgAgents({'bgAgents': 3}), 3);
    expect(
      kantorBgAgents({
        'subs': [
          {'status': 'working'},
          {'status': 'done'},
        ],
      }),
      1,
    );
    expect(kantorBgAgents({}), 0);
  });

  testWidgets('no background subagents: plain Esc without a dialog', (t) async {
    expect(await _ask(t, {'status': 'working', 'bgAgents': 0}), 'esc');
    expect(find.text('Hentikan sesi ini?'), findsNothing);
  });

  testWidgets('with background subagents: choose stop-all', (t) async {
    final r = await _ask(t, {
      'status': 'idle',
      'bgAgents': 2,
    }, tap: 'Hentikan semua (termasuk subagent)');
    expect(r, 'stop-all');
  });

  testWidgets(
    'with background subagents: sheet states the facts, main only gives esc',
    (t) async {
      final r = await _ask(t, {
        'status': 'working',
        'bgAgents': 2,
      }, tap: 'Hanya agen utama');
      expect(r, 'esc');
    },
  );
}
