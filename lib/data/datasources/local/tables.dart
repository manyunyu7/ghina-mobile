import 'package:drift/drift.dart';

/// Stores `DateTime` as integer milliseconds since epoch; reads back as local time.
class EpochMsConverter extends TypeConverter<DateTime, int> {
  const EpochMsConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

const epochMs = EpochMsConverter();

mixin Timestamps on Table {
  IntColumn get createdAt => integer().map(epochMs)();
  IntColumn get updatedAt => integer().map(epochMs)();
}

@DataClassName('WalletRow')
class Wallets extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('cash'))();

  /// Last server balance (or the initial balance until the wallet is pushed).
  RealColumn get balance => real().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  TextColumn get icon => text().withDefault(const Constant('wallet'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  TextColumn get icon => text().withDefault(const Constant('circle'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TransactionRow')
@TableIndex(name: 'idx_tx_date', columns: {#date})
@TableIndex(name: 'idx_tx_wallet', columns: {#walletId})
@TableIndex(name: 'idx_tx_to_wallet', columns: {#toWalletId})
@TableIndex(name: 'idx_tx_category', columns: {#categoryId})
class Transactions extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get walletId => text()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  IntColumn get date => integer().map(epochMs)();

  // --- schema v3 (`docs/transaction-photos.md`) ---

  /// JSON array of strings, display order: uploaded paths (`/uploads/x.jpg`) and
  /// photos waiting for upload as `local:<absolute file path>` (device-only marker,
  /// never sent on the wire). v2 rows migrate to `[]`.
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetRow')
@TableIndex(name: 'idx_budget_period', columns: {#year, #month})
class Budgets extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  RealColumn get amount => real()();
  IntColumn get month => integer()();
  IntColumn get year => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {categoryId, month, year},
  ];
}

@DataClassName('SubscriptionRow')
class Subscriptions extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get cycle => text().withDefault(const Constant('monthly'))();
  IntColumn get nextBilling => integer().map(epochMs)();
  TextColumn get categoryId => text().nullable()();
  TextColumn get walletId => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  TextColumn get icon => text().withDefault(const Constant('credit-card'))();
  TextColumn get note => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlannedRow')
@TableIndex(name: 'idx_planned_date', columns: {#date})
class Planned extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get walletId => text().nullable()();
  IntColumn get date => integer().map(epochMs)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PrayerRow')
class Prayers extends Table with Timestamps {
  TextColumn get id => text()();

  /// `YYYY-MM-DD`
  TextColumn get date => text()();

  /// Fardhu `subuh|dzuhur|ashar|maghrib|isya`, sunnah `dhuha|tahajud|witir`.
  TextColumn get prayer => text()();

  // --- schema v2 (prayer quality, `docs/prayer-quality.md`) ---

  /// Fardhu: `masjid|jamaah|ontime|late|qadha|missed|excused`; sunnah: `done`.
  /// v1 rows (performed) migrate to `ontime`.
  TextColumn get status => text().withDefault(const Constant('ontime'))();
  BoolColumn get qobliyah => boolean().withDefault(const Constant(false))();
  BoolColumn get badiyah => boolean().withDefault(const Constant(false))();

  /// Sunnah only.
  IntColumn get rakaat => integer().nullable()();
  IntColumn get prayedAt => integer().map(epochMs).nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {date, prayer},
  ];
}

@DataClassName('HealthRow')
@TableIndex(name: 'idx_health_date', columns: {#date})
class Health extends Table with Timestamps {
  TextColumn get id => text()();
  IntColumn get date => integer().map(epochMs)();
  RealColumn get weight => real().nullable()();
  IntColumn get systolic => integer().nullable()();
  IntColumn get diastolic => integer().nullable()();
  IntColumn get pulse => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FoodRow')
@TableIndex(name: 'idx_food_date', columns: {#date})
@TableIndex(name: 'idx_food_tx', columns: {#transactionId})
class Food extends Table with Timestamps {
  TextColumn get id => text()();
  IntColumn get date => integer().map(epochMs)();
  TextColumn get name => text()();
  TextColumn get meal => text().nullable()();
  IntColumn get calories => integer().nullable()();

  /// v8: upper bound of a calorie range (null = not a range).
  IntColumn get caloriesMax => integer().nullable()();

  /// v8: JSON array of tags (≤ 10).
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  TextColumn get photoUrl => text().nullable()();

  /// Device-only: photo waiting to be uploaded. Never sent on the wire.
  TextColumn get localPhotoPath => text().nullable()();
  TextColumn get note => text().nullable()();

  /// v10: the expense this meal was paid with (`docs/food-transaction-link.md`).
  /// Many food rows may share one transaction; deleting it nulls this.
  TextColumn get transactionId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v3: tasks (`docs/tasks.md`) ---

@DataClassName('TaskAreaRow')
class TaskAreas extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 1–8 chars `A–Z0–9`, unique per user.
  TextColumn get code => text()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();
  TextColumn get icon => text().withDefault(const Constant('briefcase'))();

  /// JSON `{"days":[1..7],"start":"HH:mm","end":"HH:mm"}`; null = anytime.
  TextColumn get schedule => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TaskRow')
@TableIndex(name: 'idx_task_area', columns: {#areaId})
@TableIndex(name: 'idx_task_due', columns: {#dueDate})
class Tasks extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get areaId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();

  /// `fire | want | should`
  TextColumn get bucket => text().withDefault(const Constant('want'))();

  /// Local date `YYYY-MM-DD`.
  TextColumn get dueDate => text().nullable()();

  /// Local `HH:mm`, only with [dueDate].
  TextColumn get dueTime => text().nullable()();
  IntColumn get remindBefore => integer().nullable()();

  /// JSON `{"freq","interval","weekdays"?,"monthDay"?}`; null = one-off.
  TextColumn get recurrence => text().nullable()();
  TextColumn get seriesId => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get doneAt => integer().map(epochMs).nullable()();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();
  RealColumn get amount => real().nullable()();
  TextColumn get walletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get transactionId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v4: notes (`docs/notes.md`) and content planner (`docs/content.md`) ---
//
// JSON fields are stored as JSON text. Photo/audio lists may hold device-only
// markers for files waiting for upload (`local:<path>` photos, `{"local": path}`
// clips) — never sent on the wire.

@DataClassName('NoteRow')
@TableIndex(name: 'idx_note_updated', columns: {#updatedAt})
class Notes extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// JSON `[{id, text, done}]`.
  TextColumn get checklist => text().withDefault(const Constant('[]'))();

  /// JSON array of label ids.
  TextColumn get labels => text().withDefault(const Constant('[]'))();
  TextColumn get color => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// JSON array: `/uploads/…` paths and `local:<path>` markers.
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  /// JSON `[{url, durationSec, transcript?}]`; pending clips `{local, …}`.
  TextColumn get audio => text().withDefault(const Constant('[]'))();

  /// JSON `[{url, title?}]`.
  TextColumn get links => text().withDefault(const Constant('[]'))();

  /// `share | quick | voice`
  TextColumn get source => text().nullable()();
  TextColumn get linkedTaskId => text().nullable()();
  TextColumn get linkedContentId => text().nullable()();
  TextColumn get linkedTransactionId => text().nullable()();

  /// Device-only: lowercased title + body + checklist + transcripts (search).
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NoteLabelRow')
class NoteLabels extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();
  BoolColumn get pinnedTab => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SocialAccountRow')
class SocialAccounts extends Table with Timestamps {
  TextColumn get id => text()();

  /// `instagram | tiktok | youtube | x | threads | linkedin | facebook | other`
  TextColumn get platform => text()();
  TextColumn get platformName => text().nullable()();
  TextColumn get handle => text()();
  TextColumn get color => text()();
  IntColumn get targetPerWeek => integer().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContentItemRow')
class ContentItems extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text()();

  /// `ide | naskah | produksi | siap | terjadwal | tayang`
  TextColumn get stage => text().withDefault(const Constant('ide'))();
  TextColumn get format => text().nullable()();

  /// Pillar name.
  TextColumn get pillar => text().nullable()();
  TextColumn get idea => text().withDefault(const Constant(''))();
  TextColumn get noteId => text().nullable()();
  TextColumn get checklist => text().withDefault(const Constant('[]'))();
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  /// JSON `[{url, label}]`.
  TextColumn get assetLinks => text().withDefault(const Constant('[]'))();

  /// JSON `{brand, amount, currency, due?, paid, transactionId?}` or null.
  TextColumn get sponsor => text().nullable()();

  /// Device-only: JSON `{stage: epochMs}` — when this device first saw each
  /// stage reached (gamification, see `lib/domain/game/README.md`).
  TextColumn get stageLog => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContentPostRow')
@TableIndex(name: 'idx_post_content', columns: {#contentId})
@TableIndex(name: 'idx_post_account', columns: {#accountId})
@TableIndex(name: 'idx_post_scheduled', columns: {#scheduledAt})
class ContentPosts extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get contentId => text()();
  TextColumn get accountId => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();
  TextColumn get hashtags => text().withDefault(const Constant(''))();
  IntColumn get scheduledAt => integer().map(epochMs).nullable()();
  IntColumn get remindBefore => integer().nullable()();

  /// `draft | scheduled | posted | skipped`
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get postedAt => integer().map(epochMs).nullable()();
  TextColumn get url => text().nullable()();

  /// JSON `{views, likes, comments, shares, saves, followers}`.
  TextColumn get metrics => text().withDefault(const Constant('{}'))();
  IntColumn get metricsAt => integer().map(epochMs).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContentPillarRow')
class ContentPillars extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v5: habits (`docs/habits.md`) and investments (`docs/investments.md`) ---

@DataClassName('HabitRow')
class Habits extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get emoji => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();

  /// `build | quit`
  TextColumn get kind => text().withDefault(const Constant('build'))();

  /// JSON `{"type":"daily"}` | `{"type":"weekdays","days":[…]}` |
  /// `{"type":"perWeek","times":n}`.
  TextColumn get schedule =>
      text().withDefault(const Constant('{"type":"daily"}'))();

  /// JSON `{"type":"check"}` | `{"type":"count","goal":n,"unit":…}` |
  /// `{"type":"duration","goal":minutes}`.
  TextColumn get target =>
      text().withDefault(const Constant('{"type":"check"}'))();

  /// JSON array of local `HH:mm`.
  TextColumn get reminders => text().withDefault(const Constant('[]'))();

  /// Wire `private`.
  BoolColumn get isPrivate => boolean().withDefault(const Constant(false))();
  TextColumn get why => text().nullable()();

  /// `YYYY-MM-DD`.
  TextColumn get startDate => text()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// v8: JSON array of `{title, detail, kind}` (coping playbook).
  TextColumn get tools => text().withDefault(const Constant('[]'))();

  /// v8: read-only server mirrors of the markdown notes (never pushed).
  BoolColumn get hasNotes => boolean().withDefault(const Constant(false))();
  IntColumn get notesLength => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HabitLogRow')
@TableIndex(name: 'idx_habit_log_habit', columns: {#habitId, #date})
@TableIndex(name: 'idx_habit_log_date', columns: {#date})
class HabitLogs extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get habitId => text()();

  /// Local `YYYY-MM-DD`.
  TextColumn get date => text()();

  /// `done | skip | relapse | urge`
  TextColumn get type => text()();
  RealColumn get value => real().nullable()();
  TextColumn get note => text().nullable()();

  /// JSON array of trigger tags.
  TextColumn get triggers => text().withDefault(const Constant('[]'))();
  IntColumn get at => integer().map(epochMs).nullable()();

  /// v8: JSON object of user-defined dimensions (key → string|number|bool).
  TextColumn get extra => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, date, type},
  ];
}

@DataClassName('AssetRow')
@TableIndex(name: 'idx_asset_symbol', columns: {#kind, #symbol})
class Assets extends Table with Timestamps {
  TextColumn get id => text()();

  /// `stock | fund | gold | crypto | bond | other`
  TextColumn get kind => text()();
  TextColumn get symbol => text()();
  TextColumn get name => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();

  /// `auto | manual`
  TextColumn get priceMode => text().withDefault(const Constant('auto'))();
  RealColumn get manualPrice => real().nullable()();
  IntColumn get manualPriceAt => integer().map(epochMs).nullable()();
  TextColumn get unit => text().withDefault(const Constant('lembar'))();
  TextColumn get walletId => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AssetTradeRow')
@TableIndex(name: 'idx_trade_asset', columns: {#assetId})
@TableIndex(name: 'idx_trade_cash_tx', columns: {#cashTransactionId})
class AssetTrades extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get assetId => text()();

  /// `buy | sell | dividend | split | fee`
  TextColumn get type => text()();
  IntColumn get date => integer().map(epochMs)();
  RealColumn get quantity => real().nullable()();
  RealColumn get price => real().nullable()();
  RealColumn get fee => real().withDefault(const Constant(0))();
  RealColumn get amount => real().nullable()();
  RealColumn get ratio => real().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get cashTransactionId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `reminders` ("Pengingat", docs/mobile-sync.md → "Reminders").
/// The table class isn't called `Reminders`: `Reminder` is the local
/// notification entity.
@DataClassName('ReminderRow')
@TableIndex(name: 'idx_reminder_due', columns: {#dueAt})
class ReminderItems extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get dueAt => integer().map(epochMs)();

  /// `daily | weekly | monthly | yearly`, null = one-off.
  TextColumn get recurrence => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get doneAt => integer().map(epochMs).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `calendarEvents` ("Kalender", docs/mobile-sync.md → "Calendar events").
///
/// `startAt`/`endAt` hold the wire instant as epoch ms. For all-day events
/// that is UTC midnight of the date: read the date back in UTC, never in the
/// device zone (see `agenda_mappers.dart`).
@DataClassName('CalendarEventRow')
@TableIndex(name: 'idx_event_start', columns: {#startAt})
class CalendarEvents extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get startAt => integer()();
  IntColumn get endAt => integer().nullable()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get color => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v8: people (`docs/people.md`) and habit enrichment ---

/// Synced `people`. No notes column: the markdown notes are online-only.
@DataClassName('PersonRow')
@TableIndex(name: 'idx_person_category', columns: {#category})
class People extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get fullName => text().nullable()();

  /// A `person_categories.key`.
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get relation => text().nullable()();
  TextColumn get vibe => text().withDefault(const Constant('unknown'))();
  TextColumn get status => text().nullable()();
  TextColumn get howMet => text().nullable()();
  TextColumn get summary => text().nullable()();
  IntColumn get birthYear => integer().nullable()();
  IntColumn get birthMonth => integer().nullable()();
  IntColumn get birthDay => integer().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get instagram => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get organization => text().nullable()();
  TextColumn get dataStatus => text().withDefault(const Constant('sparse'))();
  BoolColumn get sensitive => boolean().withDefault(const Constant(false))();

  /// JSON array of strings.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// JSON object: custom-field key → string|number|bool.
  TextColumn get fields => text().withDefault(const Constant('{}'))();

  /// Read-only server mirrors of the notes (never pushed).
  BoolColumn get hasNotes => boolean().withDefault(const Constant(false))();
  IntColumn get notesLength => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PersonCategoryRow')
class PersonCategories extends Table with Timestamps {
  TextColumn get id => text()();

  /// Immutable slug; unique per user (the server answers `duplicate`).
  TextColumn get key => text()();
  TextColumn get label => text()();
  TextColumn get emoji => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `personFields` (custom-field definitions).
@DataClassName('PersonFieldRow')
class PersonFields extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get key => text()();
  TextColumn get label => text()();
  TextColumn get type => text().withDefault(const Constant('text'))();

  /// JSON array (select) or null.
  TextColumn get options => text().nullable()();

  /// JSON array of category keys, null = all.
  TextColumn get appliesTo => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get showInList => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PersonDateRow')
@TableIndex(name: 'idx_person_date_person', columns: {#personId})
class PersonDates extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get personId => text()();
  TextColumn get label => text()();

  /// `anniversary | memorial | custom`
  TextColumn get kind => text().withDefault(const Constant('custom'))();
  IntColumn get month => integer()();
  IntColumn get day => integer()();
  IntColumn get year => integer().nullable()();
  IntColumn get remindDaysBefore => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `habitFields` (per-event dimensions).
@DataClassName('HabitFieldRow')
class HabitFields extends Table with Timestamps {
  TextColumn get id => text()();

  /// null = every habit.
  TextColumn get habitId => text().nullable()();
  TextColumn get key => text()();
  TextColumn get label => text()();
  TextColumn get type => text().withDefault(const Constant('text'))();
  TextColumn get options => text().nullable()();
  IntColumn get scaleMin => integer().nullable()();
  IntColumn get scaleMax => integer().nullable()();
  TextColumn get appliesTo => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `habitEvents` (journal days, milestones, neutral events).
@DataClassName('HabitEventRow')
@TableIndex(name: 'idx_habit_event_habit', columns: {#habitId, #date})
class HabitEvents extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get habitId => text()();

  /// Local `YYYY-MM-DD`.
  TextColumn get date => text()();

  /// `journal | milestone | event`
  TextColumn get kind => text()();
  TextColumn get label => text()();
  TextColumn get note => text().nullable()();
  IntColumn get at => integer().map(epochMs).nullable()();
  TextColumn get extra => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v9: dreams / "Mimpi" (`docs/dreams.md`) ---

/// Synced `dreams`. Computed values (progress, metric current values, on-track,
/// stale/overdue) never travel and have no column.
@DataClassName('DreamRow')
@TableIndex(name: 'idx_dream_category', columns: {#category})
class Dreams extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get emoji => text().nullable()();

  /// A `dream_categories.key` (default `other`).
  TextColumn get category => text().withDefault(const Constant('other'))();

  /// `idea | planned | active | waiting | done | paused | dropped | watching`
  TextColumn get status => text().withDefault(const Constant('idea'))();

  /// 1 (highest) … 5, nullable.
  IntColumn get priority => integer().nullable()();

  /// `someday | this_year | next_year | multi_year | ongoing`, nullable.
  TextColumn get horizon => text().nullable()();

  /// `YYYY-MM-DD`, always the last day of the `targetPrecision` period.
  TextColumn get targetDate => text().nullable()();

  /// `day | month | quarter | year`
  TextColumn get targetPrecision => text().withDefault(const Constant('day'))();
  TextColumn get condition => text().nullable()();
  TextColumn get why => text().nullable()();
  TextColumn get summary => text().nullable()();

  /// Rupiah estimate, nullable.
  RealColumn get costEstimate => real().nullable()();
  TextColumn get costNote => text().nullable()();

  /// 0–100, nullable (overrides the computed progress).
  IntColumn get progressManual => integer().nullable()();

  /// `YYYY-MM-DD`, nullable.
  TextColumn get startedAt => text().nullable()();

  /// `YYYY-MM-DD`, nullable.
  TextColumn get completedAt => text().nullable()();

  /// A note of the user, nullable (the note's delete nulls it).
  TextColumn get noteId => text().nullable()();

  /// A parent dream of the user, nullable.
  TextColumn get parentId => text().nullable()();

  /// JSON array of strings.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// JSON object: custom-field key → string|number|bool.
  TextColumn get fields => text().withDefault(const Constant('{}'))();

  /// JSON object `{"taskIds": [...], "habitIds": [...]}` (soft links).
  TextColumn get links => text().withDefault(const Constant('{}'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `dreamSteps` (child of a dream, deleted with it).
@DataClassName('DreamStepRow')
@TableIndex(name: 'idx_dream_step_dream', columns: {#dreamId})
class DreamSteps extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get dreamId => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// Stamped when done (epoch ms), nullable.
  IntColumn get doneAt => integer().map(epochMs).nullable()();

  /// `YYYY-MM-DD`, nullable.
  TextColumn get dueDate => text().nullable()();

  /// Rupiah, nullable.
  RealColumn get cost => real().nullable()();

  /// "Hadiah" unlocked when the step is done, nullable.
  TextColumn get reward => text().nullable()();

  /// A `dream_metrics.id` of the same dream, nullable. Stored as pushed.
  TextColumn get metricRef => text().nullable()();

  /// Threshold of [metricRef] (both or neither is set), nullable.
  RealColumn get atValue => real().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `dreamMetrics` (child of a dream, deleted with it). Computed current
/// values are never stored here.
@DataClassName('DreamMetricRow')
@TableIndex(name: 'idx_dream_metric_dream', columns: {#dreamId})
class DreamMetrics extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get dreamId => text()();
  TextColumn get label => text()();

  /// `weight | pulse | systolic | diastolic | habit_clean_days |
  /// habit_current_streak | habit_longest_streak | wallet_balance |
  /// net_worth | spend_category | manual`
  TextColumn get source => text()();

  /// JSON object (`habitId` / `walletId` / `categoryId`+`period`), nullable.
  TextColumn get sourceRef => text().nullable()();

  /// `down | up`, nullable (the server derives it when omitted).
  TextColumn get direction => text().nullable()();
  TextColumn get unit => text().nullable()();
  RealColumn get startValue => real().nullable()();

  /// `YYYY-MM-DD`, nullable.
  TextColumn get startDate => text().nullable()();
  RealColumn get targetValue => real()();

  /// `YYYY-MM-DD`, nullable.
  TextColumn get targetDate => text().nullable()();
  RealColumn get manualValue => real().nullable()();

  /// Epoch ms of [manualValue], nullable.
  IntColumn get manualAt => integer().map(epochMs).nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `dreamCategories`. The 12 built-ins are seeded by the server.
@DataClassName('DreamCategoryRow')
class DreamCategories extends Table with Timestamps {
  TextColumn get id => text()();

  /// Immutable slug; unique per user (the server answers `duplicate`).
  TextColumn get key => text()();
  TextColumn get label => text()();
  TextColumn get emoji => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Synced `dreamFields` (custom-column definitions).
@DataClassName('DreamFieldRow')
class DreamFields extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get key => text()();
  TextColumn get label => text()();
  TextColumn get type => text().withDefault(const Constant('text'))();

  /// JSON array (select) or null.
  TextColumn get options => text().nullable()();

  /// JSON array of dream category keys, null = all.
  TextColumn get appliesTo => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get showInList => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Device-only cache of `GET /api/mobile/prices` (not synced, not user data).
@DataClassName('CachedPriceRow')
class CachedPrices extends Table {
  /// `stock:BBCA`
  TextColumn get key => text()();
  TextColumn get kind => text()();
  TextColumn get symbol => text()();
  RealColumn get price => real()();
  RealColumn get prevClose => real().nullable()();
  RealColumn get change => real().nullable()();
  RealColumn get changePct => real().nullable()();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get name => text().nullable()();
  IntColumn get asOf => integer().map(epochMs).nullable()();
  TextColumn get source => text().nullable()();
  IntColumn get fetchedAt => integer().map(epochMs).nullable()();

  /// The server marked it stale (kept its last price).
  BoolColumn get stale => boolean().withDefault(const Constant(false))();

  /// When this device received it.
  IntColumn get cachedAt => integer().map(epochMs)();

  @override
  Set<Column> get primaryKey => {key};
}

/// Device-only daily portfolio value history (one row per local day).
@DataClassName('PortfolioSnapshotRow')
class PortfolioSnapshots extends Table {
  /// `YYYY-MM-DD`
  TextColumn get date => text()();
  RealColumn get value => real()();
  RealColumn get cost => real()();
  IntColumn get updatedAt => integer().map(epochMs)();

  @override
  Set<Column> get primaryKey => {date};
}

/// Device-only log of other apps' notifications ("Log Notifikasi"), written by
/// the Android notification listener (possibly from its background isolate).
@DataClassName('CapturedNotificationRow')
@TableIndex(name: 'idx_notif_posted', columns: {#postedAt})
@TableIndex(name: 'idx_notif_package', columns: {#packageName})
@TableIndex(name: 'idx_notif_processed', columns: {#processed})
class CapturedNotifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get packageName => text()();

  /// Launcher label; null until the UI isolate resolves it.
  TextColumn get appName => text().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// `StatusBarNotification.key` (diagnostics only).
  TextColumn get notificationKey => text().nullable()();
  IntColumn get postedAt => integer().map(epochMs)();
  IntColumn get capturedAt => integer().map(epochMs)();

  /// Checked against the parsing rules.
  BoolColumn get processed => boolean().withDefault(const Constant(false))();
  TextColumn get ruleId => text().nullable()();
  TextColumn get transactionId => text().nullable()();

  /// `income` | `expense` of the matching rule.
  TextColumn get txType => text().nullable()();
  RealColumn get amount => real().nullable()();
  TextColumn get parseError => text().nullable()();
}

/// Device-only notification parsing rules (notification → transaction).
@DataClassName('NotificationRuleRow')
class NotificationRules extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// JSON array of package names.
  TextColumn get packages => text()();

  /// `any` | `title` | `body`
  TextColumn get matchField => text().withDefault(const Constant('any'))();
  TextColumn get pattern => text()();
  BoolColumn get isRegex => boolean().withDefault(const Constant(false))();

  /// `income` | `expense`
  TextColumn get type => text()();
  TextColumn get amountPattern => text().nullable()();
  TextColumn get walletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get presetKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending local mutations, pushed in [seq] order.
@DataClassName('OutboxRow')
@TableIndex(name: 'idx_outbox_entity', columns: {#entity, #entityId})
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// Mutation id sent to the server (UUID v4).
  TextColumn get mutationId => text().unique()();

  /// Wire entity name (`transactions`, …).
  TextColumn get entity => text()();

  /// `upsert` | `delete`
  TextColumn get op => text()();
  TextColumn get entityId => text()();

  /// JSON of the upsert `data` (null for deletes).
  TextColumn get data => text().nullable()();

  /// Transactions only: JSON of the row as the server currently has it (null if the
  /// server doesn't have it). Pending balance effect = effect(data) − effect(base).
  TextColumn get base => text().nullable()();

  /// True when the entity did not exist on the server when this was queued.
  BoolColumn get isCreate => boolean().withDefault(const Constant(false))();

  /// True while part of a push request that hasn't been answered yet.
  BoolColumn get inFlight => boolean().withDefault(const Constant(false))();

  /// Milliseconds since epoch.
  IntColumn get clientUpdatedAt => integer()();
}

/// Single-row sync bookkeeping (id = 1).
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();

  /// Next pull cursor (server ms). 0 = full pull.
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  TextColumn get epoch => text().nullable()();

  /// Owner of the local data (wiped when a different user signs in).
  TextColumn get userId => text().nullable()();
  IntColumn get lastSyncAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  /// Set after a rejected/skipped mutation so the next pull re-downloads everything.
  BoolColumn get fullPullRequired =>
      boolean().withDefault(const Constant(false))();

  /// v3: the default task areas were checked/seeded after the first pull from a
  /// server that knows tasks (`docs/tasks.md`), so they're never re-created.
  BoolColumn get tasksSeeded => boolean().withDefault(const Constant(false))();

  /// v4: a pull from a notes-aware server succeeded — the server owns seeding
  /// the default "Ide Konten" label from then on; the app never seeds it again.
  BoolColumn get notesSeeded => boolean().withDefault(const Constant(false))();

  /// v4: a pull from a content-aware server succeeded — the server owns seeding
  /// the default pillars from then on; the app never seeds them again.
  BoolColumn get contentSeeded =>
      boolean().withDefault(const Constant(false))();

  /// v8: a pull from an enrichment-aware server succeeded (it sent
  /// `habitFields`). Until then rows may still carry v7 defaults for
  /// `habits.tools`, `habitLogs.extra`, `food.tags/caloriesMax`, so pushes
  /// leave those keys out ("absent = unchanged") rather than wipe the server's.
  BoolColumn get enrichmentSeen =>
      boolean().withDefault(const Constant(false))();

  /// v10: a pull delivered a food row carrying `transactionId` (the server
  /// knows food ⇄ transaction links). Until then a `null` link is left out of
  /// pushes ("absent = unchanged") so it can't wipe a link made on the web.
  BoolColumn get foodLinksSeen =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
