import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';

/// A notification repost with the same app/title/text inside this window is
/// the same notification (apps re-notify on updates) and is not logged twice.
const kNotificationDedupeWindow = Duration(minutes: 2);

/// Stores one captured notification unless it's a repost. Returns the new
/// row id, or null when skipped. Used by the listener callback, which may run
/// in a background isolate.
///
/// A repost is the same app/title/text inside [kNotificationDedupeWindow], or
/// (for apps no enabled rule watches) the same text as the last capture under
/// the same notification key: messengers like WhatsApp re-post every unread
/// chat, with a fresh post time, whenever any new message arrives. Apps with
/// a rule keep the window check only, so two identical payments are never
/// collapsed into one.
Future<int?> insertCapturedNotification(
  AppDatabase db, {
  required String packageName,
  String? appName,
  required String title,
  required String body,
  String? notificationKey,
  required DateTime postedAt,
  required DateTime capturedAt,
}) => db.transaction(() async {
  final t = db.capturedNotifications;
  final from = postedAt.subtract(kNotificationDedupeWindow);
  final to = postedAt.add(kNotificationDedupeWindow);
  final dup =
      await (db.selectOnly(t)
            ..addColumns([t.id])
            ..where(
              t.packageName.equals(packageName) &
                  t.title.equals(title) &
                  t.body.equals(body) &
                  t.postedAt.isBetweenValues(
                    from.millisecondsSinceEpoch,
                    to.millisecondsSinceEpoch,
                  ),
            )
            ..limit(1))
          .getSingleOrNull();
  if (dup != null) return null;
  if (notificationKey != null && !await _watchedByRule(db, packageName)) {
    final last =
        await (db.select(t)
              ..where((n) => n.notificationKey.equals(notificationKey))
              ..orderBy([
                (n) => OrderingTerm.desc(n.postedAt),
                (n) => OrderingTerm.desc(n.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (last != null && last.title == title && last.body == body) return null;
  }
  return db
      .into(t)
      .insert(
        CapturedNotificationsCompanion.insert(
          packageName: packageName,
          appName: Value(appName),
          title: Value(title),
          body: Value(body),
          notificationKey: Value(notificationKey),
          postedAt: postedAt,
          capturedAt: capturedAt,
        ),
      );
});

/// Whether an enabled parsing rule lists [packageName].
Future<bool> _watchedByRule(AppDatabase db, String packageName) async {
  final row = await db
      .customSelect(
        'SELECT 1 FROM notification_rules r, json_each(r.packages) j '
        'WHERE r.enabled = 1 AND j.value = ? LIMIT 1',
        variables: [Variable.withString(packageName)],
        readsFrom: {db.notificationRules},
      )
      .getSingleOrNull();
  return row != null;
}

extension on CapturedNotificationRow {
  CapturedNotification toEntity() => CapturedNotification(
    id: id,
    packageName: packageName,
    appName: appName,
    title: title,
    body: body,
    postedAt: postedAt,
    capturedAt: capturedAt,
    processed: processed,
    ruleId: ruleId,
    transactionId: transactionId,
    txType: TxType.tryFromWire(txType),
    amount: amount,
    parseError: parseError,
  );
}

class DriftCapturedNotificationRepository
    implements CapturedNotificationRepository {
  DriftCapturedNotificationRepository(this._db);
  final AppDatabase _db;

  $CapturedNotificationsTable get _t => _db.capturedNotifications;

  /// Rows matching [f] ([withPackage]: also its app).
  Expression<bool> _matching(
    NotificationLogFilter f, {
    bool withPackage = true,
  }) {
    final t = _t;
    final parts = <Expression<bool>>[];
    final pkg = f.packageName;
    if (withPackage && pkg != null) parts.add(t.packageName.equals(pkg));
    final q = f.query;
    if (q != null) {
      final like = '%$q%';
      parts.add(
        t.title.lower().like(like) |
            t.body.lower().like(like) |
            t.appName.lower().like(like) |
            t.packageName.lower().like(like),
      );
    }
    final from = f.from;
    if (from != null) {
      parts.add(
        t.postedAt.isBiggerOrEqualValue(
          startOfDay(from).millisecondsSinceEpoch,
        ),
      );
    }
    final to = f.to;
    if (to != null) {
      final end = startOfDay(to).add(const Duration(days: 1));
      parts.add(t.postedAt.isSmallerThanValue(end.millisecondsSinceEpoch));
    }
    switch (f.kind) {
      case NotificationLogKind.all:
        break;
      case NotificationLogKind.money:
        parts.add(_mentionsMoney);
      case NotificationLogKind.transaction:
        parts.add(t.transactionId.isNotNull());
    }
    return parts.isEmpty ? const Constant(true) : Expression.and(parts);
  }

  /// `Rp10.000`, `Rp 10.000`, `Rp. 10.000`, `IDR 68,500` in title or text
  /// (GLOB: case-sensitive, so both cases of "rp" are spelled out).
  static const _mentionsMoney = CustomExpression<bool>(
    "((title || ' ' || body) GLOB '*[Rr][Pp][0-9]*'"
    " OR (title || ' ' || body) GLOB '*[Rr][Pp][ .][0-9]*'"
    " OR (title || ' ' || body) GLOB '*[Rr][Pp]. [0-9]*'"
    " OR (title || ' ' || body) GLOB '*IDR [0-9]*')",
  );

  SimpleSelectStatement<$CapturedNotificationsTable, CapturedNotificationRow>
  _select(NotificationLogFilter f) => _db.select(_t)
    ..where((_) => _matching(f))
    ..orderBy([
      (n) => OrderingTerm.desc(n.postedAt),
      (n) => OrderingTerm.desc(n.id),
    ]);

  @override
  Stream<List<CapturedNotification>> watch(
    NotificationLogFilter filter, {
    int limit = 300,
  }) => (_select(
    filter,
  )..limit(limit)).watch().map((rows) => [for (final r in rows) r.toEntity()]);

  @override
  Stream<List<NotificationSource>> watchSources(NotificationLogFilter filter) {
    final count = _t.id.count();
    final name = _t.appName.max();
    final last = _t.postedAt.max();
    final q = _db.selectOnly(_t)
      ..addColumns([_t.packageName, name, count, last])
      ..where(_matching(filter, withPackage: false))
      ..groupBy([_t.packageName])
      ..orderBy([OrderingTerm.desc(count), OrderingTerm.asc(_t.packageName)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          NotificationSource(
            packageName: r.read(_t.packageName)!,
            appName: r.read(name),
            count: r.read(count) ?? 0,
            lastPostedAt: switch (r.read(last)) {
              final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
              null => null,
            },
          ),
      ],
    );
  }

  @override
  Stream<List<NotificationDayCount>> watchDayCounts(
    NotificationLogFilter filter,
  ) {
    const day = CustomExpression<String>(
      "date(posted_at / 1000, 'unixepoch', 'localtime')",
    );
    final count = _t.id.count();
    final q = _db.selectOnly(_t)
      ..addColumns([day, count])
      ..where(_matching(filter))
      ..groupBy([day])
      ..orderBy([OrderingTerm.asc(day)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          NotificationDayCount(
            DateTime.parse(r.read(day)!),
            r.read(count) ?? 0,
          ),
      ],
    );
  }

  @override
  Stream<int> watchUnprocessedCount() {
    final count = _t.id.count();
    return (_db.selectOnly(_t)
          ..addColumns([count])
          ..where(_t.processed.equals(false)))
        .watchSingle()
        .map((r) => r.read(count) ?? 0)
        .distinct();
  }

  @override
  Future<List<CapturedNotification>> unprocessed({int limit = 50}) async {
    final rows =
        await (_db.select(_t)
              ..where((n) => n.processed.equals(false))
              ..orderBy([
                (n) => OrderingTerm.asc(n.postedAt),
                (n) => OrderingTerm.asc(n.id),
              ])
              ..limit(limit))
            .get();
    return [for (final r in rows) r.toEntity()];
  }

  @override
  Future<void> markProcessed(
    int id, {
    String? appName,
    String? ruleId,
    String? transactionId,
    TxType? txType,
    double? amount,
    String? parseError,
  }) => _db.transaction(() async {
    await (_db.update(_t)..where((n) => n.id.equals(id))).write(
      CapturedNotificationsCompanion(
        processed: const Value(true),
        ruleId: Value(ruleId),
        transactionId: Value(transactionId),
        txType: Value(txType?.wire),
        amount: Value(amount),
        parseError: Value(parseError),
      ),
    );
    if (appName != null && appName.trim().isNotEmpty) {
      // Resolve the label for every row of that app at once.
      final row = await (_db.select(
        _t,
      )..where((n) => n.id.equals(id))).getSingleOrNull();
      if (row != null) {
        await (_db.update(_t)..where(
              (n) => n.packageName.equals(row.packageName) & n.appName.isNull(),
            ))
            .write(CapturedNotificationsCompanion(appName: Value(appName)));
      }
    }
  });

  @override
  Future<List<CapturedNotification>> all(NotificationLogFilter filter) async =>
      [for (final r in await _select(filter).get()) r.toEntity()];

  @override
  Future<int> removeReposts() => _db.customUpdate(
    // Same rule as [insertCapturedNotification], for rows logged before it:
    // a row whose title/text equals the previous capture under the same
    // notification key, from an app no enabled rule watches, never turned
    // into a transaction.
    'DELETE FROM captured_notifications WHERE id IN ('
    ' SELECT id FROM ('
    '  SELECT id, title, body, package_name, transaction_id,'
    '   LAG(title) OVER w AS prev_title, LAG(body) OVER w AS prev_body'
    '  FROM captured_notifications WHERE notification_key IS NOT NULL'
    '  WINDOW w AS (PARTITION BY notification_key ORDER BY posted_at, id)'
    ' ) WHERE prev_title = title AND prev_body = body'
    '  AND transaction_id IS NULL'
    '  AND package_name NOT IN ('
    '   SELECT j.value FROM notification_rules r, json_each(r.packages) j'
    '   WHERE r.enabled = 1)'
    ')',
    updates: {_t},
    updateKind: UpdateKind.delete,
  );

  @override
  Future<void> delete(int id) =>
      (_db.delete(_t)..where((n) => n.id.equals(id))).go();

  @override
  Future<int> clear({String? packageName}) {
    final d = _db.delete(_t);
    if (packageName != null) d.where((n) => n.packageName.equals(packageName));
    return d.go();
  }
}

extension on NotificationRuleRow {
  NotificationRule toEntity() => NotificationRule(
    id: id,
    name: name,
    packages: _decodePackages(packages),
    matchField: RuleMatchField.fromWire(matchField),
    pattern: pattern,
    isRegex: isRegex,
    type: TxType.fromWire(type) == TxType.income
        ? TxType.income
        : TxType.expense,
    amountPattern: amountPattern,
    walletId: walletId,
    categoryId: categoryId,
    enabled: enabled,
    presetKey: presetKey,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

List<String> _decodePackages(String raw) {
  try {
    final v = jsonDecode(raw);
    if (v is List) return List.unmodifiable(v.whereType<String>());
  } on FormatException {
    // fall through
  }
  return const [];
}

class DriftNotificationRuleRepository implements NotificationRuleRepository {
  DriftNotificationRuleRepository(this._db);
  final AppDatabase _db;

  $NotificationRulesTable get _t => _db.notificationRules;

  SimpleSelectStatement<$NotificationRulesTable, NotificationRuleRow> _all() =>
      _db.select(_t)..orderBy([
        // User rules (no preset key) first.
        (r) => OrderingTerm.asc(r.presetKey.isNotNull()),
        (r) => OrderingTerm.asc(r.createdAt),
        (r) => OrderingTerm.asc(r.id),
      ]);

  @override
  Stream<List<NotificationRule>> watchAll() =>
      _all().watch().map((rows) => [for (final r in rows) r.toEntity()]);

  @override
  Future<List<NotificationRule>> getAll() async => [
    for (final r in await _all().get()) r.toEntity(),
  ];

  @override
  Stream<NotificationRule?> watchById(String id) =>
      (_db.select(_t)..where((r) => r.id.equals(id))).watchSingleOrNull().map(
        (r) => r?.toEntity(),
      );

  @override
  Future<NotificationRule?> getById(String id) async => (await (_db.select(
    _t,
  )..where((r) => r.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(NotificationRule rule) => _db
      .into(_t)
      .insertOnConflictUpdate(
        NotificationRulesCompanion.insert(
          id: rule.id,
          name: rule.name,
          packages: jsonEncode(rule.packages),
          matchField: Value(rule.matchField.wire),
          pattern: rule.pattern,
          isRegex: Value(rule.isRegex),
          type: rule.type.wire,
          amountPattern: Value(rule.amountPattern),
          walletId: Value(rule.walletId),
          categoryId: Value(rule.categoryId),
          enabled: Value(rule.enabled),
          presetKey: Value(rule.presetKey),
          createdAt: rule.createdAt,
          updatedAt: rule.updatedAt,
        ),
      );

  @override
  Future<void> delete(String id) =>
      (_db.delete(_t)..where((r) => r.id.equals(id))).go();
}
