import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/diagnostics/error_log.dart';

void main() {
  late Directory dir;
  late File file;
  ErrorLog make() => ErrorLog(file: () async => file);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('errlog');
    file = File('${dir.path}/log.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps the last 50, newest first, and survives a reload', () async {
    final log = make();
    for (var i = 0; i < 60; i++) {
      log.record(StateError('boom $i'), StackTrace.current);
    }
    await log.flush();
    expect(log.entries, hasLength(ErrorLog.maxEntries));
    expect(log.entries.first.message, contains('boom 59'));

    final again = make();
    await again.load();
    expect(again.entries, hasLength(ErrorLog.maxEntries));
    expect(again.entries.first.message, contains('boom 59'));
    expect(again.entries.first.stack, isNotEmpty);
  });

  test('folds consecutive repeats and records the route', () async {
    final log = make()..routeProbe = () => '/analytics';
    for (var i = 0; i < 5; i++) {
      log.record(StateError('same'), null);
    }
    expect(log.entries, hasLength(1));
    expect(log.entries.single.count, 5);
    expect(log.entries.single.route, '/analytics');
    expect(log.entries.single.toText(), contains('/analytics'));
    await log.flush();
  });

  test('clear empties memory and file; corrupt file does not throw', () async {
    final log = make()..record(StateError('x'), null);
    await log.clear();
    expect(log.entries, isEmpty);
    await log.flush();
    expect(file.readAsStringSync(), '[]');
    file.writeAsStringSync('not json');
    final again = make();
    await again.load();
    expect(again.entries, isEmpty);
  });
}
