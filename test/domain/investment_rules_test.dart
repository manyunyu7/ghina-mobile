// Parity with the server's pure investments module and price cache rules:
// the cases of `scripts/test-investments.mjs` that apply to the app.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/investment_rules.dart';

final _c0 = DateTime.utc(2026, 1, 1);

AssetTrade T(
  TradeType type,
  String date, {
  double? quantity,
  double? price,
  double fee = 0,
  double? amount,
  double? ratio,
  DateTime? createdAt,
}) => AssetTrade(
  id: '${type.wire}-$date-${quantity ?? amount ?? ratio ?? ''}',
  assetId: 'a',
  type: type,
  date: DateTime.parse('${date}T03:00:00.000Z'),
  quantity: quantity,
  price: price,
  fee: fee,
  amount: amount,
  ratio: ratio,
  createdAt: createdAt ?? _c0,
  updatedAt: _c0,
);

Asset asset(AssetKind kind, String symbol, {String? unit}) => Asset(
  id: 'a',
  kind: kind,
  symbol: symbol,
  unit: unit ?? kind.defaultUnit,
  createdAt: _c0,
  updatedAt: _c0,
);

String? err(void Function() f) {
  try {
    f();
    return null;
  } on ValidationFailure catch (e) {
    return e.message;
  }
}

Matcher near(double v, [double e = 1e-6]) => closeTo(v, e);

