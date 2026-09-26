/// Pure logic of the notification parsing rules: rupiah amount parsing, rule
/// matching, the rule tester and the built-in presets.
library;

import '../entities/entities.dart';

// ---------------------------------------------------------------- amounts

/// One rupiah amount found in a text.
final class DetectedAmount {
  const DetectedAmount({
    required this.value,
    required this.text,
    required this.start,
  });

  final double value;

  /// The matched text (e.g. `Rp1.234.567`).
  final String text;

  /// Offset of [text] in the source.
  final int start;
}

final _currencyAmount = RegExp(
  r'(?:\bRp\.?|\bIDR)\s*[:\-]?\s*([0-9][0-9.,]*)'
  r'(?:\s*(rb|ribu|k|jt|juta)(?![a-z]))?',
  caseSensitive: false,
);

/// Numbers with thousand separators (`50.000`, `1,234,567.00`) — only used
/// when the text has no `Rp` / `IDR` amount. Plain digit runs (account
/// numbers, OTPs) are never taken as amounts.
final _groupedNumber = RegExp(
  r'(?<![0-9.,])\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?(?![0-9]|[.,]\d)',
);

/// Words right before an amount that mean "not the transaction amount".
const _skipBefore = ['saldo', 'sisa', 'biaya', 'admin', 'fee', 'limit'];

/// Parses a rupiah number, tolerant of `.`/`,` as thousands or decimal
/// separator: `1.234.567` → 1234567, `50.000,00` → 50000, `1,234,567.50` →
/// 1234567.5, `12,5` → 12.5, `50000` → 50000. Null when it isn't a number.
double? parseRupiahNumber(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\s ]'), '');
  s = s.replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');
  if (s.isEmpty || !RegExp(r'^[0-9.,]+$').hasMatch(s)) return null;
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  String intPart;
  var frac = '';
  if (lastDot >= 0 && lastComma >= 0) {
    // Both: the later one is the decimal separator.
    final dec = lastDot > lastComma ? lastDot : lastComma;
    intPart = s.substring(0, dec);
    frac = s.substring(dec + 1);
  } else if (lastDot >= 0 || lastComma >= 0) {
    final sep = lastDot >= 0 ? '.' : ',';
    final parts = s.split(sep);
    final tail = parts.last;
    if (parts.length > 2 || tail.length == 3) {
      intPart = parts.join(); // thousands: 1.234.567 / 50.000 / 1,234
    } else {
      intPart = parts.first; // decimal: 12,5 / 99.90
      frac = tail;
    }
  } else {
    intPart = s;
  }
  intPart = intPart.replaceAll(RegExp(r'[.,]'), '');
  if (intPart.isEmpty || frac.contains(RegExp(r'[.,]'))) return null;
  return double.tryParse(frac.isEmpty ? intPart : '$intPart.$frac');
}

double _applySuffix(double v, String? suffix) =>
    switch (suffix?.toLowerCase()) {
      'rb' || 'ribu' || 'k' => v * 1000,
      'jt' || 'juta' => v * 1000000,
      _ => v,
    };

/// Every positive rupiah amount in [text], in order. `Rp`/`IDR` amounts
/// (with `rb`/`jt` suffixes) are preferred; without any, grouped numbers
/// like `50.000` are used.
List<DetectedAmount> findRupiahAmounts(String text) {
  final out = <DetectedAmount>[];
  for (final m in _currencyAmount.allMatches(text)) {
    final v = parseRupiahNumber(m.group(1)!);
    if (v == null || v <= 0) continue;
    out.add(
      DetectedAmount(
        value: _applySuffix(v, m.group(2)),
        text: m.group(0)!.trim(),
        start: m.start,
      ),
    );
  }
  if (out.isNotEmpty) return out;
  for (final m in _groupedNumber.allMatches(text)) {
    final v = parseRupiahNumber(m.group(0)!);
    if (v == null || v <= 0) continue;
    out.add(DetectedAmount(value: v, text: m.group(0)!, start: m.start));
  }
  return out;
}

