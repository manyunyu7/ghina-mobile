/// Composition root: Kantor Claude — online-only, not in sync. Screens use
/// [kantorApiProvider] (null until a token is saved) and
/// [kantorEventsProvider] for live updates. Tests override
/// [kantorConfigStoreProvider].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/kantor_pratinjau.dart';
import 'kantor_complex_providers.dart';

import '../data/datasources/remote/kantor_api.dart';

export 'kantor_complex_providers.dart';

export '../data/datasources/remote/kantor_api.dart'
    show
        KantorApi,
        KantorConfig,
        KantorComplexProfile,
        KantorException,
        KantorFailure,
        KantorPratinjauApi;
export '../data/models/kantor_pratinjau.dart';

final kantorConfigStoreProvider = Provider<KantorConfigStore>(
  (ref) => KantorConfigStore(),
);

/// URL + token. `save` updates every Kantor screen at once.
final kantorConfigProvider =
    AsyncNotifierProvider<KantorConfigNotifier, KantorConfig>(
      KantorConfigNotifier.new,
    );

final class KantorConfigNotifier extends AsyncNotifier<KantorConfig> {
  @override
  Future<KantorConfig> build() => ref.read(kantorConfigStoreProvider).load();

  Future<void> save({
    required String baseUrl,
    required String token,
    String? name,
    String? profileId,
  }) async {
    final next = KantorConfig(baseUrl: baseUrl.trim(), token: token.trim());
    await ref
        .read(kantorConfigStoreProvider)
        .save(next, name: name, profileId: profileId);
    ref.invalidate(kantorComplexProfilesProvider);
    ref.invalidate(kantorActiveComplexIdProvider);
    state = AsyncData(next);
  }

  Future<void> activate(String profileId) async {
    final profiles = await ref.read(kantorComplexProfilesProvider.future);
    final profile = profiles.where((e) => e.id == profileId).firstOrNull;
    if (profile == null) {
      throw const KantorException(
        KantorFailure.notFound,
        'Kompleks tidak ditemukan.',
      );
    }
    // A failed target must never replace the current connection.
    await ref.read(kantorComplexApiProvider(profileId)).get('/api/state');
    await ref.read(kantorConfigStoreProvider).activate(profileId);
    state = AsyncData(profile.config);
    ref.invalidate(kantorActiveComplexIdProvider);
  }
}

/// Null while no token is saved: show the settings screen instead.
final kantorApiProvider = Provider<KantorApi?>((ref) {
  final config = ref.watch(kantorConfigProvider).value;
  return config != null && config.ready ? KantorApi(config) : null;
});

/// Live office events (`{t: …}` maps from the daemon's `/ws`).
final kantorEventsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final api = ref.watch(kantorApiProvider);
  return api == null ? const Stream.empty() : api.events();
});

KantorApi _pratinjauApi(Ref ref) {
  final api = ref.watch(kantorApiProvider);
  if (api == null) {
    throw const KantorException(
      KantorFailure.unauthorized,
      'Token Kantor belum diisi.',
    );
  }
  return api;
}

/// Refetch when the daemon pushes `{t:'pratinjau', office}` for [office].
void _pratinjauLive(Ref ref, String office) {
  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());
  ref.listen(kantorEventsProvider, (_, next) {
    final e = next.value;
    if (e == null || e['t'] != 'pratinjau' || e['office'] != office) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), ref.invalidateSelf);
  });
}

/// Pratinjau feed for `(office, status)`; status `baru|perlu|semua|disimpan|arsip`.
final kantorPratinjauFeedProvider = FutureProvider.autoDispose
    .family<PratinjauFeed, (String, String)>((ref, arg) async {
      final api = _pratinjauApi(ref);
      _pratinjauLive(ref, arg.$1);
      return api.pratinjauList(arg.$1, status: arg.$2);
    });

/// Pratinjau sent by one session `(office, sid)` (all statuses, newest first).
final kantorPratinjauSessionProvider = FutureProvider.autoDispose
    .family<PratinjauFeed, (String, String)>((ref, arg) async {
      final api = _pratinjauApi(ref);
      _pratinjauLive(ref, arg.$1);
      return api.pratinjauList(arg.$1, status: 'semua', sid: arg.$2);
    });

/// Disk used by previews in `office`.
final kantorPratinjauUsageProvider = FutureProvider.autoDispose
    .family<PratinjauUsage, String>(
      (ref, office) => _pratinjauApi(ref).pratinjauUsage(office),
    );

/// One pratinjau item `(office, id)`.
final kantorPratinjauItemProvider = FutureProvider.autoDispose
    .family<PratinjauItem, (String, String)>((ref, arg) async {
      final api = _pratinjauApi(ref);
      ref.listen(kantorEventsProvider, (_, next) {
        final e = next.value;
        final item = e?['item'];
        if (e?['t'] == 'pratinjau' && item is Map && item['id'] == arg.$2) {
          ref.invalidateSelf();
        }
      });
      return api.pratinjauGet(arg.$1, arg.$2);
    });