void main() {
  test('constants / lots / fees', () {
    expect(
      [for (final k in AssetKind.values) k.wire],
      ['stock', 'fund', 'gold', 'crypto', 'bond', 'other'],
    );
    expect(AssetKind.gold.defaultUnit, 'gram');
    expect(lotsToShares(10), 1000);
    expect(sharesToLots(250), 2.5);
    expect(isWholeLots(1000), isTrue);
    expect(isWholeLots(150), isFalse);
    expect(FeePreset.standard.buy, 0.0015);
    expect(FeePreset.standard.sell, 0.0025);
    expect(FeePreset.standard.feeFor(TradeType.buy, 9500000), 14250);
    expect(FeePreset.standard.feeFor(TradeType.sell, 10000000), 25000);
    expect(const FeePreset(buy: 0.01, sell: 0).feeFor(TradeType.buy, 1000), 10);
    expect(FeePreset.standard.feeFor(TradeType.sell, 0), 0);
  });

  test('symbols', () {
    expect(requireAssetSymbol(AssetKind.stock, ' bbca.jk '), 'BBCA');
    expect(err(() => requireAssetSymbol(AssetKind.stock, 'BB CA')), isNotNull);
    expect(err(() => requireAssetSymbol(AssetKind.stock, '')), isNotNull);
    expect(requireAssetSymbol(AssetKind.crypto, 'btc-idr'), 'BTC');
    expect(requireAssetSymbol(AssetKind.fund, ' Sucor MM '), 'Sucor MM');
    expect(err(() => requireAssetSymbol(AssetKind.gold, 'x' * 21)), isNotNull);
    expect(
      err(() => requireAssetSymbol(AssetKind.stock, '!!')),
      contains('Kode saham'),
    );
    expect(
      assetKeyOf(AssetKind.fund, 'abc'),
      assetKeyOf(AssetKind.fund, 'ABC'),
    );
    expect(err(() => assetCurrency('rupiah')), isNotNull);
    expect(assetCurrency(null), 'IDR');
    expect(assetUnit(AssetKind.gold, null), 'gram');
  });

  group('holding derivation (average cost)', () {
    final trades = [
      T(TradeType.buy, '2026-01-10', quantity: 1000, price: 9000, fee: 13500),
      T(TradeType.buy, '2026-02-10', quantity: 1000, price: 10000, fee: 15000),
      T(TradeType.sell, '2026-03-10', quantity: 500, price: 11000, fee: 13750),
      T(TradeType.dividend, '2026-04-10', amount: 200000),
      T(TradeType.fee, '2026-05-10', amount: 5000),
    ];
    test('buys, sell, dividend, fee (any input order)', () {
      final h = deriveHolding(trades.reversed);
      expect(h.shares, 1500);
      expect(h.cost, near(14271375));
      expect(h.avgPrice, near(9514.25));
      expect(h.realized, near(724125));
      expect(h.dividends, near(200000));
      expect(h.fees, near(13500 + 15000 + 13750 + 5000));
      expect(h.issues, isEmpty);
      expect(tradeSequenceError(trades), isNull);
    });
    test('split: shares ×5, cost unchanged, avg ÷5', () {
      final s = deriveHolding([
        T(TradeType.buy, '2026-01-01', quantity: 100, price: 5000),
        T(TradeType.split, '2026-02-01', ratio: 5),
      ]);
      expect((s.shares, s.cost, s.avgPrice), (500, 500000, 1000));
    });
    test('full exit: 0 shares, 0 cost, avg null, realized 59,100', () {
      final f = deriveHolding([
        T(TradeType.buy, '2026-01-01', quantity: 300, price: 1000),
        T(TradeType.sell, '2026-02-01', quantity: 300, price: 1200, fee: 900),
      ]);
      expect((f.shares, f.cost, f.avgPrice), (0, 0, null));
      expect(f.realized, near(59100));
    });
    test('sell more than held → issue (Indonesian) + clamped', () {
      final over = [
        T(TradeType.buy, '2026-01-01', quantity: 100, price: 1000),
        T(TradeType.sell, '2026-02-01', quantity: 150, price: 1000),
      ];
      final h = deriveHolding(over);
      expect(h.issues, hasLength(1));
      expect(h.shares, 0);
      expect(
        tradeSequenceError(over),
        'Jumlah jual (150) melebihi kepemilikan (100) per 2026-02-01',
      );
    });
    test('date order matters; same date: createdAt breaks the tie', () {
      expect(
        tradeSequenceError([
          T(TradeType.sell, '2026-01-01', quantity: 100, price: 1000),
          T(TradeType.buy, '2026-02-01', quantity: 100, price: 1000),
        ]),
        isNotNull,
      );
      final buy = T(
        TradeType.buy,
        '2026-01-01',
        quantity: 100,
        price: 1000,
        createdAt: DateTime.utc(2026, 1, 1, 5),
      );
      final sell = T(
        TradeType.sell,
        '2026-01-01',
        quantity: 100,
        price: 1100,
        createdAt: DateTime.utc(2026, 1, 1, 6),
      );
      expect(tradeSequenceError([buy, sell]), isNull);
      final buyLater = T(
        TradeType.buy,
        '2026-01-01',
        quantity: 100,
        price: 1000,
        createdAt: DateTime.utc(2026, 1, 1, 7),
      );
      expect(tradeSequenceError([sell, buyLater]), isNotNull);
    });
    test('float tolerance (0.1 + 0.2 crypto)', () {
      expect(
        tradeSequenceError([
          T(TradeType.buy, '2026-01-01', quantity: 0.1, price: 1),
          T(TradeType.buy, '2026-01-02', quantity: 0.2, price: 1),
          T(TradeType.sell, '2026-01-03', quantity: 0.3, price: 1),
        ]),
        isNull,
      );
    });
    test('change check: only newly introduced oversells are refused', () {
      final base = [
        T(TradeType.buy, '2026-01-01', quantity: 100, price: 1000),
        T(TradeType.sell, '2026-02-01', quantity: 100, price: 1000),
      ];
      final bigger = T(
        TradeType.sell,
        '2026-02-01',
        quantity: 150,
        price: 1000,
      ).copyWith();
      expect(tradeChangeError(base, base[1].id, bigger), isNotNull);
      expect(tradeChangeError(base, 'new', null), isNull);
      // An oversell that already existed doesn't block an unrelated edit.
      final broken = [
        ...base,
        T(TradeType.sell, '2026-03-01', quantity: 50, price: 1),
      ];
      expect(
        tradeChangeError(
          broken,
          'x',
          T(TradeType.dividend, '2026-04-01', amount: 5),
        ),
        isNull,
      );
    });
  });

  test('valuation / allocation', () {
    final h = deriveHolding([
      T(TradeType.buy, '2026-01-01', quantity: 1000, price: 9000, fee: 13500),
    ]);
    final v = valueHolding(h, 9500, 9400);
    expect(v.marketValue, 9500000);
    expect(v.unrealized, 486500);
    expect(v.unrealizedPct, near(486500 / 9013500 * 100));
    expect(v.dayChange, 100000);
    expect(v.dayChangePct, near(100 / 9400 * 100));
    expect(v.totalReturn, 486500);
    final nv = valueHolding(h, null);
    expect(
      (nv.marketValue, nv.unrealized, nv.dayChange, nv.totalReturn),
      (null, null, null, 0),
    );
    final al = allocation([
      (key: 'a', label: 'BBCA', value: 300),
      (key: 'b', label: 'BTC', value: 100),
      (key: 'a', label: 'BBCA', value: 100),
      (key: 'c', label: 'X', value: 0),
      (key: 'd', label: 'Y', value: null),
    ]);
    expect(
      [for (final x in al) (x.key, x.value, x.pct)],
      [('a', 400, 80), ('b', 100, 20)],
    );
  });

  group('cash effect', () {
    AssetTrade t(
      TradeType type, {
      double? q,
      double? p,
      double fee = 0,
      double? amount,
    }) =>
        T(type, '2026-09-25', quantity: q, price: p, fee: fee, amount: amount);
    test('buy/sell/fee/dividend/split', () {
      expect(tradeCashEffect(t(TradeType.buy, q: 1000, p: 9500, fee: 14250)), (
        type: TxType.investment,
        amount: -9514250.0,
      ));
      expect(tradeCashEffect(t(TradeType.sell, q: 500, p: 10000, fee: 12500)), (
        type: TxType.investment,
        amount: 4987500.0,
      ));
      expect(tradeCashEffect(t(TradeType.fee, amount: 5000)), (
        type: TxType.investment,
        amount: -5000.0,
      ));
      expect(tradeCashEffect(t(TradeType.dividend, amount: 200000)), (
        type: TxType.income,
        amount: 200000.0,
      ));
      expect(
        tradeCashEffect(T(TradeType.split, '2026-09-25', ratio: 2)),
        isNull,
      );
      expect(tradeCashEffect(t(TradeType.sell, q: 1, p: 10, fee: 10)), isNull);
    });
    test('rounded to 2 decimals', () {
      expect(
        tradeCashEffect(t(TradeType.buy, q: 0.5, p: 1000.555))!.amount,
        -500.28,
      );
    });
    test('notes', () {
      expect(
        tradeTransactionNote(
          t(TradeType.buy, q: 1000, p: 9500),
          asset(AssetKind.stock, 'BBCA'),
        ),
        'Beli BBCA 10 lot @ 9.500',
      );
      expect(
        tradeTransactionNote(
          t(TradeType.sell, q: 0.5, p: 1e9),
          asset(AssetKind.crypto, 'BTC', unit: 'koin'),
        ),
        'Jual BTC 0,5 koin @ 1.000.000.000',
      );
      expect(
        tradeTransactionNote(
          t(TradeType.dividend, amount: 1),
          asset(AssetKind.stock, 'BBRI'),
        ),
        'Dividen BBRI',
      );
    });
    test('linked tx checks; dividend category id', () {
      expect(
        linkedTransactionError(TradeType.buy, TxType.investment, -5),
        isNull,
      );
      expect(
        linkedTransactionError(TradeType.buy, TxType.investment, 5),
        isNotNull,
      );
      expect(
        linkedTransactionError(TradeType.sell, TxType.expense, 5),
        isNotNull,
      );
      expect(
        linkedTransactionError(TradeType.dividend, TxType.income, 5),
        isNull,
      );
      expect(
        linkedTransactionError(TradeType.split, TxType.investment, 1),
        isNotNull,
      );
      expect(dividendCategoryId('u1'), 'category-dividen-u1');
      expect(dividendCategoryName, 'Dividen');
    });
  });

  test('investment transaction type: signed, balance-only', () {
    expect(TxType.loggable, isNot(contains(TxType.investment)));
    expect(TxType.investment.isSigned, isTrue);
    expect(
      ledgerEffects(type: TxType.investment, amount: -500, walletId: 'w'),
      {'w': -500},
    );
    final before = Transaction(
      id: 't',
      walletId: 'w',
      type: TxType.investment,
      amount: -500,
      date: _c0,
      createdAt: _c0,
      updatedAt: _c0,
    );
    final after = Transaction(
      id: 't',
      walletId: 'w',
      type: TxType.investment,
      amount: 300,
      date: _c0,
      createdAt: _c0,
      updatedAt: _c0,
    );
    expect(effectDelta(before, after), {'w': 800});
  });

  group('prices: session / freshness', () {
    DateTime wib(String s) => DateTime.parse('$s+07:00');
    test('IDX open Fri 10:00 WIB, closed 16:15, 08:59, Saturday', () {
      expect(isIdxSessionOpen(wib('2026-09-25T10:00:00')), isTrue);
      expect(isIdxSessionOpen(wib('2026-09-25T16:15:00')), isFalse);
      expect(isIdxSessionOpen(wib('2026-09-25T16:14:59')), isTrue);
      expect(isIdxSessionOpen(wib('2026-09-25T08:59:00')), isFalse);
      expect(isIdxSessionOpen(wib('2026-09-26T10:00:00')), isFalse);
    });
    test('last close: Sat → Fri 16:15; Mon 08:00 → Fri; Mon 17:00 → Mon', () {
      expect(
        lastIdxClose(wib('2026-09-26T12:00:00')),
        wib('2026-09-25T16:15:00'),
      );
      expect(
        lastIdxClose(wib('2026-09-28T08:00:00')),
        wib('2026-09-25T16:15:00'),
      );
      expect(
        lastIdxClose(wib('2026-09-28T17:00:00')),
        wib('2026-09-28T16:15:00'),
      );
    });
    test('fresh: open → 15 min; closed → until the next session', () {
      final s = AssetKind.stock;
      expect(
        isPriceFresh(s, wib('2026-09-25T10:00:00'), wib('2026-09-25T10:14:00')),
        isTrue,
      );
      expect(
        isPriceFresh(s, wib('2026-09-25T10:00:00'), wib('2026-09-25T10:16:00')),
        isFalse,
      );
      expect(
        isPriceFresh(s, wib('2026-09-25T16:20:00'), wib('2026-09-28T08:59:00')),
        isTrue,
      );
      expect(
        isPriceFresh(s, wib('2026-09-25T16:20:00'), wib('2026-09-28T09:00:00')),
        isFalse,
      );
      expect(
        isPriceFresh(s, wib('2026-09-25T16:00:00'), wib('2026-09-25T20:00:00')),
        isFalse,
      );
      expect(
        isPriceFresh(
          AssetKind.crypto,
          wib('2026-09-26T10:00:00'),
          wib('2026-09-26T10:20:00'),
        ),
        isFalse,
      );
    });
  });

  group('portfolio', () {
    final now = DateTime.utc(2026, 9, 25, 3);
    Asset a(
      String id,
      AssetKind k,
      String sym, {
      bool manual = false,
      double? mp,
      bool archived = false,
    }) => Asset(
      id: id,
      kind: k,
      symbol: sym,
      priceMode: manual ? PriceMode.manual : PriceMode.auto,
      manualPrice: mp,
      archived: archived,
      createdAt: _c0,
      updatedAt: _c0,
    );
    AssetTrade buy(String asset, double q, double p) => T(
      TradeType.buy,
      '2026-01-01',
      quantity: q,
      price: p,
    ).copyWith(assetId: asset);
    SecurityPrice price(String sym, double p, {double? prev}) => SecurityPrice(
      kind: AssetKind.stock,
      symbol: sym,
      price: p,
      prevClose: prev,
      fetchedAt: now,
      cachedAt: now,
    );

    test('values auto/manual, counts cost without a price, skips archived', () {
      final p = buildPortfolio(
        assets: [
          a('s', AssetKind.stock, 'BBCA'),
          a('g', AssetKind.gold, 'ANTAM', manual: true, mp: 1000000),
          a('u', AssetKind.stock, 'TLKM'),
          a('x', AssetKind.stock, 'GOTO', archived: true),
        ],
        trades: [
          buy('s', 100, 9000),
          buy('g', 2, 900000),
          buy('u', 100, 3000),
          buy('x', 100, 100),
        ],
        prices: {'stock:BBCA': price('BBCA', 9500, prev: 9400)},
        now: now,
      );
      expect(p.holdings, hasLength(3));
      expect(p.marketValue, 950000 + 2000000 + 300000);
      expect(p.cost, 900000 + 1800000 + 300000);
      expect(p.unrealized, 50000 + 200000);
      expect(p.unpricedCount, 1);
      expect(p.dayChange, 10000);
      expect(p.byAsset.first.key, 'g');
      expect(p.byKind.map((s) => s.key), ['gold', 'stock']);
      expect(p.holding('u')!.marketValue, isNull);
      expect(p.holding('u')!.value, 300000);
      expect(p.holding('g')!.quote.isManual, isTrue);
    });
  });
}
