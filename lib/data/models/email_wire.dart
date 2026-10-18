/// Parsers of the `/api/mobile/email` responses (accounts, sync results,
/// suggestions, the triaged inbox and its rules). Defensive like the other online parsers: unknown keys are
/// ignored, missing optional values become null / zero, and a row without its
/// id is dropped.
library;

import '../../domain/entities/email.dart';

String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
double? _d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int _i(Object? v) => v is num && v.isFinite ? v.round() : 0;
DateTime? _t(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

/// `"2026-10-01"` → that local calendar day.
DateTime? _day(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

Iterable<Map<dynamic, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map<dynamic, dynamic>>() : const [];

EmailAccount? emailAccountFromWire(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  if (id == null) return null;
  final counts = raw['counts'];
  return EmailAccount(
    id: id,
    email: _s(raw['email']) ?? '',
    status: EmailAccountStatus.fromWire(_s(raw['status'])),
    lastSyncAt: _t(raw['lastSyncAt']),
    lastError: _s(raw['lastError']),
    messageCount: counts is Map ? _i(counts['messages']) : 0,
    pendingCount: counts is Map ? _i(counts['pending']) : 0,
    syncing: raw['syncing'] == true,
    triage: raw['triage'] == true,
    inboxUnread: counts is Map ? _i(counts['inboxUnread']) : 0,
  );
}

EmailOverview emailOverviewFromWire(Object? raw) {
  if (raw is! Map) return const EmailOverview(enabled: false);
  return EmailOverview(
    enabled: raw['enabled'] == true,
    since: _day(raw['since']),
    accounts: [
      for (final a in _maps(raw['accounts'])) ?emailAccountFromWire(a),
    ],
  );
}

List<EmailSyncResult> emailSyncResultsFromWire(Object? raw) => [
  if (raw is Map)
    for (final r in _maps(raw['accounts']))
      if (_s(r['id']) case final id?)
        EmailSyncResult(
          accountId: id,
          fetched: _i(r['fetched']),
          newMessages: _i(r['newMessages']),
          suggested: _i(r['suggested']),
          error: _s(r['error']),
        ),
];

EmailDuplicate? _duplicate(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['transactionId']);
  if (id == null) return null;
  return EmailDuplicate(
    transactionId: id,
    amount: _d(raw['amount']) ?? 0,
    date: _t(raw['date']),
    note: _s(raw['note']),
  );
}

EmailSuggestion? emailSuggestionFromWire(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  if (id == null) return null;
  final occurredAt = _t(raw['occurredAt']) ?? _t(raw['receivedAt']);
  if (occurredAt == null) return null;
  return EmailSuggestion(
    id: id,
    accountEmail: _s(raw['accountEmail']) ?? '',
    messageId: _s(raw['messageId']),
    gmailUrl: _s(raw['gmailUrl']),
    from: _s(raw['from']) ?? '',
    subject: _s(raw['subject']) ?? '',
    receivedAt: _t(raw['receivedAt']),
    kind: EmailSuggestionKind.fromWire(_s(raw['kind'])),
    amount: _d(raw['amount']) ?? 0,
    originalAmount: _d(raw['originalAmount']),
    originalCurrency: _s(raw['originalCurrency']),
    merchant: _s(raw['merchant']) ?? '',
    note: _s(raw['note']) ?? '',
    occurredAt: occurredAt,
    method: _s(raw['method']),
    walletId: _s(raw['walletId']),
    categoryId: _s(raw['categoryId']),
    source: EmailSuggestionSource.fromWire(_s(raw['source'])),
    parser: _s(raw['parser']),
    duplicateOf: _duplicate(raw['duplicateOf']),
    status: EmailSuggestionStatus.fromWire(_s(raw['status'])),
    transactionId: _s(raw['transactionId']),
  );
}

EmailSuggestionPage emailSuggestionPageFromWire(Object? raw) {
  if (raw is! Map) return const EmailSuggestionPage();
  final items = [
    for (final s in _maps(raw['items'])) ?emailSuggestionFromWire(s),
  ];
  return EmailSuggestionPage(
    items: items,
    total: raw['total'] is num ? _i(raw['total']) : items.length,
  );
}

/// The approve body: only what's set.
Map<String, Object?> emailApprovalToWire(EmailApproval a) => {
  'kind': ?a.kind?.wire,
  'amount': ?a.amount,
  'walletId': ?a.walletId,
  'toWalletId': ?a.toWalletId,
  'categoryId': ?a.categoryId,
  'note': ?a.note,
  'occurredAt': ?a.occurredAt?.toUtc().toIso8601String(),
};

EmailInboxItem? emailInboxItemFromWire(Object? raw) {
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  if (id == null) return null;
  return EmailInboxItem(
    id: id,
    accountEmail: _s(raw['accountEmail']) ?? '',
    from: _s(raw['from']) ?? '',
    subject: _s(raw['subject']) ?? '',
    receivedAt: _t(raw['receivedAt']),
    importance: EmailImportance.fromWire(_s(raw['importance'])),
    summary: _s(raw['summary']) ?? '',
    action: _s(raw['action']),
    replyDraft: _s(raw['replyDraft']),
    gmailUrl: _s(raw['gmailUrl']),
    notifiedAt: _t(raw['notifiedAt']),
    read: raw['read'] == true,
  );
}

EmailInboxPage emailInboxPageFromWire(Object? raw) {
  if (raw is! Map) return const EmailInboxPage();
  final items = [
    for (final m in _maps(raw['items'])) ?emailInboxItemFromWire(m),
  ];
  return EmailInboxPage(
    items: items,
    total: raw['total'] is num ? _i(raw['total']) : items.length,
    unread: raw['unread'] is num
        ? _i(raw['unread'])
        : items.where((i) => !i.read).length,
  );
}

/// A rule, or `{rule: …}`. Null without an id, a known kind / match or a
/// pattern.
EmailTriageRule? emailTriageRuleFromWire(Object? raw) {
  if (raw is Map && raw['rule'] is Map) raw = raw['rule'];
  if (raw is! Map) return null;
  final id = _s(raw['id']);
  final kind = EmailRuleKind.fromWire(_s(raw['kind']));
  final match = EmailRuleMatch.fromWire(_s(raw['match']));
  final pattern = _s(raw['pattern'])?.trim();
  if (id == null || kind == null || match == null || pattern == null) {
    return null;
  }
  if (pattern.isEmpty) return null;
  return EmailTriageRule(
    id: id,
    kind: kind,
    match: match,
    pattern: pattern,
    note: _s(raw['note']),
    createdAt: _t(raw['createdAt']),
  );
}

/// `{items: […]}`, `{rules: […]}` or a bare list.
List<EmailTriageRule> emailTriageRulesFromWire(Object? raw) {
  final list = raw is Map ? (raw['items'] ?? raw['rules']) : raw;
  return [for (final r in _maps(list)) ?emailTriageRuleFromWire(r)];
}

Map<String, Object?> emailRuleInputToWire(EmailRuleInput r) {
  final note = r.note?.trim();
  return {
    'kind': r.kind.wire,
    'match': r.match.wire,
    'pattern': r.pattern.trim(),
    if (note != null && note.isNotEmpty) 'note': note,
  };
}