/// The transaction amount in [text]: the first rupiah amount not preceded by
/// "saldo"/"sisa"/"biaya"/"admin" (so "Transfer Rp50.000. Saldo Rp1.200.000"
/// → 50000), else the first one. With [customPattern] (a regex) its first
/// group — or the whole match — is parsed instead. Null when none is found or
/// the custom pattern is invalid.
DetectedAmount? detectRupiahAmount(String text, {String? customPattern}) {
  final custom = customPattern?.trim();
  if (custom != null && custom.isNotEmpty) {
    final re = tryRuleRegex(custom);
    if (re == null) return null;
    for (final m in re.allMatches(text)) {
      final raw = m.groupCount >= 1 && m.group(1) != null
          ? m.group(1)!
          : m.group(0)!;
      final inner = findRupiahAmounts(raw);
      final v = inner.isNotEmpty
          ? inner.first.value
          : parseRupiahNumber(raw.replaceAll(RegExp(r'[^0-9.,]'), ''));
      if (v != null && v > 0) {
        return DetectedAmount(value: v, text: m.group(0)!, start: m.start);
      }
    }
    return null;
  }
  final all = findRupiahAmounts(text);
  if (all.isEmpty) return null;
  final lower = text.toLowerCase();
  for (final a in all) {
    final from = a.start - 16 < 0 ? 0 : a.start - 16;
    final before = lower.substring(from, a.start);
    if (!_skipBefore.any(before.contains)) return a;
  }
  return all.first;
}

// ---------------------------------------------------------------- matching

/// Case-insensitive regex, or null when [pattern] is invalid.
RegExp? tryRuleRegex(String pattern) {
  try {
    return RegExp(pattern, caseSensitive: false, multiLine: true);
  } on FormatException {
    return null;
  }
}

/// Keywords of a non-regex pattern (`transfer masuk | dana masuk`).
List<String> ruleKeywords(String pattern) => [
  for (final k in pattern.split('|'))
    if (k.trim().isNotEmpty) k.trim().toLowerCase(),
];

String _ruleText(RuleMatchField field, String title, String body) =>
    switch (field) {
      RuleMatchField.title => title,
      RuleMatchField.body => body,
      RuleMatchField.any => '$title\n$body',
    };

bool ruleAppliesToPackage(NotificationRule rule, String packageName) {
  final p = packageName.trim().toLowerCase();
  return rule.packages.any((x) => x.trim().toLowerCase() == p);
}

/// Whether [rule]'s pattern matches the notification text (the app is not
/// checked — see [ruleAppliesToPackage]).
bool rulePatternMatches(NotificationRule rule, String title, String body) {
  final text = _ruleText(rule.matchField, title, body);
  if (rule.isRegex) {
    final re = tryRuleRegex(rule.pattern);
    return re != null && re.hasMatch(text);
  }
  final keywords = ruleKeywords(rule.pattern);
  if (keywords.isEmpty) return false;
  final lower = text.toLowerCase();
  return keywords.any(lower.contains);
}

/// The first enabled rule (in [rules] order) for this notification.
NotificationRule? findMatchingRule(
  List<NotificationRule> rules, {
  required String packageName,
  required String title,
  required String body,
}) {
  for (final r in rules) {
    if (!r.enabled) continue;
    if (!ruleAppliesToPackage(r, packageName)) continue;
    if (rulePatternMatches(r, title, body)) return r;
  }
  return null;
}

/// Result of "Tes rule" on a sample notification.
final class RuleTestResult {
  const RuleTestResult({
    required this.patternMatches,
    this.amount,
    this.patternError,
    this.amountPatternError,
  });

  final bool patternMatches;
  final DetectedAmount? amount;

  /// The regex pattern is invalid (Indonesian message).
  final String? patternError;
  final String? amountPatternError;

  /// A real notification like this would become a transaction.
  bool get wouldCreate =>
      patternMatches && amount != null && patternError == null;
}

/// Runs [rule] (package ignored) on a sample title/body.
RuleTestResult testNotificationRule(
  NotificationRule rule, {
  required String title,
  required String body,
}) {
  final patternError = rule.isRegex && tryRuleRegex(rule.pattern) == null
      ? 'Regex pola nggak valid'
      : null;
  final amountPattern = rule.amountPattern?.trim();
  final amountPatternError =
      amountPattern != null &&
          amountPattern.isNotEmpty &&
          tryRuleRegex(amountPattern) == null
      ? 'Regex nominal nggak valid'
      : null;
  return RuleTestResult(
    patternMatches:
        patternError == null && rulePatternMatches(rule, title, body),
    amount: detectRupiahAmount(
      '$title\n$body',
      customPattern: rule.amountPattern,
    ),
    patternError: patternError,
    amountPatternError: amountPatternError,
  );
}

