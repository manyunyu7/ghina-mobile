/// Email use cases (Gmail read-only). Online-only: they throw
/// [EmailException] (the presentation layer shows its friendly message; a
/// `notEnabled` locks the whole feature).
library;

import '../entities/email.dart';
import '../repositories/email_repository.dart';
import '../services/gmail_authorizer.dart';

final class LoadEmailOverview {
  const LoadEmailOverview(this._repo);
  final EmailRepository _repo;

  Future<EmailOverview> call() => _repo.overview();
}

/// Google consent on the phone → server auth code → `accounts/connect`.
/// Returns null when the user cancels the Google sheet.
final class ConnectGmail {
  const ConnectGmail(this._repo, this._authorizer);
  final EmailRepository _repo;
  final GmailAuthorizer _authorizer;

  bool get available => _authorizer.available;

  Future<EmailAccount?> call() async {
    if (!_authorizer.available) {
      throw const EmailException(
        EmailErrorKind.signIn,
        'Login Google belum diaktifkan di versi aplikasi ini.',
      );
    }
    final code = await _authorizer.requestServerAuthCode();
    if (code == null || code.isEmpty) return null;
    return _repo.connect(code);
  }
}

final class DisconnectEmailAccount {
  const DisconnectEmailAccount(this._repo);
  final EmailRepository _repo;

  Future<void> call(String accountId) => _repo.disconnect(accountId);
}

final class SyncEmail {
  const SyncEmail(this._repo);
  final EmailRepository _repo;

  Future<List<EmailSyncResult>> call({
    String? accountId,
    bool background = false,
  }) => _repo.sync(accountId: accountId, background: background);
}

final class LoadEmailSuggestions {
  const LoadEmailSuggestions(this._repo);
  final EmailRepository _repo;

  Future<EmailSuggestionPage> call(
    EmailSuggestionStatus status, {
    int limit = 50,
    int offset = 0,
  }) => _repo.suggestions(status, limit: limit, offset: offset);
}

/// Approves [s] with the user's changes. A wallet is required (the
/// suggestion's guess or [EmailApproval.walletId]); a transfer also needs a
/// different destination wallet.
final class ApproveEmailSuggestion {
  const ApproveEmailSuggestion(this._repo);
  final EmailRepository _repo;

  Future<String> call(
    EmailSuggestion s, [
    EmailApproval a = const EmailApproval(),
  ]) {
    final wallet = a.walletId ?? s.walletId;
    if (wallet == null || wallet.isEmpty) {
      throw const EmailException(
        EmailErrorKind.invalid,
        'Pilih dompetnya dulu, ya.',
      );
    }
    final amount = a.amount ?? s.amount;
    if (!(amount > 0)) {
      throw const EmailException(
        EmailErrorKind.invalid,
        'Nominal harus lebih dari 0.',
      );
    }
    final kind = a.kind ?? s.kind;
    if (kind == EmailSuggestionKind.transfer) {
      final to = a.toWalletId;
      if (to == null || to.isEmpty) {
        throw const EmailException(
          EmailErrorKind.invalid,
          'Pilih dompet tujuan transfernya.',
        );
      }
      if (to == wallet) {
        throw const EmailException(
          EmailErrorKind.invalid,
          'Dompet asal dan tujuan harus beda.',
        );
      }
    }
    return _repo.approve(
      s.id,
      EmailApproval(
        kind: a.kind,
        amount: a.amount,
        walletId: wallet,
        toWalletId: kind == EmailSuggestionKind.transfer ? a.toWalletId : null,
        categoryId: kind == EmailSuggestionKind.transfer ? null : a.categoryId,
        note: a.note,
        occurredAt: a.occurredAt,
      ),
    );
  }
}

final class IgnoreEmailSuggestion {
  const IgnoreEmailSuggestion(this._repo);
  final EmailRepository _repo;

  Future<void> call(String id) => _repo.ignore(id);
}

final class RestoreEmailSuggestion {
  const RestoreEmailSuggestion(this._repo);
  final EmailRepository _repo;

  Future<void> call(String id) => _repo.restore(id);
}

/// "Killa baca semua email" on / off for one account.
final class SetEmailTriage {
  const SetEmailTriage(this._repo);
  final EmailRepository _repo;

  Future<EmailAccount> call(String accountId, bool on) =>
      _repo.setTriage(accountId, on);
}

final class LoadEmailInbox {
  const LoadEmailInbox(this._repo);
  final EmailRepository _repo;

  Future<EmailInboxPage> call({
    Set<EmailImportance> importance = const {},
    int limit = 30,
    int offset = 0,
  }) => _repo.inbox(importance: importance, limit: limit, offset: offset);
}

final class MarkEmailRead {
  const MarkEmailRead(this._repo);
  final EmailRepository _repo;

  Future<void> call(String id) => _repo.markRead(id);
}

final class LoadEmailRules {
  const LoadEmailRules(this._repo);
  final EmailRepository _repo;

  Future<List<EmailTriageRule>> call() => _repo.rules();
}

/// Adds a rule; the pattern is required and ≤ 200 chars.
final class AddEmailRule {
  const AddEmailRule(this._repo);
  final EmailRepository _repo;

  Future<EmailTriageRule> call(EmailRuleInput input) {
    final pattern = input.pattern.trim();
    if (pattern.isEmpty) {
      throw const EmailException(
        EmailErrorKind.invalid,
        'Isi pengirim atau kata kuncinya dulu, ya.',
      );
    }
    if (pattern.length > 200) {
      throw const EmailException(
        EmailErrorKind.invalid,
        'Maksimal 200 karakter.',
      );
    }
    final note = input.note?.trim();
    return _repo.addRule(
      EmailRuleInput(
        kind: input.kind,
        match: input.match,
        pattern: pattern,
        note: note == null || note.isEmpty ? null : note,
      ),
    );
  }
}

final class DeleteEmailRule {
  const DeleteEmailRule(this._repo);
  final EmailRepository _repo;

  Future<void> call(String id) => _repo.deleteRule(id);
}
