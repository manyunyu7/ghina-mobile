import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/floor/kantor_floor_tab.dart';

void main() {
  late HttpServer server;
  late String fixture;

  setUpAll(() async {
    HttpOverrides.global = null;
    fixture = File(
      'test/features/kantor/floor/office_fixture.json',
    ).readAsStringSync();
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      expect(body, isNotNull);
      req.response.headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/api/offices/contoh':
          req.response.write(fixture);
        case '/api/inbox':
          req.response.write(
            jsonEncode([
              {
                'id': 'i1',
                'office': 'contoh',
                'who': 'Agen Empat',
                'tool': 'Bash',
                'summary': 'rm -rf build',
                'created_at': DateTime.now().toIso8601String(),
                'held': true,
              },
            ]),
          );
        default:
          req.response.write(jsonEncode({'ok': true}));
      }
      await req.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  testWidgets('floor loads, shows inbox and follows live events', (
    tester,
  ) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
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
            kantorEventsProvider.overrideWith((ref) => events.stream),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: const Scaffold(body: KantorFloorTab(officeId: 'contoh')),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('1 izin menunggu'), findsOneWidget);

    // live event: a permission request disappears when decided elsewhere
    events.add({'t': 'inbox-update', 'id': 'i1', 'status': 'done'});
    await tester.pump();
    expect(find.text('Kotak masuk kosong'), findsOneWidget);

    // session event does not throw and keeps the plan
    events.add({
      't': 'session',
      'office': 'contoh',
      'session': {
        'sid': 'new-1',
        'office': 'contoh',
        'room': 'web',
        'role': null,
        'kind': 'manual',
        'status': 'working',
        'tool': {'name': 'Read', 'label': 'a.txt'},
        'title': 'Sesi baru',
        'subs': [],
      },
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // zoom button and fit button
    await tester.tap(find.byTooltip('Perbesar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Lihat semua'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    // dispose cleanly (stops the ticker)
    await tester.pumpWidget(const SizedBox());
  });
}
