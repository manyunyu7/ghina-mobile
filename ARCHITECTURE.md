# Ghina mobile — architecture

Flutter companion app for the Ghina web app (`../`). Offline-first, syncs with the
server per `../docs/mobile-sync.md`. Duolingo-style: bright, chunky, playful, rewarding.

## Stack

- State: `flutter_riverpod` 3 — plain providers, **no codegen** (no riverpod_generator).
- Local DB: `drift` + `drift_flutter` (codegen via `build_runner`, the only codegen we use).
- Network: `dio`. Token in `flutter_secure_storage`. Connectivity via `connectivity_plus`.
- Routing: `go_router`. Charts: `fl_chart`. Celebrations: `confetti`.
- Font: Nunito (variable, bundled at `assets/fonts/Nunito.ttf`).
- Run codegen: `dart run build_runner build --delete-conflicting-outputs`

## Language & tone

All UI copy is **Bahasa Indonesia**, casual and warm like Duolingo ("Mantap! 🔥 Streak
kamu 5 hari!"). Money is IDR by default, formatted `Rp 25.000` (use the user's currency).

## Clean Architecture (layer-first)

Dependency rule: **presentation → domain ← data**. `domain` is pure Dart: no Flutter,
no drift, no dio, no Riverpod, no shared_preferences imports. `presentation` never imports
`data` — it only knows domain entities and use cases. The only place that knows both is
the composition root `lib/di/`.

Layer-first (not feature-first) because entities are shared across features (a wallet is
used by transactions, budgets, subscriptions, forecast) and sync is cross-cutting.

```
lib/
  main.dart                    entry: ProviderScope + app
  app/                         app.dart (MaterialApp.router), router.dart (routes below)
  core/                        pure utilities usable by every layer: Failure types,
                               Result<T>, clock, id generation, money/date formatting
  domain/
    entities/                  immutable entities (Wallet, Transaction, Budget, …) + value
                               objects (Money, TxType, BillingCycle, …)
    repositories/              abstract repository interfaces
    usecases/                  one class per business operation, `call()` method
                               (CreateTransaction, TransferBetweenWallets,
                               PaySubscription, ComputeForecast, WatchDashboard, …)
    game/                      gamification engine: XP, streak, levels, hearts,
                               achievements, lesson engine, lesson content, GameStore
                               interface — all pure functions/classes
  data/
    datasources/local/         drift database, tables, DAOs
    datasources/remote/        dio client, auth API, sync API
    models/                    DTOs + mappers (DTO ⇄ drift row ⇄ domain entity)
    repositories/              implementations of domain/repositories
    sync/                      outbox + sync engine
    game/                      GameStore implementation (shared_preferences)
  di/                          composition root: Riverpod providers that bind
                               implementations to interfaces and build use cases
  presentation/
    design_system/             theme, tokens, typography, widgets, mascot, gallery
    state/                     app-wide Riverpod state/controllers (session, sync status,
                               game summary) built on use cases
    shared/                    cross-feature presentation code: rewards/ (XP toast +
                               celebrations, shown once), game_visuals.dart (mood/tier/icon
                               mapping), widgets/ (async states, month switcher, form
                               fields, date picker, pickers). See shared/README.md
    features/<feature>/        pages/, widgets/, controllers/ for one feature
test/                          mirrors lib/ (test/domain, test/data, test/presentation)
```

Errors: repositories/use cases throw or return typed `Failure`s from `core/`
(sealed class: network, unauthorized, validation, notFound, conflict, unknown). The
presentation layer maps failures to friendly Indonesian messages.

## Folder ownership during the build

| Owner | Folders |
|---|---|
| Data & sync agent | `core/`, `domain/entities`, `domain/repositories`, `domain/usecases`, `data/` (except `data/game`), `di/`, `presentation/state/` session + sync status |
| Design system agent | `presentation/design_system/` |
| Gamification agent | `domain/game/`, `data/game/`, `presentation/state/game/` |
| Screen agents (later) | `app/`, `presentation/features/**` |

## Screens & routes

Bottom navigation (StatefulShellRoute), 4 tabs + a big center "+" button that opens the
quick-add transaction sheet:

| Tab | Path | Screen |
|---|---|---|
| Beranda | `/home` | streak, daily goal ring, total balance, today's spending vs budget, hearts, mascot message, quick actions, recent transactions |
| Transaksi | `/transactions` | list grouped by date, filters, search |
| Belajar | `/learn` | Duolingo-style lesson path (financial literacy) |
| Profil | `/profile` | level, XP, streak calendar, achievements, links to everything else, settings |

Side drawer "Semua menu" (`features/shell/app_drawer.dart`, items in `app_menu.dart`):
every screen grouped Uang · Hidup · Produktif · Lainnya, with search (label + synonyms),
current-tab highlight, badges and a footer (sync, "Sembunyikan saldo", version). Opened
by the ☰ on each tab (`AppDrawerButton`) or an edge swipe. Tabs open with `go`, the rest
with `push`. Beranda's grid shows the 8 most-used screens + a "Semua menu" tile.

Launcher shortcuts (long-press the icon; `quick_actions`, `AppShortcuts` port in
`domain/services`): Catat pengeluaran, Catatan baru, Tugas baru, Lagi pengen… — routed by
`AppShortcutListener` through the reminder-tap pending-route gate (waits for login).

Pushed routes (full screen, outside the shell):
`/login`, `/register`, `/onboarding`,
`/transactions/new`, `/transactions/:id`,
`/wallets`, `/wallets/new`, `/wallets/:id`,
`/categories`, `/categories/new`, `/categories/:id`,
`/budgets`, `/budgets/new`, `/budgets/:id`,
`/subscriptions`, `/subscriptions/new`, `/subscriptions/:id`,
`/forecast`, `/forecast/new`, `/forecast/:id`,
`/reports`,
`/prayers`, `/prayers/report`, `/prayers/reminders` (Reminder Sholat, see `lib/data/notifications/README.md`), `/wallets/:id/history`, `/health`, `/health/new`, `/health/:id`, `/food`, `/food/new`, `/food/:id`,
`/achievements`, `/learn/lesson/:lessonId`, `/settings`, `/sync`,
`/notification-log`, `/notification-log/rules`, `/notification-log/rules/new`, `/notification-log/rules/:id`
("Log Notifikasi", Android only — see `lib/data/platform/notification_listener_bridge.dart`),
`/reminders`, `/reminders/new`, `/reminders/:id` ("Pengingat", synced `reminders`; a local
notification at each `dueAt` via `WatchReminders`), `/calendar`, `/calendar/new?date=`,
`/calendar/:id` ("Kalender", synced `calendarEvents`; all-day dates are read from the ISO date
part, never converted to local time),
`/people`, `/people/new`, `/people/manage`, `/people/:id`, `/people/:id/edit` ("Orang", synced
`people` / `personCategories` / `personFields` / `personDates`, `../docs/people.md`; the markdown
**notes are online-only**, fetched with `GET /api/mobile/people/{id}` and never stored; birthdays
and important dates notify at 09:00 through the existing scheduler and show read-only on `/calendar`),
`/dreams`, `/dreams/new`, `/dreams/manage`, `/dreams/review`, `/dreams/:id`, `/dreams/:id/edit` ("Mimpi", synced `dreams` and children, `../docs/dreams.md`; the list, detail and form work offline, the computed metric values are online-only; see "Dreams screens (phase C2)" below)
`/habits/:id/insights` ("Analisis", server-computed, online-only), `/habits/fields?habit=` ("Dimensi"),
`/killa`, `/killa/files?path=`, `/killa/file?path=`, `/killa/commits`, `/killa/reminders`,
`/killa/usage` (Killa, `../docs/killa.md` — **online-only**, not in sync: `KillaApi` in
`data/datasources/remote/`, errors are `KillaException`s; a 403 locks the screens and hides the
drawer entry via `presentation/state/killa_access_provider.dart`).

## Feature parity with the web

Everything the web has: wallets (incl. transfers), transactions, categories (with default
set), monthly budgets, subscriptions (quick pay = create expense + advance next billing),
forecast (planned items + subscriptions + history projection — port
`../src/app/(dashboard)/forecast/logic.ts`), reports, prayers (5 daily, calendar),
health (weight / blood pressure), food log (photo, meal, calories), settings (currency,
sign out, reset local data).

## Gamification (local, derived from data — no server changes)

- XP from real activity: transaction logged, prayer, health entry, food log, lesson done,
  daily goal met, streak milestones.
- Streak: consecutive local days with at least one logged transaction (by `createdAt`).
  Streak freezes earned at milestones.
- Levels from total XP. Achievements/badges. Hearts = budget health for the month.
- Learning path: units of short Indonesian personal-finance lessons with quizzes.
- Progress that can't be derived from synced data (lesson progress, freezes, daily goal
  setting) is stored locally.

