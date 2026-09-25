/// Wire entity names (contract "Entities").
abstract final class SyncEntity {
  static const wallets = 'wallets';
  static const categories = 'categories';
  static const transactions = 'transactions';
  static const budgets = 'budgets';
  static const subscriptions = 'subscriptions';
  static const planned = 'planned';
  static const prayers = 'prayers';
  static const health = 'health';
  static const food = 'food';
  static const taskAreas = 'taskAreas';
  static const tasks = 'tasks';
  static const noteLabels = 'noteLabels';
  static const notes = 'notes';
  static const socialAccounts = 'socialAccounts';
  static const contentPillars = 'contentPillars';
  static const contentItems = 'contentItems';
  static const contentPosts = 'contentPosts';
  static const habits = 'habits';
  static const habitLogs = 'habitLogs';
  static const assets = 'assets';
  static const assetTrades = 'assetTrades';

  /// Apply order for pulls (referenced entities first).
  static const all = [
    wallets,
    categories,
    transactions,
    budgets,
    subscriptions,
    planned,
    prayers,
    health,
    food,
    taskAreas,
    tasks,
    noteLabels,
    notes,
    socialAccounts,
    contentPillars,
    contentItems,
    contentPosts,
    habits,
    habitLogs,
    assets,
    assetTrades,
  ];

  /// Notes module (`docs/notes.md`): a pull carrying [noteLabels] comes from a
  /// notes-aware server.
  static const notesModule = [noteLabels, notes];

  /// Content planner (`docs/content.md`).
  static const contentModule = [
    socialAccounts,
    contentPillars,
    contentItems,
    contentPosts,
  ];

  /// Habits (`docs/habits.md`).
  static const habitsModule = [habits, habitLogs];

  /// Investments (`docs/investments.md`).
  static const investmentsModule = [assets, assetTrades];
}
