/// Read providers and shared bits of "Impor mutasi" (statement import).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/killa_access_provider.dart';

/// Online reads fail fast (offline / forbidden): the page shows the error
/// with "Coba lagi" instead of Riverpod's automatic retry.
Duration? _noRetry(int count, Object error) => null;

/// Runs a read, remembering the account's Killa access (403 → forbidden).
Future<T> trackStatementAccess<T>(Ref ref, Future<T> Function() body) async {
  try {
    final v = await body();
    ref.read(killaAccessProvider.notifier).markAllowed();
    return v;
  } on StatementException catch (e) {
    if (e.kind == StatementErrorKind.forbidden) {
      ref.read(killaAccessProvider.notifier).markForbidden();
    }
    rethrow;
  }
}

/// `GET statements`.
final statementImportsProvider =
    FutureProvider.autoDispose<List<StatementImport>>(
      (ref) => trackStatementAccess(
        ref,
        () => ref.watch(statementRepositoryProvider).list(),
      ),
      retry: _noRetry,
    );

/// `GET statements/{id}`: the import and its rows.
final statementDetailProvider = FutureProvider.autoDispose
    .family<StatementDetail, String>(
      (ref, id) => trackStatementAccess(
        ref,
        () => ref.watch(statementRepositoryProvider).detail(id),
      ),
      retry: _noRetry,
    );

/// How often [statementAttentionProvider] rechecks while Killa is reading.
const statementAttentionPoll = Duration(seconds: 8);

/// Imports the Transactions page flags (badge + status cards), so an upload
/// can be left behind: rechecked every [statementAttentionPoll] while one is
/// being read and whenever the app comes back to the foreground. Offline,
/// errors and accounts without Killa → [StatementAttention.none] (the page
/// shows nothing rather than an error).
final statementAttentionProvider = Provider.autoDispose<StatementAttention>((
  ref,
) {
  if (ref.watch(killaAccessProvider) == KillaAccess.forbidden) {
    return StatementAttention.none;
  }
  final lifecycle = AppLifecycleListener(
    onResume: () => ref.invalidate(statementImportsProvider),
  );
  ref.onDispose(lifecycle.dispose);
  // `.value` keeps the previous list while a refetch is in flight.
  final imports = ref.watch(statementImportsProvider).value;
  if (imports == null) return StatementAttention.none;
  final attention = StatementAttention.of(
    imports,
    ref.read(clockProvider).now(),
  );
  if (attention.parsing.isNotEmpty) {
    final poll = Timer(
      statementAttentionPoll,
      () => ref.invalidate(statementImportsProvider),
    );
    ref.onDispose(poll.cancel);
  }
  return attention;
});

/// Refreshes the list and every open detail (after a decision).
void invalidateStatements(WidgetRef ref) {
  ref.invalidate(statementImportsProvider);
  ref.invalidate(statementDetailProvider);
}

/// The message of a statement error (or anything else).
String statementErrorMessage(Object error) => error is StatementException
    ? error.message
    : 'Ups, ada yang salah. Coba lagi, yuk.';

bool isStatementForbidden(Object error) =>
    error is StatementException && error.kind == StatementErrorKind.forbidden;

ChunkySwatch statementStatusSwatch(StatementStatus s) => switch (s) {
  StatementStatus.parsing => GhinaColors.blue,
  StatementStatus.ready => GhinaColors.orange,
  StatementStatus.failed => GhinaColors.red,
  StatementStatus.done => GhinaColors.green,
};

IconData statementStatusIcon(StatementStatus s) => switch (s) {
  StatementStatus.parsing => Icons.hourglass_top_rounded,
  StatementStatus.ready => Icons.fact_check_rounded,
  StatementStatus.failed => Icons.error_outline_rounded,
  StatementStatus.done => Icons.check_rounded,
};

/// `BCA •1234 · 1 Okt – 31 Okt 2026` (parts that are known).
String statementCaption(StatementImport i) {
  final from = i.periodFrom, to = i.periodTo;
  final period = from != null && to != null
      ? '${Fmt.date(from)} – ${Fmt.date(to)}'
      : null;
  final account = [
    ?i.bank,
    if (i.accountLast4 != null) '•${i.accountLast4}',
  ].join(' ');
  return [if (account.isNotEmpty) account, ?period].join(' · ');
}

/// `1,2 MB` / `340 KB`.
String fileSizeLabel(int bytes) => bytes >= 1024 * 1024
    ? '${Fmt.number(bytes / (1024 * 1024), decimals: 1)} MB'
    : '${Fmt.number((bytes / 1024).ceil())} KB';
