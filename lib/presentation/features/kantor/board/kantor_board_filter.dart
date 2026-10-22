import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kantor_board_lib.dart';

/// Board filters and view, remembered per office on this phone.
final kantorFilterProvider =
    NotifierProvider.family<KFilterNotifier, KFilter, String>(
      KFilterNotifier.new,
    );

class KFilterNotifier extends Notifier<KFilter> {
  KFilterNotifier(this.officeId);
  final String officeId;

  String get _key => 'kantor.board.$officeId';

  @override
  KFilter build() {
    _load();
    return const KFilter();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) state = KFilter.fromJson(j);
    } catch (_) {
      // defaults are fine
    }
  }

  void set(KFilter next) {
    state = next;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode(next.toJson())))
        .catchError((_) => false);
  }

  void update(KFilter Function(KFilter f) fn) => set(fn(state));

  void clear() =>
      set(KFilter(group: state.group, list: state.list, me: state.me));
}
