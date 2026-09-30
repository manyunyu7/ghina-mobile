/// Composition root, part 6: Killa (`docs/killa.md`) — online-only, not in
/// sync. Tests override [killaRepositoryProvider] (and
/// [killaMediaPickerProvider]).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/remote/killa_api.dart';
import '../data/platform/platform.dart' show createKillaMediaPicker;
import '../data/repositories/killa_repository_impl.dart';
import '../domain/repositories/killa_repository.dart';
import '../domain/services/killa_media_picker.dart';
import '../domain/usecases/killa_usecases.dart';
import 'core_providers.dart';

final killaApiProvider = Provider<KillaApi>(
  (ref) => DioKillaApi(ref.watch(apiClientProvider)),
);

final killaRepositoryProvider = Provider<KillaRepository>(
  (ref) => RemoteKillaRepository(ref.watch(killaApiProvider)),
);

final killaMediaPickerProvider = Provider<KillaMediaPicker>(
  (ref) => createKillaMediaPicker(),
);

final loadKillaChatProvider = Provider(
  (ref) => LoadKillaChat(ref.watch(killaRepositoryProvider)),
);
final sendKillaMessageProvider = Provider(
  (ref) => SendKillaMessage(ref.watch(killaRepositoryProvider)),
);
final startKillaSessionProvider = Provider(
  (ref) => StartKillaSession(ref.watch(killaRepositoryProvider)),
);
final fetchKillaMediaProvider = Provider(
  (ref) => FetchKillaMedia(ref.watch(killaRepositoryProvider)),
);
final browseKillaFilesProvider = Provider(
  (ref) => BrowseKillaFiles(ref.watch(killaRepositoryProvider)),
);
final readKillaFileProvider = Provider(
  (ref) => ReadKillaFile(ref.watch(killaRepositoryProvider)),
);
final saveKillaFileProvider = Provider(
  (ref) => SaveKillaFile(ref.watch(killaRepositoryProvider)),
);
final commitKillaWorkspaceProvider = Provider(
  (ref) => CommitKillaWorkspace(ref.watch(killaRepositoryProvider)),
);
final loadKillaCommitsProvider = Provider(
  (ref) => LoadKillaCommits(ref.watch(killaRepositoryProvider)),
);
final loadKillaRemindersProvider = Provider(
  (ref) => LoadKillaReminders(ref.watch(killaRepositoryProvider)),
);
final cancelKillaReminderProvider = Provider(
  (ref) => CancelKillaReminder(ref.watch(killaRepositoryProvider)),
);
final loadKillaUsageProvider = Provider(
  (ref) => LoadKillaUsage(ref.watch(killaRepositoryProvider)),
);
