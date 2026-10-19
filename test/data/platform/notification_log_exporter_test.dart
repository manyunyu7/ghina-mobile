import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/platform/notification_log_exporter.dart';
import 'package:ghina/data/repositories/notification_log_repositories.dart';

void main() {
  late AppDatabase db;
  late Directory base;

  setUp(() async {
    db = AppDatabase.memory();
    base = await Directory.systemTemp.createTemp('notif-export-');
  });

  tearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });

  NotificationLogExporter exporter() =>
      NotificationLogExporter(db, baseDir: () async => base);

  test(
    'writes every entry as one JSON line, oldest first, plus meta',
    () async {
      await insertCapturedNotification(
        db,
        packageName: 'id.co.contoh.bank',
        title: 'Transfer masuk',
        body: 'Rp 50.000 dari Budi Contoh',
        postedAt: DateTime.utc(2026, 10, 19, 2),
        capturedAt: DateTime.utc(2026, 10, 19, 2, 0, 1),
      );
      await insertCapturedNotification(
        db,
        packageName: 'com.contoh.chat',
        appName: 'Contoh Chat',
        title: 'Siti Sample',
        body: 'Halo',
        postedAt: DateTime.utc(2026, 10, 18, 23),
        capturedAt: DateTime.utc(2026, 10, 18, 23, 0, 2),
      );

      expect(await exporter().export(), 2);

      final dir = '${base.path}/${NotificationLogExporter.folder}';
      final lines = File('$dir/notifications.jsonl').readAsLinesSync();
      expect(lines, hasLength(2));
      final first = jsonDecode(lines.first) as Map<String, Object?>;
      expect(first['packageName'], 'com.contoh.chat');
      expect(first['appName'], 'Contoh Chat');
      expect(first['postedAt'], '2026-10-18T23:00:00.000Z');
      expect(first['processed'], false);
      expect(
        first.keys,
        containsAll([
          'id',
          'title',
          'body',
          'capturedAt',
          'ruleId',
          'transactionId',
          'txType',
          'amount',
          'parseError',
        ]),
      );

      final meta =
          jsonDecode(File('$dir/meta.json').readAsStringSync())
              as Map<String, Object?>;
      expect(meta['count'], 2);
      expect(meta['latestPostedAt'], '2026-10-19T02:00:00.000Z');
      expect(meta['exportedAt'], isA<String>());
      expect(File('$dir/notifications.jsonl.tmp').existsSync(), isFalse);
    },
  );

  test('an empty log still writes an empty file and count 0', () async {
    expect(await exporter().export(), 0);
    final dir = '${base.path}/${NotificationLogExporter.folder}';
    expect(File('$dir/notifications.jsonl').readAsStringSync(), isEmpty);
    expect(
      (jsonDecode(File('$dir/meta.json').readAsStringSync())
          as Map)['latestPostedAt'],
      isNull,
    );
  });

  test('no external storage → null, nothing written', () async {
    expect(
      await NotificationLogExporter(db, baseDir: () async => null).export(),
      isNull,
    );
  });

  test('re-export replaces the file instead of appending', () async {
    await insertCapturedNotification(
      db,
      packageName: 'id.co.contoh.bank',
      title: 'A',
      body: 'B',
      postedAt: DateTime.utc(2026, 10, 19),
      capturedAt: DateTime.utc(2026, 10, 19),
    );
    await exporter().export();
    await exporter().export();
    final dir = '${base.path}/${NotificationLogExporter.folder}';
    expect(File('$dir/notifications.jsonl').readAsLinesSync(), hasLength(1));
  });
}
