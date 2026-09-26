/// Launcher shortcuts: long-press the Ghina icon (Android app shortcuts /
/// iOS Home Screen quick actions). Labels are deliberately generic (private).
library;

enum AppShortcut {
  expense('new_expense', 'Catat pengeluaran', 'ic_shortcut_expense'),
  note('new_note', 'Catatan baru', 'ic_shortcut_note'),
  task('new_task', 'Tugas baru', 'ic_shortcut_task'),

  /// Habits "Lagi pengen…" (urge / emergency screen of a quit habit).
  urge('habit_urge', 'Lagi pengen…', 'ic_shortcut_urge');

  const AppShortcut(this.type, this.label, this.icon);

  /// Stable id handed to the OS and back on launch.
  final String type;
  final String label;

  /// Android drawable resource name (`res/drawable/<icon>.xml`).
  final String icon;

  static AppShortcut? fromType(String type) {
    for (final s in values) {
      if (s.type == type) return s;
    }
    return null;
  }
}

/// Registers the launcher shortcuts and reports which one opened the app.
abstract interface class AppShortcuts {
  /// Shortcuts the user launched, including the one that cold-started the app
  /// (buffered until the first listener). Broadcast.
  Stream<AppShortcut> get launches;

  /// Publishes [items] as the app's dynamic shortcuts (in this order).
  Future<void> install(List<AppShortcut> items);

  Future<void> dispose();
}
