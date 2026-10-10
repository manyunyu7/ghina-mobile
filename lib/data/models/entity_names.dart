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
  static const reminders = 'reminders';
  static const calendarEvents = 'calendarEvents';
  static const people = 'people';
  static const personCategories = 'personCategories';
  static const personFields = 'personFields';
  static const personDates = 'personDates';
  static const habitFields = 'habitFields';
  static const habitEvents = 'habitEvents';
  static const dreamCategories = 'dreamCategories';
  static const dreamFields = 'dreamFields';
  static const dreams = 'dreams';
  static const dreamMetrics = 'dreamMetrics';
  static const dreamSteps = 'dreamSteps';

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
    reminders,
    calendarEvents,
    // Referenced entities first: categories/field defs before people before
    // their dates; habit fields after habits.
    personCategories,
    personFields,
    people,
    personDates,
    habitFields,
    habitEvents,
    // Dreams: categories and field defs before the dreams that use them, the
    // dreams before their metrics and steps (docs/dreams.md → Sync).
    dreamCategories,
    dreamFields,
    dreams,
    dreamMetrics,
    dreamSteps,
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

  /// Reminders + calendar ("Pengingat", "Kalender").
  static const agendaModule = [reminders, calendarEvents];

  /// People ("Orang", `docs/people.md`).
  static const peopleModule = [
    personCategories,
    personFields,
    people,
    personDates,
  ];

  /// Habit enrichment (`docs/habits-food-enrichment.md`): a pull carrying
  /// [habitFields] comes from an enrichment-aware server.
  static const enrichmentModule = [habitFields, habitEvents];

  /// Dreams ("Mimpi", `docs/dreams.md`).
  static const dreamsModule = [
    dreamCategories,
    dreamFields,
    dreams,
    dreamMetrics,
    dreamSteps,
  ];
}
