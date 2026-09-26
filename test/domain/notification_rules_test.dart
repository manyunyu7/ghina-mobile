import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

NotificationRule rule({
  String id = 'r1',
  List<String> packages = const ['com.bca.mybca.omni.android'],
  String pattern = 'transfer masuk|dana masuk',
  bool isRegex = false,
  RuleMatchField field = RuleMatchField.any,
  TxType type = TxType.income,
  String? amountPattern,
  bool enabled = true,
}) => NotificationRule(
  id: id,
  name: id,
  packages: packages,
  matchField: field,
  pattern: pattern,
  isRegex: isRegex,
  type: type,
  amountPattern: amountPattern,
  enabled: enabled,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('parseRupiahNumber', () {
    final cases = <String, double?>{
      '1.234.567': 1234567,
      '50.000': 50000,
      '50.000,00': 50000,
      '1,234,567.50': 1234567.5,
      '1,234': 1234,
      '25,000': 25000,
      '12,5': 12.5,
      '99.90': 99.9,
      '50000': 50000,
      '1.000.000,5': 1000000.5,
      '50.000.': 50000,
      '': null,
      'abc': null,
    };
    cases.forEach((raw, want) {
      test('"$raw" → $want', () => expect(parseRupiahNumber(raw), want));
    });
  });

  group('detectRupiahAmount', () {
    double? amount(String text, {String? pattern}) =>
        detectRupiahAmount(text, customPattern: pattern)?.value;

    test('common bank / e-wallet formats', () {
      expect(amount('Dana masuk Rp1.234.567 dari BUDI'), 1234567);
      expect(amount('Transfer Rp 50.000 berhasil'), 50000);
      expect(amount('Pembayaran Rp. 25.500,00 ke Kopi Kenangan'), 25500);
      expect(amount('You received IDR 1,500,000.00'), 1500000);
      expect(amount('Cashback Rp5rb masuk'), 5000);
      expect(amount('Gaji Rp 1,5 jt diterima'), 1500000);
      expect(amount('Rp: 75.000 dibayar'), 75000);
    });

    test('skips the balance ("saldo") when an amount comes first', () {
      expect(
        amount('Saldo Rp1.200.000. Transfer masuk Rp50.000 dari ANI'),
        50000,
      );
      expect(amount('Transfer Rp50.000 berhasil. Saldo Rp1.200.000'), 50000);
    });

    test('grouped numbers only without an Rp amount; never plain digits', () {
      expect(amount('Anda menerima 150.000 dari 1234567890'), 150000);
      expect(amount('Kode OTP 123456, rek 1234567890'), isNull);
      expect(amount('Rapat jam 12.30'), isNull);
    });

    test('custom regex: first group, else the whole match', () {
      expect(
        amount('Nominal: 2.500.000 IDR', pattern: r'Nominal:\s*([\d.]+)'),
        2500000,
      );
      expect(amount('Total 45.000', pattern: r'Total [\d.]+'), 45000);
      expect(amount('Total 45.000', pattern: r'(['), isNull);
    });
  });

  group('matching', () {
    test('keywords: any of them, case-insensitive, per field', () {
      final r = rule();
      expect(rulePatternMatches(r, 'Transfer Masuk', 'Rp 10.000'), isTrue);
      expect(rulePatternMatches(r, 'Info', 'DANA MASUK Rp 1'), isTrue);
      expect(rulePatternMatches(r, 'Promo', 'Diskon 50%'), isFalse);
      final titleOnly = rule(field: RuleMatchField.title);
      expect(rulePatternMatches(titleOnly, 'Info', 'dana masuk'), isFalse);
    });

    test('regex; an invalid regex never matches', () {
      final r = rule(pattern: r'transfer (masuk|dari)', isRegex: true);
      expect(rulePatternMatches(r, '', 'Transfer dari ANI'), isTrue);
      expect(
        rulePatternMatches(rule(pattern: '(', isRegex: true), '', '('),
        isFalse,
      );
    });

    test('first enabled rule for the package wins', () {
      final rules = [
        rule(id: 'off', enabled: false),
        rule(id: 'other', packages: ['id.dana']),
        rule(id: 'hit'),
        rule(id: 'later'),
      ];
      final hit = findMatchingRule(
        rules,
        packageName: 'com.bca.mybca.omni.android',
        title: 'Transfer masuk',
        body: 'Rp 10.000',
      );
      expect(hit?.id, 'hit');
      expect(
        findMatchingRule(
          rules,
          packageName: 'com.whatsapp',
          title: 'Transfer masuk',
          body: '',
        ),
        isNull,
      );
    });

    test('tester reports pattern, amount and invalid regexes', () {
      final ok = testNotificationRule(
        rule(),
        title: 'Transfer Masuk',
        body: 'Rp 150.000 dari BUDI',
      );
      expect(ok.wouldCreate, isTrue);
      expect(ok.amount?.value, 150000);
      final noAmount = testNotificationRule(
        rule(),
        title: 'Transfer Masuk',
        body: 'cek aplikasi',
      );
      expect(noAmount.patternMatches, isTrue);
      expect(noAmount.wouldCreate, isFalse);
      final bad = testNotificationRule(
        rule(pattern: '(', isRegex: true, amountPattern: '['),
        title: 'x',
        body: 'Rp 1.000',
      );
      expect(bad.patternError, isNotNull);
      expect(bad.amountPatternError, isNotNull);
      expect(bad.wouldCreate, isFalse);
    });
  });

  test('transaction note: "Judul — isi", collapsed and capped', () {
    expect(
      notificationTransactionNote('Transfer  Masuk', 'Rp 10.000\ndari ANI'),
      'Transfer Masuk — Rp 10.000 dari ANI',
    );
    final long = notificationTransactionNote('T', 'x' * 500);
    expect(long.length, 200);
    expect(long.endsWith('…'), isTrue);
  });

  group('presets', () {
    test('unique keys, income before expense per app, valid packages', () {
      final keys = notificationRulePresets.map((p) => p.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      for (var i = 0; i < notificationRulePresets.length; i += 2) {
        expect(notificationRulePresets[i].type, TxType.income);
        expect(notificationRulePresets[i + 1].type, TxType.expense);
      }
      for (final p in notificationRulePresets) {
        expect(
          p.packages.every(
            (x) => RegExp(r'^[A-Za-z][\w]*(\.[\w]+)+$').hasMatch(x),
          ),
          isTrue,
          reason: p.key,
        );
        if (p.isRegex) expect(tryRuleRegex(p.pattern), isNotNull);
      }
      expect(
        notificationRulePresets.map((p) => p.appLabel).toSet(),
        containsAll([
          'myBCA',
          'GoPay',
          'OVO',
          'DANA',
          'ShopeePay',
          'BRImo',
          "Livin' by Mandiri",
          'BNI Mobile',
          'SeaBank',
          'Jago',
          'Jenius',
        ]),
      );
    });

    NotificationRule fromPreset(String key) {
      final p = notificationRulePreset(key)!;
      return rule(
        id: key,
        packages: p.packages,
        pattern: p.pattern,
        isRegex: p.isRegex,
        type: p.type,
      );
    }

    test('myBCA: incoming transfer is income, payment is expense', () {
      final rules = [fromPreset('mybca.income'), fromPreset('mybca.expense')];
      NotificationRule? match(String title, String body) => findMatchingRule(
        rules,
        packageName: 'com.bca.mybca.omni.android',
        title: title,
        body: body,
      );
      expect(
        match('Transfer Masuk', 'Dana Rp 500.000 dari ANI berhasil')?.type,
        TxType.income,
      );
      expect(
        match('Pembayaran Berhasil', 'QRIS Rp 25.000 ke KOPI')?.type,
        TxType.expense,
      );
    });

    test('ShopeePay ignores Shopee promos', () {
      final rules = [
        fromPreset('shopeepay.income'),
        fromPreset('shopeepay.expense'),
      ];
      NotificationRule? match(String title, String body) => findMatchingRule(
        rules,
        packageName: 'com.shopee.id',
        title: title,
        body: body,
      );
      expect(match('Voucher Rp50RB masuk!', 'Cek sekarang'), isNull);
      expect(
        match('ShopeePay', 'Pembayaran Rp 30.000 berhasil')?.type,
        TxType.expense,
      );
      expect(
        match('ShopeePay', 'Dana Rp 100.000 diterima')?.type,
        TxType.income,
      );
    });
  });

  test('parsePackageList splits and dedupes', () {
    expect(parsePackageList(' id.dana, ovo.id\nid.dana ;com.bca '), [
      'id.dana',
      'ovo.id',
      'com.bca',
    ]);
  });
}
