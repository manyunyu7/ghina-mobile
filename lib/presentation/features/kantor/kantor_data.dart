import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../di/di.dart';

/// Shared Kantor reads. They refetch when the daemon pushes a relevant event.

/// Events that make the complex-level lists stale.
bool _touchesState(Map<String, dynamic> e) => switch (e['t']) {
  'session' || 'session-gone' || 'inbox' || 'inbox-update' => true,
  'changed' => true,
  _ => false,
};

void _refetchOnEvents(Ref ref, bool Function(Map<String, dynamic>) test) {
  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());
  ref.listen(kantorEventsProvider, (_, next) {
    final e = next.value;
    if (e == null || !test(e)) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), ref.invalidateSelf);
  });
}

/// `GET /api/state`: offices, inbox, loose sessions, settings.
final kantorStateProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final api = ref.watch(kantorApiProvider);
  if (api == null) {
    throw const KantorException(
      KantorFailure.unauthorized,
      'Token Kantor belum diisi.',
    );
  }
  _refetchOnEvents(ref, _touchesState);
  return Map<String, dynamic>.from(await api.get('/api/state') as Map);
});

/// `GET /api/offices/<id>`; the complex pseudo-office needs no fetch.
final kantorOfficeProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      if (id == '_kompleks') {
        return {'id': id, 'name': 'Kompleks', 'sessions': <dynamic>[]};
      }
      final api = ref.watch(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        );
      }
      _refetchOnEvents(ref, (e) {
        final t = e['t'];
        if (t == 'session' || t == 'session-gone') return e['office'] == id;
        return t == 'changed' &&
            (e['office'] == id || e['office'] == '*') &&
            (e['what'] == 'roles' ||
                e['what'] == 'plan' ||
                e['what'] == 'offices');
      });
      return Map<String, dynamic>.from(
        await api.get('/api/offices/${Uri.encodeComponent(id)}') as Map,
      );
    });

/// `GET /api/sessions/recent-ended`.
final kantorEndedProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  final api = ref.watch(kantorApiProvider);
  if (api == null) return const [];
  _refetchOnEvents(ref, (e) => e['t'] == 'session' || e['t'] == 'session-gone');
  try {
    return List<dynamic>.from(
      await api.get('/api/sessions/recent-ended') as List,
    );
  } on KantorException {
    return const [];
  }
});

const _lastOfficeKey = 'kantor.last_office';

/// The office opened last, or null (also when storage is unavailable).
final kantorLastOfficeProvider = FutureProvider<String?>((ref) async {
  try {
    return (await SharedPreferences.getInstance()).getString(_lastOfficeKey);
  } catch (_) {
    return null;
  }
});

Future<void> rememberKantorOffice(String id) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_lastOfficeKey, id);
  } catch (_) {}
}

/// Set when the user deliberately returns to the complex, so the home page
/// does not bounce them straight back into the last office. Consumed once.
class KantorSkipResume extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final kantorSkipResumeProvider = NotifierProvider<KantorSkipResume, bool>(
  KantorSkipResume.new,
);
