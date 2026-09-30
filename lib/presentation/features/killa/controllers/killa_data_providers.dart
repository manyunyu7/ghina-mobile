import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../state/killa_access_provider.dart';

/// Runs a Killa read, remembering the account's access (403 → forbidden).
Future<T> _track<T>(Ref ref, Future<T> Function() body) async {
  try {
    final v = await body();
    ref.read(killaAccessProvider.notifier).markAllowed();
    return v;
  } on KillaException catch (e) {
    if (e.kind == KillaErrorKind.forbidden) {
      ref.read(killaAccessProvider.notifier).markForbidden();
    }
    rethrow;
  }
}

/// Killa errors are answers (403, engine off, 413…): never auto-retry.
Duration? _noRetry(int count, Object error) => null;

/// Workspace directory listing (`""` = root).
final killaDirProvider = FutureProvider.autoDispose
    .family<KillaDirListing, String>(
      (ref, path) =>
          _track(ref, () => ref.watch(browseKillaFilesProvider)(path)),
      retry: _noRetry,
    );

/// A workspace text file.
final killaFileProvider = FutureProvider.autoDispose
    .family<KillaFileContent, String>(
      (ref, path) => _track(ref, () => ref.watch(readKillaFileProvider)(path)),
      retry: _noRetry,
    );

/// Latest 100 commits.
final killaCommitsProvider = FutureProvider.autoDispose<List<KillaCommit>>(
  (ref) => _track(ref, () => ref.watch(loadKillaCommitsProvider)(limit: 100)),
  retry: _noRetry,
);

/// "Pengingat Killa", soonest first.
final killaRemindersProvider = FutureProvider.autoDispose<List<KillaReminder>>(
  (ref) => _track(ref, () => ref.watch(loadKillaRemindersProvider)()),
  retry: _noRetry,
);

/// Usage of the last [days] days.
final killaUsageProvider = FutureProvider.autoDispose.family<KillaUsage, int>(
  (ref, days) =>
      _track(ref, () => ref.watch(loadKillaUsageProvider)(days: days)),
  retry: _noRetry,
);
