import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/repositories/notification_log_repositories.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../../domain/fakes.dart';

void main() {
  late AppDatabase db;
  late DriftCapturedNotificationRepository log;
  late DriftNotificationRuleRepository rules;
  late FakeWalletRepository wallets;
  late FakeTransactionRepository txs;
  late ProcessCapturedNotifications process;
  final clock = FixedClock(DateTime(2026, 9, 26, 10));
  final posted = DateTime(2026, 9, 26, 8, 30);

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = AppDatabase.memory();
    log = DriftCapturedNotificationRepository(db);
    rules = DriftNotificationRuleRepository(db);
    wallets = FakeWalletRepository()
      ..s.put(wallet('cash', createdAt: DateTime(2026)))
      ..s.put(wallet('bca', createdAt: DateTime(2026, 2)));
    txs = FakeTransactionRepository();
    final categories = FakeCategoryRepository()
      ..s.put(category('gaji', type: CategoryType.income));
    process = ProcessCapturedNotifications(
      log,
      rules,
      wallets,
      CreateTransaction(txs, wallets, categories, clock),
      (pkg) async => pkg == 'com.bca.mybca.omni.android' ? 'myBCA' : null,
    );
  });

  tearDown(() => db.close());

  Future<int?> capture(
    String title,
    String body, {
    String pkg = 'com.bca.mybca.omni.android',
    DateTime? at,
  }) => insertCapturedNotification(
    db,
    packageName: pkg,
    title: title,
    body: body,
    postedAt: at ?? posted,
    capturedAt: clock.now(),
  );

  test('reposts inside the dedupe window are logged once', () async {
    expect(await capture('Transfer Masuk', 'Rp 10.000'), isNotNull);
    expect(
      await capture(
        'Transfer Masuk',
        'Rp 10.000',
        at: posted.add(const Duration(seconds: 30)),
      ),
      isNull,
    );
    expect(
      await capture(
        'Transfer Masuk',
        'Rp 10.000',
        at: posted.add(const Duration(minutes: 10)),
      ),
      isNotNull,
    );
    expect(await log.watch().first, hasLength(2));
  });

  test(
    'watch: newest first, search and per-app filter; sources; clear',
    () async {
      await capture('Lama', 'satu', at: posted);
      await capture('Baru', 'dua', at: posted.add(const Duration(hours: 1)));
      await capture(
        'Chat',
        'halo',
        pkg: 'com.whatsapp',
        at: posted.subtract(const Duration(hours: 1)),
      );
      expect((await log.watch().first).map((n) => n.title), [
        'Baru',
        'Lama',
        'Chat',
      ]);
      expect((await log.watch(search: 'HALO').first).single.title, 'Chat');
      expect(await log.watch(packageName: 'com.whatsapp').first, hasLength(1));
      final sources = await log.watchSources().first;
      expect(sources.first.packageName, 'com.bca.mybca.omni.android');
      expect(sources.first.count, 2);
      expect(await log.clear(packageName: 'com.whatsapp'), 1);
      expect(await log.watch().first, hasLength(2));
    },
  );

  test(
    'matching notification becomes a transaction; others just processed',
    () async {
      final save = SaveNotificationRule(rules, clock);
      final r = await save(
        null,
        const NotificationRuleInput(
          name: 'BCA masuk',
          packages: ['com.bca.mybca.omni.android'],
          pattern: 'transfer masuk',
          type: TxType.income,
          walletId: 'bca',
          categoryId: 'gaji',
        ),
      );
      expect(r.isOk, isTrue);
      await capture('Transfer Masuk', 'Dana Rp 1.250.000 dari PT ABC');
      await capture('Promo', 'Diskon Rp 50.000');
      await capture(
        'Transfer Masuk',
        'cek aplikasi',
        at: posted.add(const Duration(hours: 2)),
      );
      expect(await log.watchUnprocessedCount().first, 3);

      final result = await process();
      expect(result.checked, 3);
      expect(result.created, hasLength(1));
      final tx = result.created.single;
      expect(tx.type, TxType.income);
      expect(tx.amount, 1250000);
      expect(tx.walletId, 'bca');
      expect(tx.categoryId, 'gaji');
      expect(tx.date, posted);
      expect(tx.note, 'Transfer Masuk — Dana Rp 1.250.000 dari PT ABC');

      final rows = await log.watch().first;
      final hit = rows.firstWhere((n) => n.transactionId != null);
      expect(hit.transactionId, tx.id);
      expect(hit.txType, TxType.income);
      expect(hit.amount, 1250000);
      expect(hit.appName, 'myBCA'); // resolved for every row of the app
      expect(rows.every((n) => n.processed), isTrue);
      final noAmount = rows.firstWhere((n) => n.body == 'cek aplikasi');
      expect(noAmount.parseError, isNotNull);
      expect(noAmount.transactionId, isNull);
      expect(await log.watchUnprocessedCount().first, 0);
      // Nothing left: a second run creates nothing.
      expect((await process()).created, isEmpty);
    },
  );

  test('preset enable creates a rule on the first active wallet', () async {
    final save = SaveNotificationRule(rules, clock);
    final setEnabled = SetNotificationRuleEnabled(rules, clock);
    final enable = EnableNotificationRulePreset(rules, save, setEnabled);
    expect(await enable('dana.expense'), isA<Ok<void>>());
    final all = await rules.getAll();
    expect(all.single.presetKey, 'dana.expense');
    expect(all.single.enabled, isTrue);
    expect(all.single.walletId, isNull);

    await capture('DANA', 'Pembayaran Rp 20.000 ke Warung', pkg: 'id.dana');
    final created = (await process()).created;
    expect(created.single.walletId, 'cash');
    expect(created.single.type, TxType.expense);

    // Off again → re-enabling reuses the same rule.
    await setEnabled(all.single.id, false);
    await enable('dana.expense');
    expect(await rules.getAll(), hasLength(1));
  });

  test('validation: package, keywords and regex', () async {
    final save = SaveNotificationRule(rules, clock);
    Future<String?> fieldOf(NotificationRuleInput i) async =>
        switch (await save(null, i)) {
          Err(:final failure) => failure.message,
          Ok() => null,
        };
    expect(
      await fieldOf(
        const NotificationRuleInput(
          name: 'x',
          packages: [],
          pattern: 'a',
          type: TxType.expense,
        ),
      ),
      isNotNull,
    );
    expect(
      await fieldOf(
        const NotificationRuleInput(
          name: 'x',
          packages: ['bukan paket'],
          pattern: 'a',
          type: TxType.expense,
        ),
      ),
      isNotNull,
    );
    expect(
      await fieldOf(
        const NotificationRuleInput(
          name: 'x',
          packages: ['id.dana'],
          pattern: '(',
          isRegex: true,
          type: TxType.expense,
        ),
      ),
      isNotNull,
    );
    expect(
      await fieldOf(
        const NotificationRuleInput(
          name: 'x',
          packages: ['id.dana'],
          pattern: ' | ',
          type: TxType.expense,
        ),
      ),
      isNotNull,
    );
  });

  test(
    'sign-out wipe clears the log and rules; data reset keeps them',
    () async {
      await capture('A', 'b');
      await SaveNotificationRule(rules, clock)(
        null,
        const NotificationRuleInput(
          name: 'x',
          packages: ['id.dana'],
          pattern: 'bayar',
          type: TxType.expense,
        ),
      );
      await db.wipe();
      expect(await log.watch().first, hasLength(1));
      expect(await rules.getAll(), hasLength(1));
      await db.wipe(includeMeta: true);
      expect(await log.watch().first, isEmpty);
      expect(await rules.getAll(), isEmpty);
    },
  );
}
