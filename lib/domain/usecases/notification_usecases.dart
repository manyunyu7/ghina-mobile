import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'notification_rules.dart';
import 'transaction_usecases.dart';
import 'validation.dart';

// ---------------------------------------------------------------- log

final class WatchCapturedNotifications {
  const WatchCapturedNotifications(this._repo);
  final CapturedNotificationRepository _repo;

  Stream<List<CapturedNotification>> call({
    String? packageName,
    String? search,
  }) => _repo.watch(packageName: packageName, search: search);
}

final class WatchNotificationSources {
  const WatchNotificationSources(this._repo);
  final CapturedNotificationRepository _repo;

  Stream<List<NotificationSource>> call() => _repo.watchSources();
}

/// Deletes the log (or one app's part). → number of rows deleted.
final class ClearCapturedNotifications {
  const ClearCapturedNotifications(this._repo);
  final CapturedNotificationRepository _repo;

  Future<Result<int>> call({String? packageName}) =>
      guard(() => _repo.clear(packageName: packageName));
}

// ---------------------------------------------------------------- rules

/// Form data of a parsing rule.
final class NotificationRuleInput {
  const NotificationRuleInput({
    required this.name,
    required this.packages,
    this.matchField = RuleMatchField.any,
    required this.pattern,
    this.isRegex = false,
    required this.type,
    this.amountPattern,
    this.walletId,
    this.categoryId,
    this.enabled = true,
    this.presetKey,
  });

  final String name;
  final List<String> packages;
  final RuleMatchField matchField;
  final String pattern;
  final bool isRegex;
  final TxType type;
  final String? amountPattern;
  final String? walletId;
  final String? categoryId;
  final bool enabled;
  final String? presetKey;

  factory NotificationRuleInput.fromPreset(
    NotificationRulePreset p, {
    bool enabled = true,
  }) => NotificationRuleInput(
    name: p.name,
    packages: p.packages,
    matchField: p.matchField,
    pattern: p.pattern,
    isRegex: p.isRegex,
    type: p.type,
    enabled: enabled,
    presetKey: p.key,
  );
}

