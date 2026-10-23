import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kantor_providers.dart';

final kantorComplexProfilesProvider =
    AsyncNotifierProvider<
      KantorComplexProfilesNotifier,
      List<KantorComplexProfile>
    >(KantorComplexProfilesNotifier.new);

final class KantorComplexProfilesNotifier
    extends AsyncNotifier<List<KantorComplexProfile>> {
  @override
  Future<List<KantorComplexProfile>> build() =>
      ref.read(kantorConfigStoreProvider).loadProfiles();

  Future<void> upsert(
    KantorComplexProfile profile, {
    bool activate = false,
  }) async {
    if (activate) await KantorApi(profile.config).get('/api/state');
    await ref
        .read(kantorConfigStoreProvider)
        .upsert(profile, activate: activate);
    state = AsyncData(await ref.read(kantorConfigStoreProvider).loadProfiles());
    if (activate) {
      ref.invalidate(kantorConfigProvider);
      ref.invalidate(kantorActiveComplexIdProvider);
    }
  }

  Future<void> remove(String id) async {
    await ref.read(kantorConfigStoreProvider).remove(id);
    state = AsyncData(await ref.read(kantorConfigStoreProvider).loadProfiles());
  }
}

final kantorActiveComplexIdProvider = FutureProvider<String?>((ref) {
  ref.watch(kantorConfigProvider);
  return ref.read(kantorConfigStoreProvider).loadActiveId();
});

final kantorActiveComplexProvider = Provider<KantorComplexProfile?>((ref) {
  final config = ref.watch(kantorConfigProvider).value;
  final id = ref.watch(kantorActiveComplexIdProvider).value;
  final profiles = ref.watch(kantorComplexProfilesProvider).value;
  if (config == null || profiles == null) return null;
  final matching = profiles.where(
    (p) => p.baseUrl == config.baseUrl && p.token == config.token,
  );
  return matching.where((p) => p.id == id).firstOrNull ?? matching.firstOrNull;
});

/// One client per connection, so requests never borrow the active token.
final kantorComplexApiProvider = Provider.family<KantorApi, String>((ref, id) {
  final profile = ref
      .watch(kantorComplexProfilesProvider)
      .value
      ?.where((p) => p.id == id)
      .firstOrNull;
  if (profile == null) {
    throw const KantorException(
      KantorFailure.notFound,
      'Kompleks tidak ditemukan.',
    );
  }
  return KantorApi(profile.config);
});

/// Independent async states: an offline complex cannot hide another's agents.
/// All visible families load concurrently. Active events keep its row current;
/// pull-to-refresh can retry any inactive complex independently.
final kantorComplexStateProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      await ref.watch(kantorComplexProfilesProvider.future);
      final api = ref.watch(kantorComplexApiProvider(id));
      Timer? debounce;
      ref.onDispose(() => debounce?.cancel());
      if (ref.watch(kantorActiveComplexProvider)?.id == id) {
        ref.listen(kantorEventsProvider, (_, next) {
          if (next.value == null) return;
          debounce?.cancel();
          debounce = Timer(
            const Duration(milliseconds: 500),
            ref.invalidateSelf,
          );
        });
      }
      return Map<String, dynamic>.from(await api.get('/api/state') as Map);
    });