## Rules for contributors (humans and agents)

- Stay inside the folders you own; import others' public APIs, don't edit their files.
- Respect the dependency rule; `domain/` must compile without Flutter.
- `flutter analyze` must be clean for your files; add tests for logic.
- No network calls outside `data/datasources/remote/`. Screens use use cases (via `di/` providers) and `presentation/state/` only — never repositories or drift directly.

## People & habit enrichment (schema v8)

Drift v8 adds `people`, `person_categories`, `person_fields` (definitions), `person_dates`,
`habit_fields`, `habit_events` and the columns `habits.tools / has_notes / notes_length`,
`habit_logs.extra`, `food.calories_max / tags`, `sync_meta.enrichment_seen`. The v7 → v8 upgrade
forces one full re-pull (like v7) so rows the old app skipped are downloaded. Pieces, in the usual
layers: `domain/entities/people.dart` + `habit_enrichment.dart`; the Dart port of `src/lib/people.ts`
in `domain/usecases/people_rules.dart` (birthday / next occurrence incl. Feb 29 → Feb 28, partial
birthdays, validation, custom-field typing, search, notification schedule); `people_usecases.dart`;
`data/models/people_wire.dart`, `data/repositories/people_repositories.dart`,
`data/sync/people_sync.dart` (+ cascades in `local_cascades.dart`); `di/people_providers.dart`;
screens in `presentation/features/people/`.

