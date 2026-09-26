import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';

/// A notification repost with the same app/title/text inside this window is
/// the same notification (apps re-notify on updates) and is not logged twice.
const kNotificationDedupeWindow = Duration(minutes: 2);

/// Stores one captured notification unless it's a repost (see
/// [kNotificationDedupeWindow]). Returns the new row id, or null when skipped.
/// Used by the listener callback, which may run in a background isolate.
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

  @override
  Stream<List<CapturedNotification>> watch({
    String? packageName,
    String? search,
    int limit = 300,
  }) {
    final q = _db.select(_t);
    if (packageName != null) q.where((n) => n.packageName.equals(packageName));
    final s = search?.trim().toLowerCase();
    if (s != null && s.isNotEmpty) {
      final like = '%$s%';
      q.where(
        (n) =>
            n.title.lower().like(like) |
            n.body.lower().like(like) |
            n.appName.lower().like(like) |
            n.packageName.lower().like(like),
      );
    }
    q
      ..orderBy([
        (n) => OrderingTerm.desc(n.postedAt),
        (n) => OrderingTerm.desc(n.id),
      ])
      ..limit(limit);
    return q.watch().map((rows) => [for (final r in rows) r.toEntity()]);
  }

  @override
  Stream<List<NotificationSource>> watchSources() {
    final count = _t.id.count();
    final name = _t.appName.max();
    final q = _db.selectOnly(_t)
      ..addColumns([_t.packageName, name, count])
      ..groupBy([_t.packageName])
      ..orderBy([OrderingTerm.desc(count)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          NotificationSource(
            packageName: r.read(_t.packageName)!,
            appName: r.read(name),
            count: r.read(count) ?? 0,
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