/// Transaction note from a notification: `Judul — isi`, ≤ [max] chars.
String notificationTransactionNote(String title, String body, {int max = 200}) {
  final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  final b = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  final s = [t, b].where((x) => x.isNotEmpty).join(' — ');
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1).trimRight()}…';
}

// ---------------------------------------------------------------- presets

/// A built-in rule template. Presets are off until the user turns them on
/// (which creates a rule with [key] as its `presetKey`).
final class NotificationRulePreset {
  const NotificationRulePreset({
    required this.key,
    required this.appLabel,
    required this.name,
    required this.packages,
    required this.type,
    required this.pattern,
    this.isRegex = false,
    this.matchField = RuleMatchField.any,
  });

  final String key;

  /// Display name of the source app (`myBCA`).
  final String appLabel;
  final String name;
  final List<String> packages;
  final TxType type;
  final String pattern;
  final bool isRegex;
  final RuleMatchField matchField;
}

const _bankIncome =
    'dana masuk|transfer masuk|uang masuk|menerima|diterima|kredit|incoming';
const _bankExpense =
    'transfer keluar|transfer ke|transfer berhasil|pembayaran|bayar|debit|'
    'qris|tarik tunai|top up|pembelian';
const _walletIncome =
    'diterima|menerima|masuk|cashback|refund|pengembalian dana';
const _walletExpense =
    'pembayaran|bayar|berhasil dibayar|transfer ke|kirim uang|dikirim|'
    'pembelian|qris';

List<NotificationRulePreset> _pair(
  String key,
  String appLabel,
  List<String> packages, {
  String income = _bankIncome,
  String expense = _bankExpense,
  bool isRegex = false,
}) => [
  NotificationRulePreset(
    key: '$key.income',
    appLabel: appLabel,
    name: '$appLabel — uang masuk',
    packages: packages,
    type: TxType.income,
    pattern: income,
    isRegex: isRegex,
  ),
  NotificationRulePreset(
    key: '$key.expense',
    appLabel: appLabel,
    name: '$appLabel — uang keluar',
    packages: packages,
    type: TxType.expense,
    pattern: expense,
    isRegex: isRegex,
  ),
];

/// Presets for popular Indonesian banks and e-wallets. Income before expense
/// per app, so "Transfer masuk berhasil" is income. Package names are the
/// Play Store ids; notification wording varies per app version — users can
/// edit a preset rule (and test it) after turning it on.
final List<NotificationRulePreset> notificationRulePresets = List.unmodifiable([
  ..._pair('mybca', 'myBCA', ['com.bca.mybca.omni.android', 'com.bca']),
  ..._pair(
    'gopay',
    'GoPay',
    ['com.gojek.gopay', 'com.gojek.app'],
    income: _walletIncome,
    expense: _walletExpense,
  ),
  ..._pair(
    'ovo',
    'OVO',
    ['ovo.id'],
    income: _walletIncome,
    expense: _walletExpense,
  ),
  ..._pair(
    'dana',
    'DANA',
    ['id.dana'],
    income: _walletIncome,
    expense: _walletExpense,
  ),
  // The Shopee app also posts promos ("Voucher Rp50RB masuk!"), so the
  // patterns require "ShopeePay" in the text.
  ..._pair(
    'shopeepay',
    'ShopeePay',
    ['com.shopee.id'],
    income:
        r'shopeepay[\s\S]*(diterima|masuk|refund|pengembalian)|'
        r'(diterima|masuk|refund|pengembalian)[\s\S]*shopeepay',
    expense:
        r'shopeepay[\s\S]*(pembayaran|bayar|transfer)|'
        r'(pembayaran|bayar|transfer)[\s\S]*shopeepay',
    isRegex: true,
  ),
  ..._pair('brimo', 'BRImo', ['id.co.bri.brimo']),
  ..._pair('livin', "Livin' by Mandiri", ['id.bmri.livin']),
  ..._pair('bni', 'BNI Mobile', ['src.com.bni', 'id.bni.wondr']),
  ..._pair('seabank', 'SeaBank', ['id.co.bankbkemobile.digitalbank']),
  ..._pair('jago', 'Jago', ['com.jago.digitalBanking']),
  ..._pair('jenius', 'Jenius', ['com.btpn.dc']),
]);

NotificationRulePreset? notificationRulePreset(String key) =>
    notificationRulePresets.where((p) => p.key == key).firstOrNull;
