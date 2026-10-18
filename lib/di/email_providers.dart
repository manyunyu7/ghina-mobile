/// Composition root: Email (Gmail read-only, `/api/mobile/email`) —
/// online-only, not in sync. Tests override [emailRepositoryProvider] and
/// [gmailAuthorizerProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform/platform.dart' show createGmailAuthorizer;
import '../data/repositories/email_repository_impl.dart';
import '../domain/repositories/email_repository.dart';
import '../domain/services/gmail_authorizer.dart';
import '../domain/usecases/email_usecases.dart';
import 'core_providers.dart';

final emailRepositoryProvider = Provider<EmailRepository>(
  (ref) => ApiEmailRepository(ref.watch(apiClientProvider)),
);

final gmailAuthorizerProvider = Provider<GmailAuthorizer>(
  (ref) => createGmailAuthorizer(),
);

final loadEmailOverviewProvider = Provider(
  (ref) => LoadEmailOverview(ref.watch(emailRepositoryProvider)),
);
final connectGmailProvider = Provider(
  (ref) => ConnectGmail(
    ref.watch(emailRepositoryProvider),
    ref.watch(gmailAuthorizerProvider),
  ),
);
final disconnectEmailAccountProvider = Provider(
  (ref) => DisconnectEmailAccount(ref.watch(emailRepositoryProvider)),
);
final syncEmailProvider = Provider(
  (ref) => SyncEmail(ref.watch(emailRepositoryProvider)),
);
final loadEmailSuggestionsProvider = Provider(
  (ref) => LoadEmailSuggestions(ref.watch(emailRepositoryProvider)),
);
final approveEmailSuggestionProvider = Provider(
  (ref) => ApproveEmailSuggestion(ref.watch(emailRepositoryProvider)),
);
final ignoreEmailSuggestionProvider = Provider(
  (ref) => IgnoreEmailSuggestion(ref.watch(emailRepositoryProvider)),
);
final restoreEmailSuggestionProvider = Provider(
  (ref) => RestoreEmailSuggestion(ref.watch(emailRepositoryProvider)),
);
final setEmailTriageProvider = Provider(
  (ref) => SetEmailTriage(ref.watch(emailRepositoryProvider)),
);
final loadEmailInboxProvider = Provider(
  (ref) => LoadEmailInbox(ref.watch(emailRepositoryProvider)),
);
final markEmailReadProvider = Provider(
  (ref) => MarkEmailRead(ref.watch(emailRepositoryProvider)),
);
final loadEmailRulesProvider = Provider(
  (ref) => LoadEmailRules(ref.watch(emailRepositoryProvider)),
);
final addEmailRuleProvider = Provider(
  (ref) => AddEmailRule(ref.watch(emailRepositoryProvider)),
);
final deleteEmailRuleProvider = Provider(
  (ref) => DeleteEmailRule(ref.watch(emailRepositoryProvider)),
);
