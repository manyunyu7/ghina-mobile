import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../state/killa_access_provider.dart';

/// A message being sent (shown as a pending bubble until the reply lands).
final class KillaPending {
  const KillaPending({
    required this.text,
    required this.media,
    required this.startedAt,
  });

  final String text;
  final List<KillaOutgoingMedia> media;
  final DateTime startedAt;
}

final class KillaChatState {
  const KillaChatState({
    this.messages = const [],
    this.nextBefore,
    this.loading = true,
    this.loadingOlder = false,
    this.pending,
    this.error,
    this.model = KillaModel.defaultModel,
    this.stillProcessing = false,
  });

  /// Oldest first.
  final List<KillaMessage> messages;

  /// Cursor of the older page; null = start reached.
  final String? nextBefore;

  /// First page loading.
  final bool loading;
  final bool loadingOlder;
  final KillaPending? pending;

  /// Error of the first load (the page shows it instead of the chat).
  final KillaException? error;
  final KillaModel model;

  /// The last send timed out: the engine may still answer (polling picks it
  /// up).
  final bool stillProcessing;

  bool get forbidden => error?.kind == KillaErrorKind.forbidden;
  bool get hasOlder => nextBefore != null;

  KillaChatState copyWith({
    List<KillaMessage>? messages,
    Object? nextBefore = _keep,
    bool? loading,
    bool? loadingOlder,
    Object? pending = _keep,
    Object? error = _keep,
    KillaModel? model,
    bool? stillProcessing,
  }) => KillaChatState(
    messages: messages ?? this.messages,
    nextBefore: identical(nextBefore, _keep)
        ? this.nextBefore
        : nextBefore as String?,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    pending: identical(pending, _keep)
        ? this.pending
        : pending as KillaPending?,
    error: identical(error, _keep) ? this.error : error as KillaException?,
    model: model ?? this.model,
    stillProcessing: stillProcessing ?? this.stillProcessing,
  );
}

const Object _keep = Object();

/// Outcome of [KillaChatController.send].
sealed class KillaSendOutcome {
  const KillaSendOutcome();
}

final class KillaSent extends KillaSendOutcome {
  const KillaSent();
}

/// The send failed. [recorded]: the server has the user message anyway (seen
/// after re-fetching), so the composer must not restore the text.
final class KillaSendFailed extends KillaSendOutcome {
  const KillaSendFailed(this.error, {required this.recorded});
  final KillaException error;
  final bool recorded;
}

/// The Killa chat: pages of the log, polling, sending, "sesi baru".
class KillaChatController extends Notifier<KillaChatState> {
  static const pageSize = 50;

  @override
  KillaChatState build() {
    Future.microtask(load);
    return const KillaChatState();
  }

  KillaAccessController get _access => ref.read(killaAccessProvider.notifier);

  void _seen(KillaException e) {
    if (e.kind == KillaErrorKind.forbidden) _access.markForbidden();
  }

  Future<void> load() async {
    if (!ref.mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final page = await ref.read(loadKillaChatProvider)(limit: pageSize);
      if (!ref.mounted) return;
      _access.markAllowed();
      state = state.copyWith(
        messages: mergeKillaMessages(const [], page.messages),
        nextBefore: page.nextBefore,
        loading: false,
        error: null,
      );
    } on KillaException catch (e) {
      _seen(e);
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadOlder() async {
    final before = state.nextBefore;
    if (before == null || state.loadingOlder) return;
    state = state.copyWith(loadingOlder: true);
    try {
      final page = await ref.read(loadKillaChatProvider)(
        before: before,
        limit: pageSize,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: mergeKillaMessages(state.messages, page.messages),
        nextBefore: page.nextBefore,
        loadingOlder: false,
      );
    } on KillaException catch (e) {
      _seen(e);
      if (!ref.mounted) return;
      state = state.copyWith(loadingOlder: false);
      rethrow;
    }
  }

  /// Polls the newest page (merged, never duplicated). Silent: errors are
  /// ignored except a 403. Returns the fetched page, or null.
  Future<KillaMessagePage?> refreshNewest() async {
    if (!ref.mounted || state.loading) return null;
    try {
      final page = await ref.read(loadKillaChatProvider)(limit: pageSize);
      if (!ref.mounted) return page;
      final merged = mergeKillaMessages(state.messages, page.messages);
      final gotReply =
          state.stillProcessing &&
          page.messages.isNotEmpty &&
          page.messages.last.role == KillaRole.assistant;
      state = state.copyWith(
        messages: merged,
        // An empty log before: take the cursor of this first page.
        nextBefore: state.messages.isEmpty ? page.nextBefore : state.nextBefore,
        error: null,
        stillProcessing: gotReply ? false : state.stillProcessing,
      );
      return page;
    } on KillaException catch (e) {
      _seen(e);
      if (e.kind == KillaErrorKind.forbidden && ref.mounted) {
        state = state.copyWith(error: e);
      }
      return null;
    }
  }

  void setModel(KillaModel m) => state = state.copyWith(model: m);

  Future<KillaSendOutcome> send(
    String text,
    List<KillaOutgoingMedia> media,
  ) async {
    final started = DateTime.now();
    state = state.copyWith(
      pending: KillaPending(
        text: text.trim(),
        media: media,
        startedAt: started,
      ),
      stillProcessing: false,
    );
    try {
      final r = await ref.read(sendKillaMessageProvider)(
        text: text,
        model: state.model,
        media: media,
      );
      if (!ref.mounted) return const KillaSent();
      state = state.copyWith(
        messages: mergeKillaMessages(state.messages, [r.userMessage, r.reply]),
        pending: null,
      );
      return const KillaSent();
    } on KillaException catch (e) {
      _seen(e);
      if (!ref.mounted) return KillaSendFailed(e, recorded: false);
      state = state.copyWith(
        pending: null,
        stillProcessing: e.kind == KillaErrorKind.timeout,
      );
      // The server records the user message before asking the engine: it
      // may be there even though this request failed.
      final page = await refreshNewest();
      final t = text.trim();
      final recorded =
          page?.messages.any(
            (m) =>
                m.role == KillaRole.user &&
                m.body.trim() == t &&
                !m.createdAt.isBefore(
                  started.subtract(const Duration(minutes: 2)),
                ),
          ) ??
          false;
      return KillaSendFailed(e, recorded: recorded);
    }
  }

  Future<void> newSession() async {
    final divider = await ref.read(startKillaSessionProvider)();
    if (!ref.mounted) return;
    state = state.copyWith(
      messages: mergeKillaMessages(state.messages, [divider]),
    );
  }
}

final killaChatControllerProvider =
    NotifierProvider.autoDispose<KillaChatController, KillaChatState>(
      KillaChatController.new,
    );

/// Engine attachments (Bearer media proxy), cached for 10 minutes after the
/// last listener goes away.
final killaMediaProvider = FutureProvider.autoDispose
    .family<KillaMediaFile, String>((ref, path) async {
      final file = await ref.watch(fetchKillaMediaProvider)(path);
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 10), link.close);
      ref.onDispose(timer.cancel);
      return file;
    }, retry: (count, error) => null);