- Push order is enforced by **ranks** in `Outbox.takeBatch`, not by queue order (re-saving an entry
  moves it to the end of the queue): personCategories → personFields → people → personDates, and
  habits → habitFields → habitLogs / habitEvents. Deletes of the new entities go last.
- Enrichment keys on existing rows (`tools`, `extra`, `caloriesMax`, `tags`) are left out of pushes
  until a pull from an enrichment-aware server (one that sends `habitFields`) set
  `sync_meta.enrichment_seen`, so an upgraded device that edits before its first re-pull can't wipe
  the server's values ("absent = unchanged").
- `FoodLog.meal` is the canonical `MealType?`; any other meal text (≤ 24) is `FoodLog.mealLabel`
  and survives round trips.
- Notes writes (`ReplacePersonNotes` / `AppendPersonNotes`) re-stamp a queued edit of the same
  person so the server's moved `updatedAt` can't make it lose last-write-wins.


## Habit & food screens (phase B)

Screens for the enrichment of schema v8 — no schema change. Offline-first through the synced repositories:
coping **tools** (editor on the habit screen + tappable suggestions grouped by kind on the urge screen,
next to the preset ideas), the **events** timeline (journal / milestone / event, never touches streaks),
user-defined **dimensions** (`habitFields`, manager at `/habits/fields`) and the `extra` values they
produce on relapses (sheet), urges (optional card on the emergency screen, merged into the urge row that
is logged on open) and events. **Online-only**, never stored: the habit **notes** (`HabitNotesSection`, a
`private` habit keeps them collapsed behind "Tampilkan catatan" and fetches only on tap, like sensitive
people; notes, tools and events never enter the masked digests/lists) and the server **analysis**
(`HabitOnlineRepository`, `/insights?days=&today=&tz=`; offline = a distinct message, not an error).

- A notes write moves the server habit's `updatedAt`, so `ReplaceHabitNotes` / `AppendHabitNotes` call
  `HabitRepository.refreshPending` (re-stamps a queued edit, e.g. tools) and sync.
- `extra` is validated locally exactly as the server does (`habit_enrichment_rules.dart`): only defs that
  apply to the habit **and** the log type / event kind; a dimension without `appliesTo` does not show on the
  one-tap check-in (list `done` to get a "Tambah detail" tile after it). A rejected row would be dropped by
  sync, so a bad value is refused before saving.
- `HabitFieldRepository.delete` strips the key from every log/event in the same transaction (the server does
  the same); the UI warns with the number of records first.
