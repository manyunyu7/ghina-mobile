// Parity with the server's pure habits module: every case of
// `scripts/test-habits.mjs` that applies to the app, same inputs and results.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/habit_rules.dart';

// 2026-09-21 is a Monday; "today" in most tests is Friday 2026-09-25.
const today = '2026-09-25';
final _t0 = DateTime(2026, 9, 1);
var _n = 0;

HabitLog _log(
  String date,
  HabitLogType type, [
  double? value,
  List<String> triggers = const [],
  DateTime? at,
  String? note,
]) => HabitLog(
  id: 'l${_n++}',
  habitId: 'h',
  date: date,
  type: type,
  value: value,
  triggers: triggers,
  at: at,
  note: note,
  createdAt: _t0,
  updatedAt: _t0,
);
HabitLog done(String d, [double v = 1]) => _log(d, HabitLogType.done, v);
HabitLog skip(String d) => _log(d, HabitLogType.skip);
HabitLog relapse(
  String d, [
  double v = 1,
  List<String> tr = const [],
  DateTime? at,
  String? note,
]) => _log(d, HabitLogType.relapse, v, tr, at, note);
HabitLog urge(
  String d, [
  double v = 1,
  List<String> tr = const [],
  DateTime? at,
]) => _log(d, HabitLogType.urge, v, tr, at);

Habit habit({
  HabitKind kind = HabitKind.build,
  HabitSchedule schedule = HabitSchedule.daily,
  HabitTarget target = HabitTarget.check,
  String startDate = '2026-09-01',
  bool isPrivate = false,
  String name = 'x',
}) => Habit(
  id: 'h',
  name: name,
  kind: kind,
  schedule: schedule,
  target: target,
  startDate: startDate,
  isPrivate: isPrivate,
  createdAt: _t0,
  updatedAt: _t0,
);

final daily = habit();
final quit = habit(kind: HabitKind.quit);

String? err(void Function() f) {
  try {
    f();
    return null;
  } on ValidationFailure catch (e) {
    return e.message;
  }
}

