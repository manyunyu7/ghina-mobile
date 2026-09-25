// Upgrade safety against the REAL server: a phone on app 1.0.5 (drift schema
// v4: finance, tasks, notes + content) with a realistic amount of data and a
// pending outbox is upgraded to the current app (schema v5: habits +
// investments). Nothing may be lost, the old outbox must push, and what the
// web created meanwhile — habits, habit logs, assets, trades and their
// `investment` cash transactions (which the v4 app stored as an unknown type
// without a balance effect) — must arrive through the forced full re-pull,
// with balances equal to the server's.
// Skipped unless GHINA_E2E_BASE_URL is set:
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_upgrade_v4_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/auth_api.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/habit_repositories.dart';
import 'package:ghina/data/repositories/investment_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/notes_repositories.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'local/generated_migrations/schema_v4.dart' as v4;

const emailPrefix = 'mobile-test-dart-up4-';
final repoRoot = Directory.current.parent.path;

String iso(DateTime d) => d.toUtc().toIso8601String();
int ms(Object? isoString) =>
    DateTime.parse(isoString! as String).millisecondsSinceEpoch;
int b(Object? v) => v == true ? 1 : 0;
Object? js(Object? v) => v == null ? null : jsonEncode(v);

void main() {
  final base = Platform.environment['GHINA_E2E_BASE_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDownAll(() async {
    if (base == null) return;
    await Process.run('node', [
      'scripts/e2e-helper.mjs',
      'cleanup',
      emailPrefix,
    ], workingDirectory: repoRoot);
  });

  test(
    'v1.0.5 phone (schema v4, ~1200 tx, notes, pending outbox) upgrades to v5 '
    'and pulls the web\'s habits and portfolio',
    () async {
      final rnd = Random(5);
      final tokens = MemoryTokenStore();
      final client = ApiClient(baseUrl: base!, tokens: tokens);
      final api = DioSyncApi(client);
      final email =
          '$emailPrefix${DateTime.now().millisecondsSinceEpoch}@example.test';
      final auth = await AuthApi(client).register('Up4', email, 'rahasia123');
      await tokens.writeToken(auth.token);
      final epoch = auth.user.syncEpoch;
      final uid = auth.user.id;

      var mseq = 0;
      PushMutation up(String entity, String id, Json data) => PushMutation(
        id: 'seed-${mseq++}',
        entity: entity,
        op: MutationOp.upsert,
        entityId: id,
        data: data,
        clientUpdatedAt: DateTime.now(),
      );
      Future<void> pushAll(List<PushMutation> ms) async {
        for (var i = 0; i < ms.length; i += 500) {
          final res = await api.push(
            ms.sublist(i, min(i + 500, ms.length)),
            epoch: epoch,
          );
          final bad = res.results.where((r) => r.status != PushStatus.applied);
          expect(bad, isEmpty, reason: '${bad.map((r) => r.error)}');
        }
      }

      // ---- 1. The account as the v4 app + web built it (server side).
      final start = await api.pull(0);
      final cats = start.changes[SyncEntity.categories]!;
      final expenseCats = [
        for (final c in cats)
          if (c['type'] == 'expense') c['id'] as String,
      ];
      const walletIds = ['u4-w-bca', 'u4-w-rdn', 'u4-w-tunai'];
      await pushAll([
        for (final (i, id) in walletIds.indexed)
          up(SyncEntity.wallets, id, {
            'name': ['BCA', 'RDN Ajaib', 'Tunai'][i],
            'type': ['bank', 'bank', 'cash'][i],
            'balance': [15000000, 20000000, 750000][i],
            'currency': 'IDR',
            'color': '#22c55e',
            'icon': 'wallet',
          }),
      ]);
      final now = DateTime.now();
      await pushAll([
        for (var i = 0; i < 1200; i++)
          up(SyncEntity.transactions, 'u4-t-$i', {
            'walletId': walletIds[i % 3 == 1 ? 0 : i % 3],
            'toWalletId': null,
            'categoryId': expenseCats[i % expenseCats.length],
            'type': 'expense',
            'amount': 1000 + rnd.nextInt(200) * 500,
            'note': i % 3 == 0 ? 'Catatan $i' : null,
            'date': iso(now.subtract(Duration(hours: i * 4))),
          }),
        for (var i = 0; i < 15; i++)
          up(SyncEntity.notes, 'u4-n-$i', {
            'title': 'Catatan $i',
            'body': 'Isi $i',
            'checklist': [],
            'labels': [],
            'color': null,
            'pinned': i == 0,
            'archived': false,
            'photos': [],
          }),
      ]);

      // The web (already on the habits/investments release) used the new
      // features; the v4 app pulled past habits/assets/trades without storing
      // them, and stored the `investment` transactions as an unknown type.
      final today = dateKey(now);
      String day(int ago) => dateKey(addDays(now, -ago));
      await pushAll([
        up(SyncEntity.habits, 'u4-h-air', {
          'name': 'Minum air',
          'emoji': '💧',
          'color': '#1CB0F6',
          'kind': 'build',
          'schedule': {'type': 'daily'},
          'target': {'type': 'count', 'goal': 8, 'unit': 'gelas'},
          'reminders': ['07:00', '12:00'],
          'private': false,
          'why': null,
          'startDate': day(40),
          'archived': false,
          'sortOrder': 0,
        }),
        up(SyncEntity.habits, 'u4-h-lari', {
          'name': 'Lari',
          'emoji': '🏃',
          'color': '#58CC02',
          'kind': 'build',
          'schedule': {
            'type': 'weekdays',
            'days': [1, 3, 5],
          },
          'target': {'type': 'duration', 'goal': 30},
          'reminders': [],
          'private': false,
          'why': null,
          'startDate': day(40),
          'archived': false,
          'sortOrder': 1,
        }),
        up(SyncEntity.habits, 'u4-h-rokok', {
          'name': 'Rokok',
          'emoji': '🚭',
          'color': '#FF4B4B',
          'kind': 'quit',
          'schedule': {'type': 'daily'},
          'target': {'type': 'check'},
          'reminders': ['21:00'],
          'private': true,
          'why': 'Biar napas lega',
          'startDate': day(60),
          'archived': false,
          'sortOrder': 2,
        }),
      ]);
      await pushAll([
        for (var i = 0; i < 30; i++)
          up(SyncEntity.habitLogs, 'u4-l-air-$i', {
            'habitId': 'u4-h-air',
            'date': day(i),
            'type': 'done',
            'value': 5 + i % 4,
            'note': i == 0 ? 'Hari ini segar' : null,
            'triggers': [],
            'at': null,
          }),
        up(SyncEntity.habitLogs, 'u4-l-air-skip', {
          'habitId': 'u4-h-air',
          'date': day(31),
          'type': 'skip',
          'value': null,
          'note': 'sakit',
          'triggers': [],
          'at': null,
        }),
        for (var i = 0; i < 10; i++)
          up(SyncEntity.habitLogs, 'u4-l-urge-$i', {
            'habitId': 'u4-h-rokok',
            'date': day(i * 2),
            'type': 'urge',
            'value': 1 + i % 3,
            'note': null,
            'triggers': ['stres', if (i.isEven) 'malam'],
            'at': iso(addDays(now, -i * 2)),
          }),
        up(SyncEntity.habitLogs, 'u4-l-relapse', {
          'habitId': 'u4-h-rokok',
          'date': day(9),
          'type': 'relapse',
          'value': 2,
          'note': 'lembur',
          'triggers': ['capek'],
          'at': iso(addDays(now, -9)),
        }),
      ]);
      Json asset(String kind, String symbol, String? name) => {
        'kind': kind,
        'symbol': symbol,
        'name': name,
        'currency': 'IDR',
        'priceMode': kind == 'gold' ? 'manual' : 'auto',
        'manualPrice': kind == 'gold' ? 1900000 : null,
        'manualPriceAt': kind == 'gold' ? iso(now) : null,
        'unit': null,
        'walletId': 'u4-w-rdn',
        'archived': false,
        'sortOrder': 0,
      };
      await pushAll([
        up(SyncEntity.assets, 'u4-a-bbca', asset('stock', 'BBCA', 'BCA')),
        up(SyncEntity.assets, 'u4-a-emas', asset('gold', 'ANTAM', 'Emas')),
      ]);
      // Trades with their cash transactions (pushed first, like the client).
      final trades = <(String, String, Json, num)>[
        (
          'u4-tr-1',
          'u4-a-bbca',
          {'type': 'buy', 'quantity': 500, 'price': 9000, 'fee': 6750},
          -(500 * 9000 + 6750),
        ),
        (
          'u4-tr-2',
          'u4-a-bbca',
          {'type': 'buy', 'quantity': 300, 'price': 9500, 'fee': 4275},
          -(300 * 9500 + 4275),
        ),
        (
          'u4-tr-3',
          'u4-a-bbca',
          {'type': 'sell', 'quantity': 200, 'price': 9800, 'fee': 4900},
          200 * 9800 - 4900,
        ),
        (
          'u4-tr-4',
          'u4-a-emas',
          {'type': 'buy', 'quantity': 5, 'price': 1800000, 'fee': 0},
          -(5 * 1800000),
        ),
      ];
      final cashTx = <String, num>{};
      await pushAll([
        for (final (i, (id, _, t, amount)) in trades.indexed)
          up(SyncEntity.transactions, '$id-cash', {
            'walletId': 'u4-w-rdn',
            'toWalletId': null,
            'categoryId': null,
            'type': 'investment',
            'amount': cashTx['$id-cash'] = amount,
            'note': '${t['type']} $i',
            'date': iso(addDays(now, -20 + i)),
          }),
      ]);
      await pushAll([
        for (final (i, (id, assetId, t, _)) in trades.indexed)
          up(SyncEntity.assetTrades, id, {
            'assetId': assetId,
            ...t,
            'amount': null,
            'ratio': null,
            'note': null,
            'date': iso(addDays(now, -20 + i)),
            'cashTransactionId': '$id-cash',
          }),
      ]);

      // The old app's last sync happened after all of that.
      await Future<void>.delayed(const Duration(seconds: 2));
      final snap = await api.pull(0);
      final sTx = snap.changes[SyncEntity.transactions]!;
      expect(sTx, hasLength(1204));
      expect(snap.changes[SyncEntity.habits], hasLength(3));
      expect(snap.changes[SyncEntity.habitLogs], hasLength(42));
      expect(snap.changes[SyncEntity.assetTrades], hasLength(4));
      final serverBal = {
        for (final w in snap.changes[SyncEntity.wallets]!)
          w['id'] as String: (w['balance'] as num).toDouble(),
      };
      final rdnExpected =
          20000000 + cashTx.values.fold<num>(0, (s, v) => s + v);
      expect(serverBal['u4-w-rdn'], closeTo(rdnExpected, 0.001));

      // ---- 2. The v4 database file on the phone.
      final dir = await Directory.systemTemp.createTemp('ghina_upgrade_v4');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ghina.sqlite');
      final old = v4.DatabaseAtV4(NativeDatabase(file));
      Future<void> ins(String sql, List<Object?> args) =>
          old.customStatement(sql, args);
      await old.transaction(() async {
        for (final w in snap.changes[SyncEntity.wallets]!) {
          await ins(
            'INSERT INTO wallets (id, name, type, balance, currency, color, icon, archived, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              w['id'], w['name'], w['type'], w['balance'], w['currency'], //
              w['color'], w['icon'], b(w['archived']),
              ms(w['createdAt']), ms(w['updatedAt']),
            ],
          );
        }
        for (final c in snap.changes[SyncEntity.categories]!) {
          await ins(
            'INSERT INTO categories (id, name, type, color, icon, created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
            [
              c['id'], c['name'], c['type'], c['color'], c['icon'], //
              ms(c['createdAt']), ms(c['updatedAt']),
            ],
          );
        }
        // Every transaction, `investment` ones as the v4 app stored them.
        for (final t in sTx) {
          await ins(
            'INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, photos, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            [
              t['id'], t['walletId'], t['toWalletId'], t['categoryId'], //
              t['type'], t['amount'], t['note'], ms(t['date']),
              jsonEncode(t['photos'] ?? const []),
              ms(t['createdAt']), ms(t['updatedAt']),
            ],
          );
        }
        for (final a in snap.changes[SyncEntity.taskAreas]!) {
          await ins(
            'INSERT INTO task_areas (id, name, code, color, icon, schedule, sort_order, archived, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              a['id'], a['name'], a['code'], a['color'], a['icon'], //
              js(a['schedule']), a['sortOrder'], b(a['archived']),
              ms(a['createdAt']), ms(a['updatedAt']),
            ],
          );
        }
        for (final l in snap.changes[SyncEntity.noteLabels] ?? const []) {
          await ins(
            'INSERT INTO note_labels (id, name, color, pinned_tab, sort_order, created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
            [
              l['id'], l['name'], l['color'], b(l['pinnedTab']), //
              l['sortOrder'], ms(l['createdAt']), ms(l['updatedAt']),
            ],
          );
        }
        for (final x in snap.changes[SyncEntity.notes]!) {
          await ins(
            'INSERT INTO notes (id, title, body, pinned, archived, search_text, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)',
            [
              x['id'], x['title'], x['body'], b(x['pinned']), //
              b(x['archived']), '${x['title']} ${x['body']}'.toLowerCase(),
              ms(x['createdAt']), ms(x['updatedAt']),
            ],
          );
        }
        await ins(
          'INSERT INTO sync_meta (id, cursor, epoch, user_id, last_sync_at, full_pull_required, tasks_seeded, notes_seeded, content_seeded) VALUES (1,?,?,?,?,0,1,1,1)',
          [snap.serverTime, snap.epoch, uid, snap.serverTime],
        );

        // Pending offline work, exactly as the v4 app queued it.
        final at = DateTime.now().millisecondsSinceEpoch;
        final newTx = {
          'walletId': 'u4-w-tunai',
          'toWalletId': null,
          'categoryId': expenseCats.first,
          'type': 'expense',
          'amount': 42000,
          'note': 'Offline',
          'date': iso(now),
          'photos': <String>[],
        };
        await ins(
          'INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, photos, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [
            'u4-new-1', 'u4-w-tunai', null, expenseCats.first, 'expense', //
            42000, 'Offline', now.millisecondsSinceEpoch, '[]', at, at,
          ],
        );
        await ins(
          'INSERT INTO outbox (mutation_id, entity, op, entity_id, data, base, is_create, in_flight, client_updated_at) VALUES (?,?,?,?,?,?,1,0,?)',
          [
            'old-tx-new',
            'transactions',
            'upsert',
            'u4-new-1',
            jsonEncode(newTx),
            null,
            at,
          ],
        );
      });
      expect(
        (await old.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        4,
      );
      await old.close();

      // ---- 3. Upgrade: open with the current app database.
      final db = AppDatabase(NativeDatabase(file));
      final outbox = Outbox(db);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        5,
      );
      expect(await db.select(db.transactions).get(), hasLength(1205));
      expect(await outbox.all(), hasLength(1));
      final meta0 = await db.getMeta();
      expect(meta0.fullPullRequired, isTrue);
      expect(meta0.userId, uid);
      expect(await db.select(db.habits).get(), isEmpty);

      // ---- 4. First sync of the upgraded app.
      const clock = SystemClock();
      final store = LocalStore(db, outbox, clock);
      final photos = InMemoryPhotoStore();
      final engine = SyncEngine(
        db: db,
        outbox: outbox,
        api: api,
        photos: photos,
      );
      final sw = Stopwatch()..start();
      await engine.syncNow();
      sw.stop();
      // ignore: avoid_print
      print(
        'v4→v5 first sync (push 1 + full pull): ${sw.elapsedMilliseconds} ms',
      );
      final meta = await db.getMeta();
      expect(meta.lastError, isNull);
      expect(meta.fullPullRequired, isFalse);
      expect(await outbox.all(), isEmpty);

      final after = await api.pull(0);
      expect(
        after.changes[SyncEntity.transactions]!.any(
          (t) => t['id'] == 'u4-new-1',
        ),
        isTrue,
      );
      // Local = server: transactions, balances (incl. the investment cash).
      expect(await db.select(db.transactions).get(), hasLength(1205));
      final wallets = DriftWalletRepository(store);
      final afterBal = {
        for (final w in after.changes[SyncEntity.wallets]!)
          w['id'] as String: (w['balance'] as num).toDouble(),
      };
      expect(afterBal['u4-w-tunai'], serverBal['u4-w-tunai']! - 42000);
      for (final w in await wallets.getAll()) {
        expect(w.balance, closeTo(afterBal[w.id]!, 0.001), reason: w.id);
      }
      final txRepo = DriftTransactionRepository(store, photos);
      final inv = await txRepo.list(type: TxType.investment);
      expect(inv, hasLength(4));

      // What the v4 app never stored arrives now.
      final habits = DriftHabitRepository(store);
      final logs = DriftHabitLogRepository(store);
      expect(await habits.getAll(), hasLength(3));
      final air = (await habits.getById('u4-h-air'))!;
      expect(air.target, HabitTarget.count(8, unit: 'gelas'));
      final lari = (await habits.getById('u4-h-lari'))!;
      expect(lari.schedule, HabitSchedule.weekdays(const [1, 3, 5]));
      expect(lari.target, HabitTarget.duration(30));
      final rokok = (await habits.getById('u4-h-rokok'))!;
      expect(rokok.isPrivate, isTrue);
      expect(rokok.why, 'Biar napas lega');
      expect(await logs.getAll(), hasLength(42));
      final airToday = habitToday(
        air,
        await logs.getAll(habitId: air.id),
        today,
      );
      expect(airToday.progress, 5);
      final rokokLogs = await logs.getAll(habitId: rokok.id);
      final t = habitToday(rokok, rokokLogs, today);
      expect(
        t.streak.current,
        9,
        reason: 'relapse 9 days ago → clean 8 + today',
      );
      expect(
        rokokLogs.firstWhere((l) => l.type == HabitLogType.relapse).triggers,
        ['capek'],
      );

      final assets = DriftAssetRepository(store);
      final tradeRepo = DriftAssetTradeRepository(store);
      expect(await assets.getAll(), hasLength(2));
      final bbca = deriveHolding(await tradeRepo.getAll(assetId: 'u4-a-bbca'));
      expect(bbca.shares, 600);
      expect(bbca.issues, isEmpty);
      final emas = (await assets.getById('u4-a-emas'))!;
      expect(emas.priceMode, PriceMode.manual);
      expect(emas.manualPrice, 1900000);
      for (final tr in await tradeRepo.getAll()) {
        expect(tr.cashTransactionId, '${tr.id}-cash');
      }

      // Notes survive untouched.
      expect(await DriftNoteRepository(store, photos).getAll(), hasLength(15));

      // A second sync is a no-op.
      await engine.syncNow();
      expect((await db.getMeta()).lastError, isNull);
      expect(await outbox.all(), isEmpty);

      await engine.dispose();
      await db.close();
    },
    skip: base == null ? 'set GHINA_E2E_BASE_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
