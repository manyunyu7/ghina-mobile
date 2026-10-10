import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/models/habit_analysis_wire.dart';

void main() {
  test('parses the documented sample', () {
    final a = habitAnalysisFromWire('hab1', {
      'habitId': 'hab1',
      'kind': 'quit',
      'window': {'from': '2026-06-13', 'to': '2026-10-10', 'days': 120},
      'current': 30,
      'longest': 31,
      'unit': 'day',
      'lastRelapse': '2026-09-10',
      'runs': {
        'count': 4,
        'longest': {'start': '2026-07-01', 'end': '2026-07-31', 'days': 31},
        'recent': [
          {
            'start': '2026-09-11',
            'end': '2026-10-10',
            'days': 30,
            'ongoing': true,
          },
        ],
      },
      'relapses': {
        'total': 4,
        'days': 3,
        'perMonth': {'2026-09': 1, '2026-08': 3},
        'weekday': {'mon': 0, 'thu': 3, 'sat': 1},
        'timeOfDay': {'night': 0, 'morning': 1, 'evening': 3},
        'riskWindows': [
          {'from': '21:00', 'to': '23:59', 'count': 3, 'share': 0.75},
        ],
      },
      'triggers': [
        {'tag': 'bosan', 'count': 3, 'share': 0.75},
      ],
      'dimensions': [
        {
          'key': 'tingkat_stres',
          'label': 'Tingkat stres',
          'type': 'number',
          'lapse': {'n': 3, 'avg': 6.67},
          'ok': {'n': 1, 'avg': 6},
          'comparable': true,
        },
        {
          'key': 'suasana',
          'label': 'Suasana',
          'type': 'select',
          'lapse': {
            'n': 2,
            'options': {'capek': 2},
          },
          'ok': null,
          'comparable': false,
        },
      ],
      'lastEvents': [
        {
          'date': '2026-09-15',
          'kind': 'event',
          'label': 'Lembur proyek contoh',
          'note': 'Diubah',
        },
      ],
    })!;
    expect(a.isQuit, isTrue);
    expect(a.from, '2026-06-13');
    expect(a.days, 120);
    expect(a.current, 30);
    expect(a.longestRun!.days, 31);
    expect(a.recentRuns.single.ongoing, isTrue);
    expect(a.perMonth.keys.toList(), ['2026-08', '2026-09']);
    expect(a.weekday['thu'], 3);
    expect(a.riskWindows.single.share, 0.75);
    expect(a.triggers.single.tag, 'bosan');
    expect(a.dimensions[0].lapse!.avg, 6.67);
    expect(a.dimensions[0].ok!.avg, 6);
    expect(a.dimensions[0].comparable, isTrue);
    expect(a.dimensions[1].lapse!.options, {'capek': 2});
    expect(a.dimensions[1].ok, isNull);
    expect(a.lastEvents.single.label, 'Lembur proyek contoh');
    expect(a.isEmpty, isFalse);
  });

  test('empty object gives an empty analysis', () {
    final a = habitAnalysisFromWire('hab1', <String, Object?>{})!;
    expect(a.habitId, 'hab1');
    expect(a.isEmpty, isTrue);
    expect(a.perMonth, isEmpty);
    expect(a.longestRun, isNull);
  });

  test('missing and mistyped keys never throw', () {
    final a = habitAnalysisFromWire('hab1', {
      'current': 'abc',
      'runs': 5,
      'relapses': {
        'perMonth': 'x',
        'riskWindows': [1, 'a', {}],
      },
      'triggers': [
        {'count': 2},
        'nope',
        {'tag': 'stres', 'count': '2'},
      ],
      'dimensions': [
        {'label': 'tanpa kunci'},
        {'key': 'k', 'lapse': 'bad'},
      ],
      'lastEvents': 'x',
    })!;
    expect(a.current, 0);
    expect(a.runCount, 0);
    expect(a.perMonth, isEmpty);
    expect(a.riskWindows, isEmpty);
    expect(a.triggers.single.tag, 'stres');
    expect(a.triggers.single.count, 0);
    expect(a.dimensions.single.key, 'k');
    expect(a.dimensions.single.lapse, isNull);
    expect(a.lastEvents, isEmpty);
  });

  test('a non-object response is null', () {
    expect(habitAnalysisFromWire('h', null), isNull);
    expect(habitAnalysisFromWire('h', [1]), isNull);
    expect(habitAnalysisFromWire('h', 'x'), isNull);
  });
}
