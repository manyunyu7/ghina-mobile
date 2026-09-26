import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/quick_actions_app_shortcuts.dart';
import 'package:ghina/domain/services/app_shortcuts.dart';
import 'package:quick_actions/quick_actions.dart';

/// Stands in for the plugin: records items, lets the test fire launches.
class _FakePlugin implements QuickActions {
  QuickActionHandler? handler;
  List<ShortcutItem>? items;
  int initializations = 0;

  /// What the OS reports when `initialize` runs (cold start).
  String? launchAction;

  @override
  Future<void> initialize(QuickActionHandler handler) async {
    initializations++;
    this.handler = handler;
    if (launchAction != null) handler(launchAction!);
  }

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) async =>
      this.items = items;

  @override
  Future<void> clearShortcutItems() async => items = null;
}

void main() {
  test(
    'cold start: the launching shortcut reaches the first listener',
    () async {
      final plugin = _FakePlugin()..launchAction = 'new_expense';
      final s = QuickActionsAppShortcuts(plugin: plugin);
      final got = <AppShortcut>[];
      s.launches.listen(got.add);
      await pumpEventQueue();
      expect(got, [AppShortcut.expense]);
      expect(plugin.initializations, 1);
    },
  );

  test(
    'warm start: later launches are forwarded; unknown types dropped',
    () async {
      final plugin = _FakePlugin();
      final s = QuickActionsAppShortcuts(plugin: plugin);
      final got = <AppShortcut>[];
      s.launches.listen(got.add);
      await pumpEventQueue();
      plugin.handler!('habit_urge');
      plugin.handler!('something_else');
      plugin.handler!('new_task');
      await pumpEventQueue();
      expect(got, [AppShortcut.urge, AppShortcut.task]);
    },
  );

  test(
    'a launch while nobody listens is buffered for the next listener',
    () async {
      final plugin = _FakePlugin();
      final s = QuickActionsAppShortcuts(plugin: plugin);
      await s.install(AppShortcut.values); // initializes the plugin
      plugin.handler!('new_note');
      final got = <AppShortcut>[];
      s.launches.listen(got.add);
      await pumpEventQueue();
      expect(got, [AppShortcut.note]);
      expect(plugin.initializations, 1);
    },
  );

  test('install publishes type, generic label and drawable icon', () async {
    final plugin = _FakePlugin();
    await QuickActionsAppShortcuts(plugin: plugin).install(AppShortcut.values);
    expect(
      [for (final i in plugin.items!) (i.type, i.localizedTitle, i.icon)],
      [
        ('new_expense', 'Catat pengeluaran', 'ic_shortcut_expense'),
        ('new_note', 'Catatan baru', 'ic_shortcut_note'),
        ('new_task', 'Tugas baru', 'ic_shortcut_task'),
        ('habit_urge', 'Lagi pengen…', 'ic_shortcut_urge'),
      ],
    );
  });
}