void main() {
  group('constants', () {
    test('milestones, XP, presets, daysBetween', () {
      expect(quitMilestones, [
        1,
        3,
        7,
        14,
        21,
        30,
        40,
        60,
        90,
        120,
        180,
        270,
        365,
      ]);
      expect(HabitXp.buildMet, 5);
      expect(HabitXp.buildMetDailyCap, 10);
      expect(HabitXp.quitCleanCheckIn, 3);
      expect(HabitXp.urgeResisted, 5);
      expect(HabitXp.urgeResistedDailyCap, 5);
      expect(HabitXp.quitMilestoneBonus[365], 365);
      expect(habitTriggerPresets, [
        'bosan',
        'stres',
        'sendirian',
        'malam',
        'medsos',
        'capek',
      ]);
      expect(habitDaysBetween('2026-09-01', '2026-09-25'), 24);
      expect(habitDaysBetween('2026-12-31', '2027-01-01'), 1);
    });
  });

  group('schemas', () {
    test('cleaning + defaults', () {
      expect(requireHabitName('  Minum\nair '), 'Minum air');
      final t = requireHabitTarget(HabitTarget.count(8, unit: ' gelas '));
      expect(t.toJson(), {'type': 'count', 'goal': 8, 'unit': 'gelas'});
      expect(habitReminderTimes(['21:30', '07:00', '07:00']), [
        '07:00',
        '21:30',
      ]);
      expect(habitWhy('  demi anak  '), 'demi anak');
    });
    test("count unit default 'kali'", () {
      expect(requireHabitTarget(HabitTarget.count(2)).unit, 'kali');
      expect(HabitTarget.tryParse({'type': 'count', 'goal': 2})!.unit, 'kali');
    });
    test('weekdays dedup + sorted, needs ≥ 1 day', () {
      expect(
        requireHabitSchedule(HabitSchedule.weekdays([5, 1, 3, 1])).toJson(),
        {
          'type': 'weekdays',
          'days': [1, 3, 5],
        },
      );
      expect(
        err(() => requireHabitSchedule(HabitSchedule.weekdays([]))),
        contains('minimal satu hari'),
      );
    });
    test('perWeek 1–7; unknown type / JSON string', () {
      expect(
        err(() => requireHabitSchedule(HabitSchedule.perWeek(8))),
        isNotNull,
      );
      expect(err(() => requireHabitSchedule(HabitSchedule.perWeek(7))), isNull);
      expect(HabitSchedule.tryParse({'type': 'monthly'}), isNull);
      expect(
        HabitSchedule.tryParse('{"type":"perWeek","times":3}'),
        HabitSchedule.perWeek(3),
      );
      expect(HabitSchedule.tryParse('nope'), isNull);
    });
    test('duration 1–1440 integer; count ≤ 10000', () {
      expect(
        err(() => requireHabitTarget(HabitTarget.duration(1441))),
        isNotNull,
      );
      expect(
        err(() => requireHabitTarget(HabitTarget.duration(1.5))),
        isNotNull,
      );
      expect(
        err(() => requireHabitTarget(HabitTarget.count(10001))),
        isNotNull,
      );
      expect(HabitTarget.tryParse({'type': 'count'}), isNull);
    });
    test('name 1–60, startDate real, ≤ 5 reminders HH:mm, why ≤ 500', () {
      expect(err(() => requireHabitName(' ')), 'Nama wajib diisi');
      expect(err(() => requireHabitName('x' * 61)), isNotNull);
      expect(err(() => requireHabitDate('2026-02-30')), isNotNull);
      expect(err(() => habitReminderTimes(['1:00'])), isNotNull);
      expect(
        err(
          () => habitReminderTimes([
            '01:00',
            '02:00',
            '03:00',
            '04:00',
            '05:00',
            '06:00',
          ]),
        ),
        isNotNull,
      );
      expect(err(() => habitWhy('x' * 501)), isNotNull);
    });
    test('triggers dedup case-insensitive, note cleaned, ≤ 10', () {
      expect(normalizeTriggers(['Stres', 'stres', ' malam ', '']), [
        'Stres',
        'malam',
      ]);
      expect(habitNote('  capek \r\n banget '), 'capek \n banget');
      expect(
        err(() => normalizeTriggers([for (var i = 0; i < 11; i++) 't$i'])),
        isNotNull,
      );
    });
    test('parse (lenient)', () {
      expect(HabitTarget.tryParse('{"type":"count"}'), isNull);
    });
  });

  group('normalizeHabitLog', () {
    Habit b(HabitTarget t) => habit(target: t);
    test('build', () {
      expect(normalizeHabitLog(b(HabitTarget.check), done(today, 7)).value, 1);
      final cnt = b(HabitTarget.count(8, unit: 'gelas'));
      expect(
        err(() => normalizeHabitLog(cnt, _log(today, HabitLogType.done))),
        'Progres wajib diisi',
      );
      expect(normalizeHabitLog(cnt, done(today, 3)).value, 3);
      expect(
        err(
          () =>
              normalizeHabitLog(b(HabitTarget.duration(30)), done(today, 2.5)),
        ),
        isNotNull,
      );
      final s = normalizeHabitLog(
        b(HabitTarget.check),
        _log(today, HabitLogType.skip, 3, ['x']),
      );
      expect(s.value, isNull);
      expect(s.triggers, isEmpty);
      expect(err(() => normalizeHabitLog(daily, relapse(today))), isNotNull);
      expect(err(() => normalizeHabitLog(daily, urge(today))), isNotNull);
    });
    test('quit', () {
      expect(err(() => normalizeHabitLog(quit, skip(today))), isNotNull);
      expect(normalizeHabitLog(quit, done(today, 5)).value, 1);
      final r = normalizeHabitLog(
        quit,
        _log(today, HabitLogType.relapse, null, ['bosan']),
      );
      expect(r.value, 1);
      expect(r.triggers, ['bosan']);
      expect(err(() => normalizeHabitLog(quit, urge(today, 0))), isNotNull);
      expect(err(() => normalizeHabitLog(quit, urge(today, 1.5))), isNotNull);
      expect(normalizeHabitLog(quit, urge(today, 3)).value, 3);
    });
  });

  group('build streak: daily', () {
    final logs = [
      done('2026-09-20'),
      done('2026-09-21'),
      skip('2026-09-22'),
      done('2026-09-23'),
      done('2026-09-24'),
    ];
    test("skip neutral, today unmet doesn't break → 4", () {
      final s = habitStreak(daily, logs, today);
      expect(s.current, 4);
      expect(s.unit, HabitStreakUnit.day);
      expect(s.periodMet, isFalse);
    });
    test('today met → 5', () {
      final s = habitStreak(daily, [...logs, done(today)], today);
      expect(s.current, 5);
      expect(s.periodMet, isTrue);
    });
    test('a missed day breaks (21st) → 3; longest 3', () {
      final s = habitStreak(daily, [
        done('2026-09-20'),
        done('2026-09-22'),
        done('2026-09-23'),
        done('2026-09-24'),
      ], today);
      expect((s.current, s.longest), (3, 3));
    });
    test('longest from history (4), current 1', () {
      final s = habitStreak(daily, [
        done('2026-09-10'),
        done('2026-09-11'),
        done('2026-09-12'),
        done('2026-09-13'),
        done('2026-09-24'),
      ], today);
      expect((s.current, s.longest), (1, 4));
    });
    test("yesterday missed → 0 (today pending doesn't save it)", () {
      expect(habitStreak(daily, [done('2026-09-23')], today).current, 0);
    });
    test("days before startDate don't break", () {
      expect(
        habitStreak(habit(startDate: '2026-09-24'), [
          done('2026-09-24'),
        ], today).current,
        1,
      );
    });
    test('count: partial past day is a miss; value ≥ goal met', () {
      final cnt = habit(target: HabitTarget.count(8, unit: 'gelas'));
      final s7 = habitStreak(cnt, [
        done('2026-09-23', 8),
        done('2026-09-24', 5),
        done(today, 3),
      ], today);
      expect((s7.current, s7.longest), (0, 1));
      final s8 = habitStreak(cnt, [
        done('2026-09-23', 8),
        done('2026-09-24', 9),
        done(today, 3),
      ], today);
      expect(s8.current, 2);
    });
    test('future startDate → 0', () {
      expect(habitStreak(habit(startDate: '2026-10-01'), [], today).current, 0);
    });
  });

  group('build streak: weekdays', () {
    final mwf = habit(schedule: HabitSchedule.weekdays([1, 3, 5]));
    final logs = [
      done('2026-09-14'),
      done('2026-09-16'),
      done('2026-09-18'),
      done('2026-09-21'),
      done('2026-09-23'),
    ];
    test('only scheduled days count; off days ignored → 5', () {
      expect(habitStreak(mwf, logs, today).current, 5);
    });
    test("done on an off day doesn't count", () {
      expect(habitStreak(mwf, [...logs, done('2026-09-22')], today).current, 5);
    });
    test('missed Wed 16 breaks → 3', () {
      expect(
        habitStreak(mwf, [
          done('2026-09-14'),
          done('2026-09-18'),
          done('2026-09-21'),
          done('2026-09-23'),
        ], today).current,
        3,
      );
    });
    test('status off vs missed', () {
      final idx = HabitLogIndex(const []);
      expect(buildDayStatus(mwf, idx, '2026-09-22', today), HabitDayState.off);
      expect(
        buildDayStatus(mwf, idx, '2026-09-23', today),
        HabitDayState.missed,
      );
    });
  });

  group('build streak: perWeek', () {
    final pw = habit(
      schedule: HabitSchedule.perWeek(3),
      startDate: '2026-08-31',
    );
    final logs = [
      done('2026-08-31'),
      done('2026-09-02'),
      done('2026-09-04'),
      done('2026-09-07'),
      done('2026-09-08'),
      done('2026-09-09'),
      done('2026-09-14'),
      done('2026-09-16'),
      done('2026-09-19'),
      done('2026-09-22'),
    ];
    test("3 met weeks; current week not met yet doesn't break", () {
      final s = habitStreak(pw, logs, today);
      expect(s.current, 3);
      expect(s.unit, HabitStreakUnit.week);
      expect(s.periodMet, isFalse);
    });
    test('current week met → 4', () {
      final s = habitStreak(pw, [
        ...logs,
        done('2026-09-23'),
        done('2026-09-24'),
      ], today);
      expect(s.current, 4);
      expect(s.periodMet, isTrue);
    });
    test('a missed week breaks → 1; longest 1', () {
      final s = habitStreak(
        pw,
        logs.where((l) => l.date != '2026-09-09'),
        today,
      );
      expect((s.current, s.longest), (1, 1));
    });
    test("skips lower the week's need (min(n, available))", () {
      final s = habitStreak(pw, [
        ...logs.where((l) => l.date != '2026-09-09'),
        skip('2026-09-09'),
        skip('2026-09-10'),
        skip('2026-09-11'),
        skip('2026-09-12'),
        skip('2026-09-13'),
      ], today);
      expect(s.current, 3);
    });
    test('partial first week: need = min(n, days since start)', () {
      final w = habitWeekStatus(
        habit(schedule: HabitSchedule.perWeek(3), startDate: '2026-09-25'),
        HabitLogIndex([done('2026-09-25'), done('2026-09-26')]),
        '2026-09-21',
        today,
      );
      expect((w.need, w.met, w.state), (3, 2, HabitWeekState.pending));
      final w2 = habitWeekStatus(
        habit(schedule: HabitSchedule.perWeek(3), startDate: '2026-09-26'),
        HabitLogIndex([done('2026-09-26'), done('2026-09-27')]),
        '2026-09-21',
        '2026-09-28',
      );
      expect((w2.need, w2.state), (2, HabitWeekState.met));
    });
  });

  group('quit streak', () {
    test('no relapse: startDate..today inclusive = 25', () {
      final s = habitStreak(quit, [], today);
      expect((s.current, s.longest, s.lastRelapse), (25, 25, null));
      expect(s.segments.single.ongoing, isTrue);
      expect(s.cleanSince, '2026-09-01');
    });
    test('after relapse on 20th: 5; longest 9; segments', () {
      final s = habitStreak(quit, [
        relapse('2026-09-10'),
        relapse('2026-09-20', 2),
      ], today);
      expect((s.current, s.longest, s.lastRelapse), (5, 9, '2026-09-20'));
      expect(
        [for (final x in s.segments) (x.start, x.end, x.days)],
        [
          ('2026-09-01', '2026-09-09', 9),
          ('2026-09-11', '2026-09-19', 9),
          ('2026-09-21', today, 5),
        ],
      );
    });
    test('relapse today → 0, relapsedToday', () {
      final s = habitStreak(quit, [relapse(today)], today);
      expect((s.current, s.relapsedToday, s.longest), (0, true, 24));
      expect(s.cleanSince, isNull);
    });
    test('relapses before start / after today ignored; done/urge ignored', () {
      expect(
        habitStreak(quit, [
          relapse('2026-08-20'),
          relapse('2026-09-30'),
          done(today),
          urge(today, 3),
        ], today).current,
        25,
      );
    });
    test('future start → 0; value 0 ignored; start day = 1', () {
      expect(
        habitStreak(
          habit(kind: HabitKind.quit, startDate: '2026-10-01'),
          [],
          today,
        ).current,
        0,
      );
      expect(habitStreak(quit, [relapse('2026-09-20', 0)], today).current, 25);
      expect(
        habitStreak(
          habit(kind: HabitKind.quit, startDate: today),
          [],
          today,
        ).current,
        1,
      );
    });
    test("cleanStreakBefore: 'sempat bersih 24 hari'", () {
      expect(cleanStreakBefore(quit, [relapse(today)], today), 24);
      expect(cleanStreakBefore(quit, [relapse('2026-09-20')], today), 4);
    });
  });

  test('milestones', () {
    for (final d in [7, 365, 400, 500]) {
      expect(isQuitMilestone(d), isTrue, reason: '$d');
    }
    expect(isQuitMilestone(8), isFalse);
    expect(isQuitMilestone(465), isFalse);
    expect(nextQuitMilestone(0), 1);
    expect(nextQuitMilestone(7), 14);
    expect(nextQuitMilestone(365), 400);
    expect(nextQuitMilestone(401), 500);
    expect(quitMilestonesReached(410), [
      1, 3, 7, 14, 21, 30, 40, 60, 90, 120, 180, 270, 365, 400, //
    ]);
  });

  group('completion rate', () {
    test('daily: 3 met / 5 scheduled', () {
      final r = habitCompletion(
        daily,
        [
          done('2026-09-20'),
          done('2026-09-21'),
          skip('2026-09-22'),
          done('2026-09-24'),
        ],
        '2026-09-19',
        today,
        today,
      );
      expect((r.met, r.total), (3, 5));
      expect(r.rate, closeTo(0.6, 1e-9));
    });
    test('today counts once met; range before start → null', () {
      final r = habitCompletion(daily, [done(today)], today, today, today);
      expect((r.met, r.total), (1, 1));
      expect(
        habitCompletion(daily, [], '2026-08-01', '2026-08-10', today).rate,
        isNull,
      );
    });
    test('perWeek: weeks met/judged (current week pending excluded)', () {
      final pw = habit(
        schedule: HabitSchedule.perWeek(2),
        startDate: '2026-09-07',
      );
      final r = habitCompletion(
        pw,
        [done('2026-09-07'), done('2026-09-08'), done('2026-09-15')],
        '2026-09-07',
        today,
        today,
      );
      expect((r.met, r.total), (1, 2));
    });
    test('quit: clean days / days since start', () {
      final q = habit(kind: HabitKind.quit, startDate: '2026-09-16');
      final r = habitCompletion(
        q,
        [relapse('2026-09-20')],
        '2026-09-01',
        today,
        today,
      );
      expect((r.met, r.total), (9, 10));
    });
  });

  group('skips + today', () {
    test('canSkip: max 2 per rolling 7 days', () {
      expect(
        canSkipHabitDay([skip('2026-09-20'), skip('2026-09-23')], today),
        isFalse,
      );
      expect(
        canSkipHabitDay([skip('2026-09-18'), skip('2026-09-23')], today),
        isTrue,
      );
      expect(
        canSkipHabitDay([skip('2026-09-17'), skip('2026-09-30')], today),
        isTrue,
      );
      expect(canSkipHabitDay([skip(today), skip('2026-09-23')], today), isTrue);
      expect(
        canSkipHabitDay([skip('2026-09-26'), skip('2026-09-27')], today),
        isFalse,
      );
    });
    test('habitToday count progress', () {
      final t = habitToday(habit(target: HabitTarget.count(8, unit: 'gelas')), [
        done(today, 5),
      ], today);
      expect((t.progress, t.goal, t.met, t.scheduled), (5, 8, false, true));
      expect(t.fraction, closeTo(5 / 8, 1e-9));
    });
    test('habitToday quit: urges + clean check-in, streak', () {
      final t = habitToday(quit, [urge(today, 2), done(today)], today);
      expect(
        (t.urges, t.cleanCheckIn, t.streak.current, t.met),
        (2, true, 25, false),
      );
    });
    test('weekdays habit not scheduled on Friday', () {
      expect(
        habitToday(
          habit(schedule: HabitSchedule.weekdays([1])),
          [],
          today,
        ).scheduled,
        isFalse,
      );
    });
  });

  group('insights', () {
    // WIB-local `at` (the app reads the device zone; tests run in any zone).
    DateTime wib(String s) => DateTime.parse('$s+07:00').toLocal();
    final logs = [
      relapse(
        '2026-09-18',
        2,
        ['malam', 'Bosan'],
        wib('2026-09-18T22:30:00'),
        'susah tidur',
      ),
      relapse('2026-09-21', 1, ['bosan'], wib('2026-09-21T23:00:00')),
      urge('2026-09-22', 3, ['stres'], wib('2026-09-22T20:00:00')),
      urge('2026-09-23', 1, ['bosan']),
      done('2026-09-24'),
    ];
    final ins = habitInsights(quit, logs, '2026-09-15', today, today);
    int localHour(String s) => wib(s).hour;

    test('relapse totals weighted by value, by weekday (Mon = 0), by hour', () {
      expect((ins.relapses.total, ins.relapses.days), (3, 2));
      expect(ins.relapses.byWeekday[4], 2);
      expect(ins.relapses.byWeekday[0], 1);
      expect(ins.relapses.byHour[localHour('2026-09-18T22:30:00')], 2);
      expect(ins.relapses.byHour[localHour('2026-09-21T23:00:00')], 1);
    });
    test('urges: total 4, hour → 3, unknown hour 1', () {
      expect(ins.urges.total, 4);
      expect(ins.urges.byHour[localHour('2026-09-22T20:00:00')], 3);
      expect(ins.urges.unknownHour, 1);
    });
    test('top triggers merged case-insensitively, weighted', () {
      expect(
        [for (final t in ins.topTriggers) (t.tag, t.count)],
        [('Bosan', 4), ('stres', 3), ('malam', 2)],
      );
    });
    test('journal, heatmap statuses, segments', () {
      expect(ins.journal.single.note, 'susah tidur');
      expect(ins.heatmap, hasLength(11));
      HabitDayCell at(String d) => ins.heatmap.firstWhere((c) => c.date == d);
      expect(at('2026-09-18').state, HabitDayState.relapse);
      expect(at('2026-09-19').state, HabitDayState.clean);
      expect(at('2026-09-22').urges, 3);
      expect(ins.segments, hasLength(3));
      expect(ins.segments.last.ongoing, isTrue);
      expect(ins.streak.current, 4);
      expect(ins.completion.total, 11);
    });
    test('build heatmap statuses', () {
      final bi = habitInsights(
        daily,
        [done('2026-09-24'), skip('2026-09-23')],
        '2026-09-22',
        '2026-09-26',
        today,
      );
      expect(
        [for (final c in bi.heatmap) c.state.wire],
        ['missed', 'skip', 'met', 'pending', 'future'],
      );
    });
    test('streak history (mobile chart)', () {
      final h = habitInsights(
        daily,
        [
          done('2026-09-20'),
          done('2026-09-21'),
          skip('2026-09-22'),
          done('2026-09-23'),
        ],
        '2026-09-19',
        today,
        today,
      );
      expect(
        [for (final p in h.streakHistory) p.streak],
        [0, 1, 2, 2, 3, 0, 0],
      );
      final q = habitInsights(
        quit,
        [relapse('2026-09-23')],
        '2026-09-22',
        today,
        today,
      );
      expect([for (final p in q.streakHistory) p.streak], [22, 0, 1, 2]);
    });
  });

  test('maskedHabitName', () {
    expect(
      maskedHabitName(habit(name: 'PMO', isPrivate: true)),
      'Kebiasaan pribadi',
    );
    expect(maskedHabitName(habit(name: 'Baca')), 'Baca');
    expect(
      habit(name: 'PMO', isPrivate: true).publicTitle,
      'Kebiasaan pribadi',
    );
  });

  group('milestone hits (gamification plumbing)', () {
    test('quit: every run keeps its milestones', () {
      final hits = habitMilestoneHits(quit, [relapse('2026-09-10')], today);
      expect(
        [for (final h in hits) (h.milestone, h.reachedOn, h.runStart)],
        [
          (1, '2026-09-01', '2026-09-01'),
          (3, '2026-09-03', '2026-09-01'),
          (7, '2026-09-07', '2026-09-01'),
          (1, '2026-09-11', '2026-09-11'),
          (3, '2026-09-13', '2026-09-11'),
          (7, '2026-09-17', '2026-09-11'),
          (14, '2026-09-24', '2026-09-11'),
        ],
      );
    });
    test('build: 7-day run', () {
      final hits = habitMilestoneHits(daily, [
        for (var d = 10; d <= 17; d++) done('2026-09-$d'),
      ], today);
      expect(
        [for (final h in hits) (h.milestone, h.reachedOn)],
        [(7, '2026-09-16')],
      );
    });
  });
}
