import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'food.link.dismissed.v1';

/// Keep the newest pairs only; old ones can't match again anyway.
const _max = 300;

/// "Bukan" on an "Ini makanan yang sama?" card (`docs/food-transaction-link.md`):
/// `<foodId>:<transactionId>` pairs never suggested again on this device.
final foodLinkDismissedProvider =
    NotifierProvider<FoodLinkDismissedNotifier, Set<String>>(
      FoodLinkDismissedNotifier.new,
    );

class FoodLinkDismissedNotifier extends Notifier<Set<String>> {
  final _added = <String>[];

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final saved =
          (await SharedPreferences.getInstance()).getStringList(_key) ?? [];
      if (ref.mounted) state = {...saved, ..._added};
    } catch (_) {}
  }

  void dismiss(String key) {
    if (state.contains(key)) return;
    _added.add(key);
    state = {...state, key};
    _save();
  }

  Future<void> _save() async {
    try {
      final list = state.toList();
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        list.length > _max ? list.sublist(list.length - _max) : list,
      );
    } catch (_) {}
  }
}
