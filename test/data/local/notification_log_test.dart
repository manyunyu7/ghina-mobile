import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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

  const all = NotificationLogFilter();

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
    String? key,
  }) => insertCapturedNotification(
    db,
    packageName: pkg,
    title: title,
    body: body,
    notificationKey: key,
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
    expect(await log.watch(all).first, hasLength(2));
  });

  test('messenger re-posts under the same key are logged once', () async {
    Future<int?> wa(String body, int minutes) => capture(
      'Budi',
      body,
      pkg: 'com.whatsapp.w4b',
      key: '0|com.whatsapp.w4b|1|budi',
      at: posted.add(Duration(minutes: minutes)),
    );
    expect(await wa('Halow', 0), isNotNull);
    expect(await wa('Halow', 25), isNull, reason: 're-posted later');
    expect(await wa('Udah sampai?', 40), isNotNull);
    expect(await wa('Udah sampai?', 90), isNull);
    expect(await log.watch(all).first, hasLength(2));
  });

  test('apps watched by a rule keep identical notifications', () async {
    await SaveNotificationRule(rules, clock)(
      null,
      const NotificationRuleInput(
        name: 'QRIS',
        packages: ['com.gojek.gopaymerchant'],
        pattern: 'QRIS',
        type: TxType.income,
        walletId: 'bca',
      ),
    );
    for (final m in [0, 10, 20]) {
      expect(
        await capture(
          'Pembayaran QRIS diterima',
          'Rp 10.000',
          pkg: 'com.gojek.gopaymerchant',
          key: '0|com.gojek.gopaymerchant|7|null',
          at: posted.add(Duration(minutes: m)),
        ),
        isNotNull,
      );
    }
  });

  test(
    'removeReposts drops old reposts, keeps changes and rule apps',
    () async {
      Future<void> raw(String pkg, String key, String body, int minutes) => db
          .into(db.capturedNotifications)
          .insert(
            CapturedNotificationsCompanion.insert(
              packageName: pkg,
              title: const Value('t'),
              body: Value(body),
              notificationKey: Value(key),
              postedAt: posted.add(Duration(minutes: minutes)),
              capturedAt: posted,
            ),
          )
          .then((_) {});
      await raw('com.whatsapp', 'a', 'Halow', 0);
      await raw('com.whatsapp', 'a', 'Halow', 5);
      await raw('com.whatsapp', 'b', 'Halow', 6); // other chat
      await raw('com.whatsapp', 'a', 'Lagi', 7);
      await raw('com.whatsapp', 'a', 'Lagi', 30);
      await raw('com.gojek.gopaymerchant', 'g', 'Rp 10.000', 0);
      await raw('com.gojek.gopaymerchant', 'g', 'Rp 10.000', 9);
      await SaveNotificationRule(rules, clock)(
        null,
        const NotificationRuleInput(
          name: 'QRIS',
          packages: ['com.gojek.gopaymerchant'],
          pattern: 'Rp',
          type: TxType.income,
          walletId: 'bca',
        ),
      );
      expect(await log.removeReposts(), 2);
      expect(await log.removeReposts(), 0);
      expect(await log.all(all), hasLength(5));
    },
  );

  test('filters: date range, kind, sources and day counts', () async {
    final d1 = DateTime(2026, 10, 1, 9);
    final d2 = DateTime(2026, 10, 2, 21);
    final d3 = DateTime(2026, 10, 3, 7);
    await capture('Promo', 'Diskon besar', pkg: 'com.shopee', at: d1);
    await capture(
      'Jago',
      'You received Rp10.000 from Budi',
      pkg: 'com.jago',
      at: d2,
    );
    await capture(
      'OVO',
      'Bayar Rp 186.480 di TIKTOK',
      pkg: 'com.ovo',
      at: d2.add(const Duration(minutes: 5)),
    );
    await capture('Chat', 'Halo rpm motor', pkg: 'com.whatsapp', at: d3);
    await capture(
      'Chat',
      'IDR 68,500 spent',
      pkg: 'com.whatsapp',
      at: d3.add(const Duration(minutes: 9)),
    );

    Future<List<String>> titles(NotificationLogFilter f) async => [
      for (final n in await log.watch(f).first) n.title,
    ];

    expect(
      await titles(
        NotificationLogFilter(
          from: DateTime(2026, 10, 2),
          to: DateTime(2026, 10, 2),
        ),
      ),
      ['OVO', 'Jago'],
    );
    expect(await titles(NotificationLogFilter(from: DateTime(2026, 10, 2))), [
      'Chat',
      'Chat',
      'OVO',
      'Jago',
    ]);
    expect(await titles(NotificationLogFilter(to: DateTime(2026, 10, 1))), [
      'Promo',
    ]);
    expect(
      [
        for (final n
            in await log
                .watch(
                  const NotificationLogFilter(kind: NotificationLogKind.money),
                )
                .first)
          n.body,
      ],
      [
        'IDR 68,500 spent',
        'Bayar Rp 186.480 di TIKTOK',
        'You received Rp10.000 from Budi',
      ],
      reason: '"rpm" is not money',
    );
    expect(
      await log
          .watch(
            const NotificationLogFilter(kind: NotificationLogKind.transaction),
          )
          .first,
      isEmpty,
    );
    expect(await log.watch(all, limit: 2).first, hasLength(2));

    final sources = await log
        .watchSources(
          NotificationLogFilter(
            packageName: 'com.jago',
            from: DateTime(2026, 10, 2),
          ),
        )
        .first;
    expect(
      sources.map((s) => s.packageName),
      ['com.whatsapp', 'com.jago', 'com.ovo'],
      reason: 'app filter ignored, date range applied',
    );
    expect(sources.first.count, 2);
    expect(sources.first.lastPostedAt, d3.add(const Duration(minutes: 9)));

    final days = await log.watchDayCounts(all).first;
    expect(
      [for (final d in days) (d.day, d.count)],
      [
        (DateTime(2026, 10, 1), 1),
        (DateTime(2026, 10, 2), 2),
        (DateTime(2026, 10, 3), 2),
      ],
    );
    final ids = [for (final n in await log.watch(all).first) n.id];
    await log.delete(ids.first);
    expect(await log.all(all), hasLength(4));
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
      expect((await log.watch(all).first).map((n) => n.title), [
        'Baru',
        'Lama',
        'Chat',
      ]);
      expect(
        (await log.watch(const NotificationLogFilter(search: 'HALO')).first)
            .single
            .title,
        'Chat',
      );
      expect(
        await log
            .watch(const NotificationLogFilter(packageName: 'com.whatsapp'))
            .first,
        hasLength(1),
      );
      final sources = await log.watchSources(all).first;
      expect(sources.first.packageName, 'com.bca.mybca.omni.android');
      expect(sources.first.count, 2);
      expect(await log.clear(packageName: 'com.whatsapp'), 1);
      expect(await log.watch(all).first, hasLength(2));
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

      final rows = await log.watch(all).first;
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
      expect(await log.watch(all).first, hasLength(1));
      expect(await rules.getAll(), hasLength(1));
      await db.wipe(includeMeta: true);
      expect(await log.watch(all).first, isEmpty);
      expect(await rules.getAll(), isEmpty);
    },
  );
}
