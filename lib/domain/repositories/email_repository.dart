import '../entities/email.dart';

/// Gmail read-only (`/api/mobile/email`). **Online-only**: every method throws
/// an [EmailException] (`notEnabled` when the feature is off for this user).
abstract interface class EmailRepository {
  /// `GET accounts` — never throws `notEnabled` (returns `enabled: false`).
  Future<EmailOverview> overview();

  /// `POST accounts/connect` — reconnecting the same address keeps its data.
  Future<EmailAccount> connect(String serverAuthCode);

  /// `DELETE accounts/{id}` — approved transactions stay.
  Future<void> disconnect(String accountId);

  /// `POST sync` — every account, or only [accountId]. With [background] the
  /// server answers at once (202, no results) and syncs after the response;
  /// accounts then report `syncing` until it is done.
  Future<List<EmailSyncResult>> sync({
    String? accountId,
    bool background = false,
  });

  /// `GET suggestions` — pending oldest first, the others newest first.
  Future<EmailSuggestionPage> suggestions(
    EmailSuggestionStatus status, {
    int limit = 50,
    int offset = 0,
  });

  /// `POST suggestions/{id}/approve` → the created transaction id.
  Future<String> approve(String id, EmailApproval approval);

  /// `POST suggestions/{id}/ignore`.
  Future<void> ignore(String id);

  /// `POST suggestions/{id}/restore` — back to pending.
  Future<void> restore(String id);

  /// `PATCH accounts/{id}` `{triage}` — "Killa baca semua email".
  Future<EmailAccount> setTriage(String accountId, bool on);

  /// `GET inbox` — triaged mail of [importance] (all shown ones when empty),
  /// newest first.
  Future<EmailInboxPage> inbox({
    Set<EmailImportance> importance = const {},
    int limit = 50,
    int offset = 0,
  });

  /// `POST inbox/{id}/read`.
  Future<void> markRead(String id);

  /// `GET inbox/rules`.
  Future<List<EmailTriageRule>> rules();

  /// `POST inbox/rules`.
  Future<EmailTriageRule> addRule(EmailRuleInput input);

  /// `DELETE inbox/rules/{id}`.
  Future<void> deleteRule(String id);
}
