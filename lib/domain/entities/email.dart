/// Email ("Gmail read-only", `/api/mobile/email`): connected Gmail accounts
/// and the transactions the server suggests from finance emails. Online-only:
/// nothing here is stored or synced locally; an approved suggestion becomes a
/// normal transaction that arrives through sync.
library;

enum EmailAccountStatus {
  active('active'),
  error('error'),
  revoked('revoked');

  const EmailAccountStatus(this.wire);
  final String wire;

  static EmailAccountStatus fromWire(String? s) => values.firstWhere(
    (v) => v.wire == s,
    orElse: () => EmailAccountStatus.error,
  );
}

/// One connected Gmail address.
final class EmailAccount {
  const EmailAccount({
    required this.id,
    required this.email,
    required this.status,
    this.lastSyncAt,
    this.lastError,
    this.messageCount = 0,
    this.pendingCount = 0,
    this.syncing = false,
    this.triage = false,
    this.inboxUnread = 0,
  });

  final String id;
  final String email;
  final EmailAccountStatus status;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int messageCount;
  final int pendingCount;

  /// A sync is running on the server right now (background sync).
  final bool syncing;

  /// "Killa baca semua email": Killa triages the whole inbox of this
  /// address, not only finance mail.
  final bool triage;

  /// Unread triaged mail ("Email penting") of this address.
  final int inboxUnread;

  EmailAccount copyWith({bool? triage}) => EmailAccount(
    id: id,
    email: email,
    status: status,
    lastSyncAt: lastSyncAt,
    lastError: lastError,
    messageCount: messageCount,
    pendingCount: pendingCount,
    syncing: syncing,
    triage: triage ?? this.triage,
    inboxUnread: inboxUnread,
  );
}

/// `GET accounts`: whether the feature is on for this user, the backfill
/// start date and the connected accounts.
final class EmailOverview {
  const EmailOverview({
    required this.enabled,
    this.since,
    this.accounts = const [],
  });

  final bool enabled;

  /// Messages received on/after this day (Asia/Jakarta) are read.
  final DateTime? since;
  final List<EmailAccount> accounts;

  int get pendingCount => accounts.fold(0, (s, a) => s + a.pendingCount);

  int get inboxUnread => accounts.fold(0, (s, a) => s + a.inboxUnread);

  /// Any account has "Killa baca semua email" on.
  bool get triageOn => accounts.any((a) => a.triage);
}

/// One account's result of `POST sync`.
final class EmailSyncResult {
  const EmailSyncResult({
    required this.accountId,
    this.fetched = 0,
    this.newMessages = 0,
    this.suggested = 0,
    this.error,
  });

  final String accountId;
  final int fetched;
  final int newMessages;
  final int suggested;
  final String? error;
}

enum EmailSuggestionStatus {
  pending('pending', 'Perlu dicek'),
  approved('approved', 'Disetujui'),
  ignored('ignored', 'Diabaikan');

  const EmailSuggestionStatus(this.wire, this.label);
  final String wire;
  final String label;

  static EmailSuggestionStatus fromWire(String? s) => values.firstWhere(
    (v) => v.wire == s,
    orElse: () => EmailSuggestionStatus.pending,
  );
}

enum EmailSuggestionKind {
  expense('expense', 'Pengeluaran'),
  income('income', 'Pemasukan'),
  transfer('transfer', 'Transfer');

  const EmailSuggestionKind(this.wire, this.label);
  final String wire;
  final String label;

  static EmailSuggestionKind fromWire(String? s) => values.firstWhere(
    (v) => v.wire == s,
    orElse: () => EmailSuggestionKind.expense,
  );
}

/// How the suggestion was made: a sender rule ("Otomatis") or the AI.
enum EmailSuggestionSource {
  rule('rule'),
  ai('ai');

  const EmailSuggestionSource(this.wire);
  final String wire;

  static EmailSuggestionSource fromWire(String? s) =>
      s == 'ai' ? EmailSuggestionSource.ai : EmailSuggestionSource.rule;
}

/// An existing transaction that looks like the same payment.
final class EmailDuplicate {
  const EmailDuplicate({
    required this.transactionId,
    required this.amount,
    this.date,
    this.note,
  });

  final String transactionId;
  final double amount;
  final DateTime? date;
  final String? note;
}

/// A transaction suggested from one email. Nothing is recorded until the user
/// approves it.
final class EmailSuggestion {
  const EmailSuggestion({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    required this.status,
    this.accountEmail = '',
    this.messageId,
    this.gmailUrl,
    this.from = '',
    this.subject = '',
    this.receivedAt,
    this.originalAmount,
    this.originalCurrency,
    this.merchant = '',
    this.note = '',
    this.method,
    this.walletId,
    this.categoryId,
    this.source = EmailSuggestionSource.rule,
    this.parser,
    this.duplicateOf,
    this.transactionId,
  });

  final String id;
  final String accountEmail;
  final String? messageId;
  final String? gmailUrl;
  final String from;
  final String subject;
  final DateTime? receivedAt;
  final EmailSuggestionKind kind;

  /// In IDR.
  final double amount;
  final double? originalAmount;
  final String? originalCurrency;
  final String merchant;
  final String note;
  final DateTime occurredAt;

  /// e.g. "Kartu Kredit BCA •5736".
  final String? method;

  /// The server's best wallet guess (by method / name).
  final String? walletId;
  final String? categoryId;
  final EmailSuggestionSource source;

  /// e.g. `bca_cc`, `gopay_bill`, `ai`.
  final String? parser;
  final EmailDuplicate? duplicateOf;
  final EmailSuggestionStatus status;

