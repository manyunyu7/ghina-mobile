import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/services/notification_log_export.dart';
import '../datasources/local/app_database.dart';

/// Copy of "Log Notifikasi" as JSON Lines in the app's external files dir:
/// `Android/data/<package>/files/notification-log/notifications.jsonl` plus
/// `meta.json` ({exportedAt, count, latestPostedAt}). Pulled over adb by
/// `tool/pull_notification_log.sh`.
///
/// Stays on the device like the log itself: on Android 11+ `Android/data` is
/// private to this app (other apps can't read it; adb from an authorised
/// computer can) and it is removed on uninstall. Written to a temp file and
/// renamed, so a pull never sees half a file.
final class NotificationLogExporter implements NotificationLogExport {
  NotificationLogExporter(this._db, {Future<Directory?> Function()? baseDir})
    : _baseDir = baseDir ?? getExternalStorageDirectory;

  final AppDatabase _db;
  final Future<Directory?> Function() _baseDir;

  static const folder = 'notification-log';

  @override
  Future<int?> export() async {
    final base = await _baseDir();
    if (base == null) return null;
    final dir = Directory('${base.path}/$folder');
    await dir.create(recursive: true);

    final rows = await (_db.select(
      _db.capturedNotifications,
    )..orderBy([(t) => OrderingTerm.asc(t.postedAt)])).get();
    final buf = StringBuffer();
    for (final r in rows) {
      buf.writeln(jsonEncode(toExportJson(r)));
    }
    await _writeAtomic(File('${dir.path}/notifications.jsonl'), buf.toString());
    await _writeAtomic(
      File('${dir.path}/meta.json'),
      jsonEncode({
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'count': rows.length,
        'latestPostedAt': rows.isEmpty
            ? null
            : rows.last.postedAt.toUtc().toIso8601String(),
      }),
    );
    return rows.length;
  }

  /// One line of the export. Times are UTC ISO-8601.
  static Map<String, Object?> toExportJson(CapturedNotificationRow r) => {
    'id': r.id,
    'packageName': r.packageName,
    'appName': r.appName,
    'title': r.title,
    'body': r.body,
    'postedAt': r.postedAt.toUtc().toIso8601String(),
    'capturedAt': r.capturedAt.toUtc().toIso8601String(),
    'processed': r.processed,
    'ruleId': r.ruleId,
    'transactionId': r.transactionId,
    'txType': r.txType,
    'amount': r.amount,
    'parseError': r.parseError,
  };

  static Future<void> _writeAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }
}

/// iOS / tests: there is no notification log to copy.
final class NoopNotificationLogExport implements NotificationLogExport {
  const NoopNotificationLogExport();

  @override
  Future<int?> export() async => null;
}
