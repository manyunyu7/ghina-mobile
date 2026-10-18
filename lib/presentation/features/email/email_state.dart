/// Read providers and shared bits of the Email feature (Gmail read-only).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';

/// Online reads fail fast (offline / not enabled): the page shows the error
/// with "Coba lagi" instead of Riverpod's automatic retry.
Duration? _noRetry(int count, Object error) => null;

/// `GET accounts`: enabled flag, backfill date, connected accounts.
final emailOverviewProvider = FutureProvider.autoDispose<EmailOverview>(
  (ref) => ref.watch(loadEmailOverviewProvider)(),
  retry: _noRetry,
);

/// One tab of the review queue.
final emailSuggestionsProvider = FutureProvider.autoDispose
    .family<EmailSuggestionPage, EmailSuggestionStatus>(
      (ref, status) => ref.watch(loadEmailSuggestionsProvider)(status),
      retry: _noRetry,
    );

/// "Aturan Killa": the user's triage rules.
final emailRulesProvider = FutureProvider.autoDispose<List<EmailTriageRule>>(
  (ref) => ref.watch(loadEmailRulesProvider)(),
  retry: _noRetry,
);

/// The semantic color of an importance: red / orange / blue.
ChunkySwatch emailImportanceSwatch(EmailImportance i) => switch (i) {
  EmailImportance.urgent => GhinaColors.red,
  EmailImportance.important => GhinaColors.orange,
  EmailImportance.info => GhinaColors.blue,
  EmailImportance.ignore => GhinaColors.gray,
};

/// Refreshes every email read (after connect / sync / a decision).
void invalidateEmail(WidgetRef ref) {
  ref.invalidate(emailOverviewProvider);
  ref.invalidate(emailSuggestionsProvider);
}

/// The message of an email error ([EmailException] or anything else).
String emailErrorMessage(Object error) => error is EmailException
    ? error.message
    : 'Ups, ada yang salah. Coba lagi, yuk.';

/// Opens the email in Gmail (http(s) only).
Future<void> openGmailLink(BuildContext context, String? href) async {
  final uri = href == null ? null : Uri.tryParse(href.trim());
  var ok = false;
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showErrorToast(context, 'Email ini nggak bisa dibuka');
  }
}

/// The feature is off for this account (403 `email_not_enabled` or
/// `enabled: false`).
class EmailNotEnabledView extends StatelessWidget {
  const EmailNotEnabledView({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    key: Key('email-not-enabled'),
    mood: MascotMood.thinking,
    title: 'Fitur email belum aktif',
    message:
        'Baca email tagihan & struk otomatis masih tahap uji coba dan baru '
        'dibuka untuk akun tertentu. Nanti kalau sudah dibuka untuk kamu, '
        'menu ini langsung bisa dipakai 👍',
  );
}

/// Error state of an email read: the locked view for `notEnabled`, else the
/// retry view.
class EmailErrorView extends StatelessWidget {
  const EmailErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ScrollableFill(
    child:
        error is EmailException &&
            (error as EmailException).kind == EmailErrorKind.notEnabled
        ? const EmailNotEnabledView()
        : ErrorRetry(message: emailErrorMessage(error), onRetry: onRetry),
  );
}