  /// The created transaction once approved.
  final String? transactionId;

  /// Merchant, else the subject, else the sender.
  String get title => merchant.isNotEmpty
      ? merchant
      : subject.isNotEmpty
      ? subject
      : from;
}

final class EmailSuggestionPage {
  const EmailSuggestionPage({this.items = const [], this.total = 0});

  final List<EmailSuggestion> items;
  final int total;
}

/// What the user confirms (or changes) when approving. Null = keep the
/// suggestion's value.
final class EmailApproval {
  const EmailApproval({
    this.kind,
    this.amount,
    this.walletId,
    this.toWalletId,
    this.categoryId,
    this.note,
    this.occurredAt,
  });

  final EmailSuggestionKind? kind;
  final double? amount;
  final String? walletId;
  final String? toWalletId;
  final String? categoryId;
  final String? note;
  final DateTime? occurredAt;
}

/// How much an email matters, as judged by Killa.
enum EmailImportance {
  urgent('urgent', 'Mendesak', '🔴'),
  important('important', 'Penting', '🟠'),
  info('info', 'Info', '🔵'),
  ignore('ignore', 'Diabaikan', '⚪');

  const EmailImportance(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  /// Unknown or missing → [info] (shown, never alarming).
  static EmailImportance fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => EmailImportance.info);

  /// What "Email penting" lists: everything Killa didn't ignore.
  static const shown = [urgent, important, info];
}

/// One mail Killa triaged (`GET inbox`): no body, only Killa's reading.
final class EmailInboxItem {
  const EmailInboxItem({
    required this.id,
    required this.importance,
    this.accountEmail = '',
    this.from = '',
    this.subject = '',
    this.receivedAt,
    this.summary = '',
    this.action,
    this.replyDraft,
    this.gmailUrl,
    this.notifiedAt,
    this.read = false,
  });

  final String id;
  final String accountEmail;
  final String from;
  final String subject;
  final DateTime? receivedAt;
  final EmailImportance importance;

  /// 1–2 sentences, Indonesian.
  final String summary;

  /// "Perlu dilakukan", when there is something to do.
  final String? action;

  /// A reply Killa suggests (Killa never sends email).
  final String? replyDraft;
  final String? gmailUrl;

  /// When it went out on WhatsApp (urgent at once, important in a digest).
  final DateTime? notifiedAt;
  final bool read;

  /// The display name of [from] (`"BCA <bca@bca.co.id>"` → `BCA`).
  String get sender {
    final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<[^>]+>\s*$').firstMatch(from);
    final name = m?.group(1)?.trim();
    return name != null && name.isNotEmpty ? name : from;
  }

  EmailInboxItem copyWith({bool? read}) => EmailInboxItem(
    id: id,
    importance: importance,
    accountEmail: accountEmail,
    from: from,
    subject: subject,
    receivedAt: receivedAt,
    summary: summary,
    action: action,
    replyDraft: replyDraft,
    gmailUrl: gmailUrl,
    notifiedAt: notifiedAt,
    read: read ?? this.read,
  );
}

final class EmailInboxPage {
  const EmailInboxPage({
    this.items = const [],
    this.total = 0,
    this.unread = 0,
  });

  final List<EmailInboxItem> items;

  /// Rows matching the filter (for "Muat lagi").
  final int total;
  final int unread;
}

/// `always` = at least important; `never` = skipped without AI.
enum EmailRuleKind {
  always('always', 'Selalu penting'),
  never('never', 'Abaikan');

  const EmailRuleKind(this.wire, this.label);
  final String wire;
  final String label;

  static EmailRuleKind? fromWire(String? s) =>
      values.where((v) => v.wire == s).firstOrNull;
}

/// What a rule's pattern is matched against.
enum EmailRuleMatch {
  /// The address or the domain (case-insensitive).
  sender('sender', 'Pengirim'),

  /// The subject.
  keyword('keyword', 'Kata kunci');

  const EmailRuleMatch(this.wire, this.label);
  final String wire;
  final String label;

  static EmailRuleMatch? fromWire(String? s) =>
      values.where((v) => v.wire == s).firstOrNull;
}

/// A user rule for Killa's triage ("Aturan Killa").
final class EmailTriageRule {
  const EmailTriageRule({
    required this.id,
    required this.kind,
    required this.match,
    required this.pattern,
    this.note,
    this.createdAt,
  });

  final String id;
  final EmailRuleKind kind;
  final EmailRuleMatch match;

  /// ≤ 200 chars.
  final String pattern;
  final String? note;
  final DateTime? createdAt;
}

/// A new rule (`POST inbox/rules`).
final class EmailRuleInput {
  const EmailRuleInput({
    required this.kind,
    required this.match,
    required this.pattern,
    this.note,
  });

  final EmailRuleKind kind;
  final EmailRuleMatch match;
  final String pattern;
  final String? note;
}

enum EmailErrorKind {
  /// 403 `email_not_enabled`: the feature is off for this account.
  notEnabled,

  /// 401.
  unauthorized,

  /// 400 / 422.
  invalid,

  /// 404.
  notFound,

  /// 409: the suggestion was already approved / ignored.
  conflict,

  /// 502: Google refused or is unreachable.
  google,

  /// The Google sign-in on the phone failed (not a cancel).
  signIn,

  /// No connection.
  network,
  unknown,
}

/// What every email call throws. [message] is friendly Indonesian copy.
final class EmailException implements Exception {
  const EmailException(this.kind, this.message, {this.status});

  final EmailErrorKind kind;
  final String message;
  final int? status;

  @override
  String toString() => 'EmailException($kind, $status): $message';
}
