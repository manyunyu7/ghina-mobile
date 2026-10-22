import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/diagnostics/error_log.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/settings/pages/error_log_page.dart';
import 'package:ghina/presentation/features/settings/widgets/error_card.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: GhinaTheme.light(), home: child);

void main() {
  testWidgets('lists, opens detail, deletes entries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('errpage');
    addTearDown(() => dir.deleteSync(recursive: true));
    final log = ErrorLog(file: () async => File('${dir.path}/l.json'));
    log.record(StateError('kotak abu'), StackTrace.current);

    await tester.pumpWidget(_app(ErrorLogPage(logOverride: log)));
    expect(find.textContaining('kotak abu'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('error-log-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('error-detail-text')), findsOneWidget);
    expect(find.text('SALIN'), findsOneWidget);

    await tester.tap(find.text('HAPUS ENTRI INI'));
    await tester.pump(const Duration(seconds: 1)); // mascot loops forever
    expect(log.entries, isEmpty);
    expect(find.text('Belum ada error'), findsOneWidget);
  });

  testWidgets('error card renders compactly without Theme or Navigator', (
    tester,
  ) async {
    openErrorLog = () {};
    addTearDown(() => openErrorLog = null);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(height: 60, width: 120, child: GhinaErrorCard()),
      ),
    );
    expect(find.text('Bagian ini gagal dimuat'), findsOneWidget);
    expect(find.text('Lihat detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
