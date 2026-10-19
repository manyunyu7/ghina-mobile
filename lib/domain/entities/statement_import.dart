/// Statement import ("Impor mutasi", `docs/statement-import.md`): a bank
/// statement PDF the server hands to Killa, who turns it into rows to review.
/// Online-only: nothing here is stored or synced locally; an approved row
/// becomes a normal transaction that arrives through sync.
library;

import 'enums.dart';

enum StatementStatus {
  parsing('parsing', 'Membaca…'),
  ready('ready', 'Siap direview'),
  failed('failed', 'Gagal'),
  done('done', 'Selesai');

  const StatementStatus(this.wire, this.label);
  final String wire;
  final String label;

  /// Unknown values (newer server) → [failed], the one state with a way out.
  static StatementStatus fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return failed;
  }
}

/// Killa's call on a row: not in Ghina yet, already there, or unsure.
enum StatementVerdict {
  isNew('new'),
  duplicate('duplicate'),
  uncertain('uncertain');

  const StatementVerdict(this.wire);
  final String wire;

  static StatementVerdict fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return uncertain;
  }
}

enum StatementRowStatus {
  pending('pending'),
  approved('approved'),
  ignored('ignored');

  const StatementRowStatus(this.wire);
  final String wire;

  static StatementRowStatus fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return pending;
  }
}

final class StatementCounts {
  const StatementCounts({
    this.total = 0,
    this.newRows = 0,
    this.duplicate = 0,
    this.uncertain = 0,
    this.pending = 0,
    this.approved = 0,
    this.ignored = 0,
  });

  final int total;
  final int newRows;
  final int duplicate;
  final int uncertain;
  final int pending;
  final int approved;
  final int ignored;
}

/// `ImportSummary`.
final class StatementImport {
  const StatementImport({
    required this.id,
    required this.fileName,
    required this.status,
    this.error,
    this.walletId,
    this.wallet,
    this.bank,
    this.accountLast4,
    this.periodFrom,
    this.periodTo,
    this.summary,
    this.createdAt,
    this.updatedAt,
    this.counts = const StatementCounts(),
  });

  final String id;
  final String fileName;
  final StatementStatus status;

  /// `failed`: short Indonesian reason from the server.
  final String? error;
  final String? walletId;

  /// The statement's own account (name).
  final String? wallet;
  final String? bank;
  final String? accountLast4;
  final DateTime? periodFrom;
  final DateTime? periodTo;

  /// Killa's one-liner.
  final String? summary;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final StatementCounts counts;
}

/// The existing transaction a duplicate / uncertain row points at.
final class StatementMatch {
  const StatementMatch({
    required this.id,
    this.date,
    this.type = TxType.expense,
    this.amount = 0,
    this.note,
    this.wallet,
  });

  final String id;
  final DateTime? date;
  final TxType type;
  final double amount;
  final String? note;
  final String? wallet;
}

final class StatementRow {
  const StatementRow({
    required this.id,
    required this.idx,
    required this.date,
    required this.type,
    required this.amount,
    required this.description,
    required this.walletId,
    required this.verdict,
    required this.status,
    this.note,
    this.toWalletId,
    this.categoryId,
    this.wallet,
    this.toWallet,
    this.category,
    this.reason,
    this.duplicateOf,
    this.transactionId,
  });

  final String id;
  final int idx;
  final DateTime date;

  /// expense | income | transfer.
  final TxType type;

  /// Positive.
  final double amount;

  /// The statement line.
  final String description;

  /// Proposed transaction note.
  final String? note;
  final String walletId;
  final String? toWalletId;
  final String? categoryId;
  final String? wallet;
  final String? toWallet;
  final String? category;
  final StatementVerdict verdict;
  final StatementRowStatus status;

  /// Why it is a duplicate / uncertain (Indonesian).
  final String? reason;

  /// Null when the matching transaction no longer exists.
  final StatementMatch? duplicateOf;
  final String? transactionId;

  bool get pending => status == StatementRowStatus.pending;

  /// What to show as the row's title.
  String get title {
    final n = note?.trim();
    return n != null && n.isNotEmpty ? n : description;
  }
}

/// `GET /statements/:id`.
final class StatementDetail {
  const StatementDetail({required this.import, this.rows = const []});

  final StatementImport import;
  final List<StatementRow> rows;
}

/// A PDF to upload.
final class StatementUpload {
  const StatementUpload({
    required this.name,
    required this.bytes,
    this.walletId,
    this.password,
  });

  final String name;
  final List<int> bytes;

  /// The statement's account; null = Killa guesses.
  final String? walletId;

  /// Only after `password_required` / `password_wrong`; never stored.
  final String? password;
}

/// Fields of a pending row the user changed (null = untouched).
final class StatementRowPatch {
  const StatementRowPatch({
    this.date,
    this.type,
    this.amount,
    this.note,
    this.walletId,
    this.toWalletId,
    this.categoryId,
    this.clearCategory = false,
  });

  final DateTime? date;
  final TxType? type;
  final double? amount;
  final String? note;
  final String? walletId;
  final String? toWalletId;
  final String? categoryId;

  /// Send `categoryId: null` (e.g. after switching to transfer).
  final bool clearCategory;

  bool get isEmpty =>
      date == null &&
      type == null &&
      amount == null &&
      note == null &&
      walletId == null &&
      toWalletId == null &&
      categoryId == null &&
      !clearCategory;
}

enum StatementErrorKind {
  /// Offline / timeout.
  network,

  /// 401.
  unauthorized,

  /// 403: the account is not on Killa's allowlist.
  forbidden,

  /// 422 `password_required`.
  passwordRequired,

  /// 422 `password_wrong`.
  passwordWrong,

  /// 400 / other 422.
  invalid,

  /// 404.
  notFound,

  /// 409: already decided / a run is in progress.
  conflict,

  /// 413.
  tooLarge,
  unknown,
}

/// What every statement-import call throws. [message] is friendly Indonesian.
final class StatementException implements Exception {
  const StatementException(this.kind, this.message, {this.status});

  final StatementErrorKind kind;
  final String message;
  final int? status;

  @override
  String toString() => 'StatementException($kind, $status): $message';
}