- Food: calories are a range (`700–900 kkal`, en dash, "kkal" like the rest of the app), daily totals show
  min–max with a midpoint, `meal` is a free label (canonical meals resolve to `MealType`), tags are chips
  (≤ 10 × 30) with a filter, and a weekly summary is computed locally with the same rounding as
  `GET /food/summary` (`food_rules.dart`).
- New routes sit behind `HabitLockGate` like every habit route; the analysis and notes are never shown on
  home, the board, reminders or search.

## Dreams / Mimpi (schema v9)

Drift v9 adds `dreams`, `dream_steps`, `dream_metrics`, `dream_categories`, `dream_fields`
(all synced, `../docs/dreams.md`). The v8 → v9 upgrade forces one full re-pull like v7 and v8.
Layers: `domain/entities/dreams.dart` (entities + enums; dates are `YYYY-MM-DD` strings),
`domain/usecases/dreams_rules.dart` (Dart port of `src/lib/dreams.ts`: flexible targets, limits,
metric math, costs, staleness, lists), `dreams_usecases.dart`, `domain/repositories/dreams_*.dart`;
`data/models/dreams_wire.dart` (sync rows) and `dreams_online_wire.dart` (computed values, parsed
defensively), `data/repositories/dreams_repositories.dart` (offline-first, through the outbox) and
`dreams_online_repository_impl.dart` (summary, detail, manual value: online only), `data/sync/dreams_sync.dart`
(pull, tombstones, key clashes), cascades in `local_cascades.dart`, `di/dreams_providers.dart`.

- Push order: the outbox ranks `dreamCategories` 5.1, `dreamFields` 5.2, `dreams` 5.5 (after `notes`
  at 5), `dreamMetrics` 5.6, `dreamSteps` 5.7; inside a batch a child dream follows its parent
  (`dreamParentDepths`). Ranks are fixed, so a re-saved entry keeps its place.
- Computed values (progress, metric readings, on-track, projections, summary) never enter the
  database. The app stamps `startedAt` / `completedAt` on its own writes (the server does the same on
  REST); it does **not** auto-complete steps: that happens on the server and arrives with the pull.
- A manual reading written offline is queued (`RecordDreamManualValue`); a reading older than the
  stored one is refused, because the row carries only the newest value.

## Dreams screens (phase C2)

Screens for the Mimpi data layer of schema v9, all under `presentation/features/dreams/`. Local
first: the list, the detail's stored values, the form, the review and the manage screen write through
the use cases. Only the computed values (metric readings, on-track, projected dates, the server
summary) come from `DreamOnlineRepository`, and they are shown only when the network answered.

- Pure logic, no Flutter, unit tested: `dream_list_logic.dart` (one `DreamRow` per dream with the local
  cost, checklist progress, staleness and review tag; filters, search, sorts, board columns, timeline
  groups, summary counts, the review queue), `dream_format.dart` (text helpers), and the metric /
  target helpers of the detail and form.
- The list (`dreams_page.dart`) has three views: board (`dream_views.dart`, eager columns so every
  status stays reachable), table (sortable) and timeline. The rows come from `dreamRowsProvider`
  (`dream_list_rows.dart`), which joins dreams, steps and metrics streams. Status changes use the card
  menu or long press. The filter sheet and status sheet are in `dream_sheets.dart`.
- Staleness is computed locally from the newest of the dream's, steps', metrics' and manual readings'
  timestamps (`dreamStaleDays` in the rules). The review tag `perlu-ditinjau` is the user's own
  convention (the web has no such tag); the review queue is open dreams that are stale or tagged.
- Use cases added in this phase (`domain/usecases/dreams_extra_usecases.dart`): `ReorderDreamCategories`,
  `ReorderDreamFields` (same shape as People's reorder), and `WatchDreamSteps` / `WatchDreamMetrics`
  (every dream's children as one live map, for the list). Providers in `di/dreams_providers.dart`.
- "Masih berlaku" in the review is an update with unchanged values, which stamps `updatedAt` like the
  web's `touchDream`, plus the removal of the review tag.
- The calendar shows read-only 🎯 markers for open dreams with a target date (`dream_calendar.dart`);
  no `CalendarEvent` rows are created.
- Tests: `test/presentation/features/dreams/` (widget tests share `dreams_test_rig.dart`), and
  `test/domain/dreams_extra_usecases_test.dart`. Test data is invented.
