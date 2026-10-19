/// Parsers of the `/api/mobile/statements` responses and the request bodies.
/// Defensive like the other online parsers: unknown keys are ignored, missing
/// optional values become null / zero, and a row without its id is dropped.
library;

import 'dart:convert';

import '../../domain/entities/enums.dart';
import '../../domain/entities/statement_import.dart';

String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
double? _d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int _i(Object? v) => v is num && v.isFinite ? v.round() : 0;
DateTime? _t(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

Iterable<Map<dynamic, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map<dynamic, dynamic>>() : const [];

StatementCounts statementCountsFromWire(Object? raw) {
  if (raw is! Map) return const StatementCounts();
  return StatementCounts(
    total: _i(raw['total']),
    newRows: _i(raw['new']),
    duplicate: _i(raw['duplicate']),
    uncertain: _i(raw['uncertain']),
    pending: _i(raw['pending']),
    approved: _i(raw['approved']),
    ignored: _i(raw['ignored']),
  );
}

StatementImport? statementImportFromWire(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  if (id == null) return null;
  return StatementImport(
    id: id,
    fileName: _s(raw['fileName']) ?? 'mutasi.pdf',
    status: StatementStatus.fromWire(_s(raw['status'])),
    error: _s(raw['error']),
    walletId: _s(raw['walletId']),
    wallet: _s(raw['wallet']),
    bank: _s(raw['bank']),
    accountLast4: _s(raw['accountLast4']),
    periodFrom: _t(raw['periodFrom']),
    periodTo: _t(raw['periodTo']),
    summary: _s(raw['summary']),
    createdAt: _t(raw['createdAt']),
    updatedAt: _t(raw['updatedAt']),
    counts: statementCountsFromWire(raw['counts']),
  );
}

List<StatementImport> statementImportsFromWire(Object? raw) => [
  if (raw is Map)
    for (final m in _maps(raw['imports'])) ?statementImportFromWire(m),
];

StatementMatch? _match(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  if (id == null) return null;
  return StatementMatch(
    id: id,
    date: _t(raw['date']),
    type: TxType.fromWire(_s(raw['type'])),
    amount: _d(raw['amount']) ?? 0,
    note: _s(raw['note']),
    wallet: _s(raw['wallet']),
  );
}

StatementRow? statementRowFromWire(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  final date = _t(raw['date']);
  if (id == null || date == null) return null;
  return StatementRow(
    id: id,
    idx: _i(raw['idx']),
    date: date,
    type: TxType.fromWire(_s(raw['type'])),
    amount: _d(raw['amount']) ?? 0,
    description: _s(raw['description']) ?? '',
    note: _s(raw['note']),
    walletId: _s(raw['walletId']) ?? '',
    toWalletId: _s(raw['toWalletId']),
    categoryId: _s(raw['categoryId']),
    wallet: _s(raw['wallet']),
    toWallet: _s(raw['toWallet']),
    category: _s(raw['category']),
    verdict: StatementVerdict.fromWire(_s(raw['verdict'])),
    status: StatementRowStatus.fromWire(_s(raw['status'])),
    reason: _s(raw['reason']),
    duplicateOf: _match(raw['duplicateOf']),
    transactionId: _s(raw['transactionId']),
  );
}

StatementDetail? statementDetailFromWire(Object? raw) {
  if (raw is! Map) return null;
  final imp = statementImportFromWire(raw['import']);
  if (imp == null) return null;
  return StatementDetail(
    import: imp,
    rows: [for (final m in _maps(raw['rows'])) ?statementRowFromWire(m)],
  );
}

/// `POST /statements` body. The password is only included when given.
Map<String, Object?> statementUploadToWire(StatementUpload u) => {
  'name': u.name,
  'dataBase64': base64Encode(u.bytes),
  if (u.walletId != null && u.walletId!.isNotEmpty) 'walletId': u.walletId,
  if (u.password != null && u.password!.isNotEmpty) 'password': u.password,
};

/// `PATCH /statements/rows/:rowId` body: only the fields that changed.
Map<String, Object?> statementRowPatchToWire(StatementRowPatch p) => {
  if (p.date != null) 'date': p.date!.toUtc().toIso8601String(),
  if (p.type != null) 'type': p.type!.wire,
  'amount': ?p.amount,
  'note': ?p.note,
  'walletId': ?p.walletId,
  'toWalletId': ?p.toWalletId,
  'categoryId': ?p.categoryId,
  if (p.clearCategory) 'categoryId': null,
};
