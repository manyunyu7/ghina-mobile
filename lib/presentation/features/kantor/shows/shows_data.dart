import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import 'shows_model.dart';

/// Open shows (newest first), unseen count and the latest live arrival.
final class KantorShowsState {
  const KantorShowsState({
    this.items = const [],
    this.loaded = false,
    this.error,
    this.fresh,
  });

  final List<KantorShow> items;
  final bool loaded;
  final Object? error;

  /// Last show that arrived live; the button turns it into a notification.
  final KantorShow? fresh;

  int get unseen => items.where((i) => !i.seen).length;

  KantorShowsState copyWith({
    List<KantorShow>? items,
    bool? loaded,
    Object? error,
    KantorShow? fresh,
    bool clearError = false,
  }) => KantorShowsState(
    items: items ?? this.items,
    loaded: loaded ?? this.loaded,
    error: clearError ? null : (error ?? this.error),
    fresh: fresh ?? this.fresh,
  );
}

final kantorShowsProvider =
    NotifierProvider<KantorShowsNotifier, KantorShowsState>(
      KantorShowsNotifier.new,
    );

final class KantorShowsNotifier extends Notifier<KantorShowsState> {
  @override
  KantorShowsState build() {
    ref.listen(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e != null) _onEvent(e);
    });
    ref.listen(kantorApiProvider, (_, _) => refresh());
    Future.microtask(refresh);
    return const KantorShowsState();
  }

  static List<KantorShow> _sorted(Iterable<KantorShow> l) =>
      l.toList()..sort((a, b) => b.at.compareTo(a.at));

  Future<void> refresh() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final j = await api.get('/api/shows', query: {'open': '1'});
      final list = [
        for (final e in (j as List? ?? const []))
          if (e is Map) KantorShow.fromJson(e.cast<String, dynamic>()),
      ].where((s) => !s.closed);
      state = state.copyWith(
        items: _sorted(list),
        loaded: true,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loaded: true, error: e);
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    final raw = e['item'];
    if (raw is! Map) return;
    final item = KantorShow.fromJson(raw.cast<String, dynamic>());
    final known = state.items.any((s) => s.id == item.id);
    switch (e['t']) {
      case 'show':
        if (known) return;
        state = state.copyWith(
          items: _sorted([...state.items, item]),
          fresh: item,
        );
      case 'show-update':
        final rest = state.items.where((s) => s.id != item.id);
        state = state.copyWith(
          items: _sorted(item.closed ? rest : [...rest, item]),
        );
    }
  }

  void _patch(String id, bool? seen, bool? closed) {
    state = state.copyWith(
      items: [
        for (final s in state.items)
          if (s.id != id)
            s
          else if (closed != true)
            s.copyWith(seen: seen, closed: closed),
      ],
    );
  }

  Future<void> _send(String id, Map<String, Object> body) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      await api.post('/api/shows/${Uri.encodeComponent(id)}', body);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markSeen(String id) async {
    // Also when the list has not loaded yet: the caller only asks for unseen items.
    if (state.items.any((s) => s.id == id && s.seen)) return;
    _patch(id, true, null);
    await _send(id, {'seen': true});
  }

  Future<void> close(String id) async {
    _patch(id, null, true);
    await _send(id, {'closed': true, 'seen': true});
  }

  Future<void> closeAll() async {
    for (final s in List.of(state.items)) {
      await close(s.id);
    }
  }
}
