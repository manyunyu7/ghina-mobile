import 'enums.dart';

/// One notification from another app, captured by the Android notification
/// listener ("Log Notifikasi"). Device-only, never synced.
final class CapturedNotification {
  const CapturedNotification({
    required this.id,
    required this.packageName,
    this.appName,
    required this.title,
    required this.body,
    required this.postedAt,
    required this.capturedAt,
    this.processed = false,
    this.ruleId,
    this.transactionId,
    this.txType,
    this.amount,
    this.parseError,
  });

  final int id;
  final String packageName;

  /// App label from the launcher; null until resolved (the background
  /// isolate can't look it up) — show [displayAppName].
  final String? appName;
  final String title;
  final String body;

  /// When the source app posted it.
  final DateTime postedAt;
  final DateTime capturedAt;

  /// Checked against the parsing rules already (matched or not).
  final bool processed;

  /// The rule that matched, if any.
  final String? ruleId;

  /// The transaction created from it (the reference back to the source
  /// notification lives here, the transaction itself is a normal one).
  final String? transactionId;
  final TxType? txType;
  final double? amount;

  /// Why a matching rule couldn't create a transaction (Indonesian).
  final String? parseError;

  String get displayAppName =>
      (appName?.trim().isNotEmpty ?? false) ? appName!.trim() : packageName;

  bool get hasTransaction => transactionId != null;
}

/// Which part of the notification a rule's pattern is matched against.
enum RuleMatchField {
  any('any', 'Judul atau isi'),
  title('title', 'Judul'),
  body('body', 'Isi');

  const RuleMatchField(this.wire, this.label);
  final String wire;
  final String label;

  static RuleMatchField fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? any;
}

/// Turns matching notifications of some apps into income/expense transactions.
/// Device-only (not synced).
final class NotificationRule {
  const NotificationRule({
    required this.id,
    required this.name,
    required this.packages,
    this.matchField = RuleMatchField.any,
    required this.pattern,
    this.isRegex = false,
    required this.type,
    this.amountPattern,
    this.walletId,
    this.categoryId,
    this.enabled = false,
    this.presetKey,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Source apps (package names, e.g. `com.bca.mybca.omni.android`).
  final List<String> packages;
  final RuleMatchField matchField;

  /// Keywords separated by `|` (any of them, case-insensitive) or, with
  /// [isRegex], a regular expression (case-insensitive).
  final String pattern;
  final bool isRegex;

  /// [TxType.income] or [TxType.expense].
  final TxType type;

  /// Optional regex for the amount; its first group (or the whole match) is
  /// parsed as rupiah. Null = the default rupiah detector.
  final String? amountPattern;

  /// Null = the first active wallet.
  final String? walletId;
  final String? categoryId;
  final bool enabled;

  /// Set on rules created from a built-in preset.
  final String? presetKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationRule copyWith({bool? enabled, DateTime? updatedAt}) =>
      NotificationRule(
        id: id,
        name: name,
        packages: packages,
        matchField: matchField,
        pattern: pattern,
        isRegex: isRegex,
        type: type,
        amountPattern: amountPattern,
        walletId: walletId,
        categoryId: categoryId,
        enabled: enabled ?? this.enabled,
        presetKey: presetKey,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// An app that has notifications in the log (for the per-app filter).
final class NotificationSource {
  const NotificationSource({
    required this.packageName,
    this.appName,
    required this.count,
  });
  final String packageName;
  final String? appName;
  final int count;

  String get displayAppName =>
      (appName?.trim().isNotEmpty ?? false) ? appName!.trim() : packageName;
}

/// An app installed on the device (launcher label + package).
final class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});
  final String packageName;
  final String label;
}