/// Parses a package list typed by the user (comma/space/newline separated).
List<String> parsePackageList(String raw) {
  final out = <String>[];
  for (final p in raw.split(RegExp(r'[\s,;]+'))) {
    final s = p.trim();
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

final _packageRe = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$');

NotificationRule _buildRule(
  String id,
  NotificationRuleInput input,
  DateTime createdAt,
  DateTime now,
) {
  final packages = [
    for (final p in input.packages)
      if (p.trim().isNotEmpty) p.trim(),
  ];
  if (packages.isEmpty) {
    throw const ValidationFailure(
      'Pilih aplikasi sumbernya',
      field: 'packages',
    );
  }
  final bad = packages.where((p) => !_packageRe.hasMatch(p)).firstOrNull;
  if (bad != null) {
    throw ValidationFailure(
      'Nama paket "$bad" nggak valid (contoh: com.bca.mybca.omni.android)',
      field: 'packages',
    );
  }
  final pattern = input.pattern.trim();
  if (pattern.isEmpty) {
    throw const ValidationFailure('Isi kata kunci dulu', field: 'pattern');
  }
  if (input.isRegex && tryRuleRegex(pattern) == null) {
    throw const ValidationFailure('Regex pola nggak valid', field: 'pattern');
  }
  if (!input.isRegex && ruleKeywords(pattern).isEmpty) {
    throw const ValidationFailure('Isi kata kunci dulu', field: 'pattern');
  }
  final amountPattern = optionalText(
    input.amountPattern,
    max: 300,
    field: 'amountPattern',
  );
  if (amountPattern != null && tryRuleRegex(amountPattern) == null) {
    throw const ValidationFailure(
      'Regex nominal nggak valid',
      field: 'amountPattern',
    );
  }
  if (input.type != TxType.income && input.type != TxType.expense) {
    throw const ValidationFailure(
      'Pilih pemasukan atau pengeluaran',
      field: 'type',
    );
  }
  return NotificationRule(
    id: id,
    name: requireName(input.name, max: 80),
    packages: List.unmodifiable(packages),
    matchField: input.matchField,
    pattern: pattern,
    isRegex: input.isRegex,
    type: input.type,
    amountPattern: amountPattern,
    walletId: optionalId(input.walletId),
    categoryId: optionalId(input.categoryId),
    enabled: input.enabled,
    presetKey: optionalId(input.presetKey),
    createdAt: createdAt,
    updatedAt: now,
  );
}

final class WatchNotificationRules {
  const WatchNotificationRules(this._repo);
  final NotificationRuleRepository _repo;

  Stream<List<NotificationRule>> call() => _repo.watchAll();
}

final class WatchNotificationRule {
  const WatchNotificationRule(this._repo);
  final NotificationRuleRepository _repo;

  Stream<NotificationRule?> call(String id) => _repo.watchById(id);
}

/// Creates (null [id]) or updates a rule.
final class SaveNotificationRule {
  const SaveNotificationRule(this._repo, this._clock);
  final NotificationRuleRepository _repo;
  final Clock _clock;

  Future<Result<NotificationRule>> call(
    String? id,
    NotificationRuleInput input,
  ) => guard(() async {
    final now = _clock.now();
    NotificationRule? existing;
    if (id != null) {
      existing = await _repo.getById(id);
      if (existing == null) throw const NotFoundFailure('Rule tidak ditemukan');
    }
    final rule = _buildRule(
      existing?.id ?? newId(),
      NotificationRuleInput(
        name: input.name,
        packages: input.packages,
        matchField: input.matchField,
        pattern: input.pattern,
        isRegex: input.isRegex,
        type: input.type,
        amountPattern: input.amountPattern,
        walletId: input.walletId,
        categoryId: input.categoryId,
        enabled: input.enabled,
        presetKey: input.presetKey ?? existing?.presetKey,
      ),
      existing?.createdAt ?? now,
      now,
    );
    await _repo.save(rule);
    return rule;
  });
}

final class DeleteNotificationRule {
  const DeleteNotificationRule(this._repo);
  final NotificationRuleRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

final class SetNotificationRuleEnabled {
  const SetNotificationRuleEnabled(this._repo, this._clock);
  final NotificationRuleRepository _repo;
  final Clock _clock;

  Future<Result<void>> call(String id, bool enabled) => guard(() async {
    final r = await _repo.getById(id);
    if (r == null) throw const NotFoundFailure('Rule tidak ditemukan');
    await _repo.save(r.copyWith(enabled: enabled, updatedAt: _clock.now()));
  });
}

/// Turns a preset on: enables its rule, creating it from the preset first
/// when it doesn't exist yet (wallet: the first active one, no category).
final class EnableNotificationRulePreset {
  const EnableNotificationRulePreset(this._repo, this._save, this._setEnabled);
  final NotificationRuleRepository _repo;
  final SaveNotificationRule _save;
  final SetNotificationRuleEnabled _setEnabled;

  Future<Result<void>> call(String presetKey) async {
    final preset = notificationRulePreset(presetKey);
    if (preset == null) {
      return const Err(NotFoundFailure('Preset tidak ditemukan'));
    }
    final existing = (await _repo.getAll())
        .where((r) => r.presetKey == presetKey)
        .firstOrNull;
    if (existing != null) return _setEnabled(existing.id, true);
    final r = await _save(null, NotificationRuleInput.fromPreset(preset));
    return switch (r) {
      Ok() => const Ok(null),
      Err(:final failure) => Err(failure),
    };
  }
}

// ---------------------------------------------------------------- processing

/// Summary of one [ProcessCapturedNotifications] run.
final class NotificationProcessResult {
  const NotificationProcessResult({this.checked = 0, this.created = const []});
  final int checked;
  final List<Transaction> created;
}

/// Checks captured notifications against the enabled rules and records a
/// matching one as an income/expense transaction through [CreateTransaction]
/// (the regular path: outbox, sync, balances, XP). The transaction's date is
/// when the notification was posted and its note is the notification text; the
/// log row keeps the transaction id (the reference to the source).
///
/// Runs in the UI isolate while signed in (the background listener only
/// stores rows), so notifications captured while the app was closed are
/// recorded on the next start. Runs are serialized.
final class ProcessCapturedNotifications {
  const ProcessCapturedNotifications(
    this._log,
    this._rules,
    this._wallets,
    this._createTransaction,
    this._appLabel,
  );
  final CapturedNotificationRepository _log;
  final NotificationRuleRepository _rules;
  final WalletRepository _wallets;
  final CreateTransaction _createTransaction;

  /// Resolves app labels the background isolate couldn't (null = unknown).
  final Future<String?> Function(String packageName) _appLabel;

  static Future<void> _queue = Future.value();

  Future<NotificationProcessResult> call() {
    final run = _queue.then((_) => _run());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<NotificationProcessResult> _run() async {
    var checked = 0;
    final created = <Transaction>[];
    final labels = <String, String?>{};
    for (var round = 0; round < 20; round++) {
      final batch = await _log.unprocessed();
      if (batch.isEmpty) break;
      final rules = await _rules.getAll();
      for (final n in batch) {
        checked++;
        final appName =
            n.appName ??
            (labels.containsKey(n.packageName)
                ? labels[n.packageName]
                : labels[n.packageName] = await _safeLabel(n.packageName));
        final rule = findMatchingRule(
          rules,
          packageName: n.packageName,
          title: n.title,
          body: n.body,
        );
        if (rule == null) {
          await _log.markProcessed(n.id, appName: appName);
          continue;
        }
        final amount = detectRupiahAmount(
          '${n.title}\n${n.body}',
          customPattern: rule.amountPattern,
        );
        if (amount == null) {
          await _log.markProcessed(
            n.id,
            appName: appName,
            ruleId: rule.id,
            txType: rule.type,
            parseError: 'Nominal rupiah nggak ketemu',
          );
          continue;
        }
        final walletId = await _walletFor(rule);
        if (walletId == null) {
          await _log.markProcessed(
            n.id,
            appName: appName,
            ruleId: rule.id,
            txType: rule.type,
            amount: amount.value,
            parseError: 'Belum ada dompet',
          );
          continue;
        }
        final r = await _createTransaction(
          TransactionInput(
            type: rule.type,
            amount: amount.value,
            walletId: walletId,
            categoryId: rule.categoryId,
            note: notificationTransactionNote(n.title, n.body),
            date: n.postedAt,
          ),
        );
        switch (r) {
          case Ok(:final value):
            created.add(value);
            await _log.markProcessed(
              n.id,
              appName: appName,
              ruleId: rule.id,
              transactionId: value.id,
              txType: rule.type,
              amount: amount.value,
            );
          case Err(:final failure):
            await _log.markProcessed(
              n.id,
              appName: appName,
              ruleId: rule.id,
              txType: rule.type,
              amount: amount.value,
              parseError: failure.message,
            );
        }
      }
    }
    return NotificationProcessResult(checked: checked, created: created);
  }

  Future<String?> _safeLabel(String pkg) async {
    try {
      return await _appLabel(pkg);
    } catch (_) {
      return null;
    }
  }

  /// The rule's wallet when it still exists (not archived), else the first
  /// active wallet.
  Future<String?> _walletFor(NotificationRule rule) async {
    final wallets = await _wallets.getAll(includeArchived: false);
    final own = wallets.where((w) => w.id == rule.walletId).firstOrNull;
    return (own ?? wallets.firstOrNull)?.id;
  }
}
