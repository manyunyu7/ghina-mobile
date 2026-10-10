// Habit enrichment rules (port of `src/lib/habit-extras.ts`): tools, which
// dimensions show where, and `extra` validation. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

final _t = DateTime(2026, 10, 1);

HabitFieldDef def(
  String key,
  HabitFieldType type, {
  String? habitId,
  List<String>? options,
  int? min,
  int? max,
  List<String>? appliesTo,
  String? label,
}) => HabitFieldDef(
  id: 'f-$key',
  habitId: habitId,
  key: key,
  label: label ?? key,
  type: type,
  options: options,
  min: min,
  max: max,
  appliesTo: appliesTo,
  createdAt: _t,
  updatedAt: _t,
);

void main() {
  group('tools', () {
    test('titles are one line, details trimmed, order kept', () {
      final out = validateHabitTools(const [
        HabitTool(
          title: '  Minum\n air ',
          detail: ' Segelas ',
          kind: HabitToolKind.physical,
        ),
        HabitTool(title: 'Telepon teman'),
      ]);
      expect(out.map((t) => t.title), ['Minum air', 'Telepon teman']);
      expect(out.first.detail, 'Segelas');
      expect(out.first.kind, HabitToolKind.physical);
      expect(out.last.kind, HabitToolKind.other);
    });

    test('rejects empty and over-long titles, long details and > 30 tools', () {
      void bad(List<HabitTool> tools) => expect(
        () => validateHabitTools(tools),
        throwsA(
          isA<ValidationFailure>().having((f) => f.field, 'field', 'tools'),
        ),
      );
      bad(const [HabitTool(title: '   ')]);
      bad([HabitTool(title: 'x' * 81)]);
      bad([HabitTool(title: 'a', detail: 'd' * 501)]);
      bad([for (var i = 0; i < 31; i++) HabitTool(title: 't$i')]);
      expect(
        validateHabitTools([
          for (var i = 0; i < 30; i++) HabitTool(title: 't$i'),
        ]),
        hasLength(30),
      );
    });

    test('grouped by kind in the declared order, empty groups left out', () {
      final g = groupToolsByKind(const [
        HabitTool(title: 'a', kind: HabitToolKind.reward),
        HabitTool(title: 'b', kind: HabitToolKind.distraction),
        HabitTool(title: 'c', kind: HabitToolKind.reward),
      ]);
      expect(g.map((x) => x.kind), [
        HabitToolKind.distraction,
        HabitToolKind.reward,
      ]);
      expect(g.last.tools.map((t) => t.title), ['a', 'c']);
    });
  });

  group('which dimensions show', () {
    final all = def('suasana', HabitFieldType.text);
    final own = def('stres', HabitFieldType.scale, habitId: 'h1');
    final other = def('lain', HabitFieldType.text, habitId: 'h2');
    final doneOnly = def(
      'mood',
      HabitFieldType.boolean,
      appliesTo: const ['done'],
    );
    final defs = [all, own, other, doneOnly];

    test('global defs plus the habit own, never another habit', () {
      expect(fieldsForHabit(defs, 'h1').map((d) => d.key), [
        'suasana',
        'stres',
        'mood',
      ]);
    });

    test('no appliesTo = relapse, urge and events, but not the check-in', () {
      for (final s in ['relapse', 'urge', 'journal', 'milestone', 'event']) {
        expect(fieldAppliesTo(all, s), isTrue, reason: s);
      }
      expect(fieldAppliesTo(all, 'done'), isFalse);
      expect(fieldAppliesTo(all, 'skip'), isFalse);
    });

    test('an explicit list decides, done included', () {
      expect(fieldAppliesTo(doneOnly, 'done'), isTrue);
      expect(fieldAppliesTo(doneOnly, 'relapse'), isFalse);
      expect(fieldsForScope(defs, 'h1', 'done').map((d) => d.key), ['mood']);
      expect(fieldsForScope(defs, 'h1', 'relapse').map((d) => d.key), [
        'suasana',
        'stres',
      ]);
    });
  });

  group('extra values', () {
    final text = def('catatan', HabitFieldType.text, label: 'Catatan');
    final num_ = def('jam_tidur', HabitFieldType.number, label: 'Jam tidur');
    final scale = def('stres', HabitFieldType.scale, label: 'Stres');
    final scale5 = def(
      'puas',
      HabitFieldType.scale,
      min: 0,
      max: 5,
      label: 'Puas',
    );
    final select = def(
      'suasana',
      HabitFieldType.select,
      options: const ['capek', 'tenang'],
      label: 'Suasana',
    );
    final bool_ = def('sendiri', HabitFieldType.boolean, label: 'Sendiri');

    test('each type accepts what fits and says why otherwise', () {
      expect(checkExtraValue(text, 'ok'), isNull);
      expect(checkExtraValue(text, '  '), contains('tidak boleh kosong'));
      expect(checkExtraValue(text, 3), 'Catatan harus teks');
      expect(checkExtraValue(text, 'x' * 501), contains('maksimal 500'));
      expect(checkExtraValue(num_, 7.5), isNull);
      expect(checkExtraValue(num_, '7'), 'Jam tidur harus angka');
      expect(checkExtraValue(num_, double.infinity), isNotNull);
      expect(checkExtraValue(scale, 1), isNull);
      expect(checkExtraValue(scale, 10), isNull);
      expect(checkExtraValue(scale, 11), 'Stres harus 1–10');
      expect(checkExtraValue(scale, 0), 'Stres harus 1–10');
      expect(checkExtraValue(scale5, 0), isNull);
      expect(checkExtraValue(scale5, 6), 'Puas harus 0–5');
      expect(checkExtraValue(select, 'capek'), isNull);
      expect(checkExtraValue(select, 'lain'), contains('capek, tenang'));
      expect(checkExtraValue(bool_, false), isNull);
      expect(checkExtraValue(bool_, 'ya'), isNotNull);
    });

    test('a whole map: unknown keys fail, nulls drop, text is trimmed', () {
      final defs = [text, num_, scale];
      final ok = validateExtra({
        'catatan': '  pusing  ',
        'jam_tidur': 5,
        'stres': null,
      }, defs);
      expect(ok, {'catatan': 'pusing', 'jam_tidur': 5});
      expect(
        () => validateExtra({'hantu': 1}, defs),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            contains('"hantu" belum didefinisikan'),
          ),
        ),
      );
      expect(
        () => validateExtra({'stres': 99}, defs),
        throwsA(isA<ValidationFailure>().having((f) => f.field, 'f', 'extra')),
      );
    });

    test('at most 30 keys', () {
      final defs = [
        for (var i = 0; i < 31; i++) def('k$i', HabitFieldType.number),
      ];
      expect(
        () => validateExtra({for (var i = 0; i < 31; i++) 'k$i': i}, defs),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        validateExtra({for (var i = 0; i < 30; i++) 'k$i': i}, defs),
        hasLength(30),
      );
    });

    test('merge sets per key and a null removes the key', () {
      expect(mergeExtra({'a': 1, 'b': 'x'}, {'a': null, 'c': true}), {
        'b': 'x',
        'c': true,
      });
    });

    test('display values', () {
      expect(formatExtraValue(scale, 7), '7/10');
      expect(formatExtraValue(num_, 6.5), '6.5');
      expect(formatExtraValue(num_, 6.0), '6');
      expect(formatExtraValue(bool_, true), 'Ya');
      expect(formatExtraValue(bool_, false), 'Tidak');
      expect(formatExtraValue(select, 'capek'), 'capek');
      final entries = extraEntries(
        {'stres': 4, 'hantu': 1, 'jam_tidur': 3},
        [scale, num_],
      );
      expect(entries.map((e) => e.def.key), ['stres', 'jam_tidur']);
    });

    test('usage counts logs and events that carry a key', () {
      HabitLog log(Map<String, Object> extra) => HabitLog(
        id: 'l${extra.hashCode}',
        habitId: 'h',
        date: '2026-10-01',
        type: HabitLogType.relapse,
        extra: extra,
        createdAt: _t,
        updatedAt: _t,
      );
      HabitEvent event(Map<String, Object> extra) => HabitEvent(
        id: 'e${extra.hashCode}',
        habitId: 'h',
        date: '2026-10-01',
        kind: HabitEventKind.event,
        label: 'x',
        extra: extra,
        createdAt: _t,
        updatedAt: _t,
      );
      final u = fieldUsage(
        'stres',
        [
          log({'stres': 3}),
          log({'lain': 1}),
          log({'stres': 5, 'lain': 2}),
        ],
        [
          event({'stres': 1}),
          event(const {}),
        ],
      );
      expect(u.logs, 2);
      expect(u.events, 1);
    });
  });

  group('events', () {
    test('label 1–60 one line, note ≤ 2000 and empty = null', () {
      expect(
        validateEventLabel('  Lembur\nproyek contoh '),
        'Lembur proyek contoh',
      );
      expect(() => validateEventLabel(' '), throwsA(isA<ValidationFailure>()));
      expect(
        () => validateEventLabel('x' * 61),
        throwsA(isA<ValidationFailure>()),
      );
      expect(validateEventNote('  '), isNull);
      expect(validateEventNote(' ok '), 'ok');
      expect(
        () => validateEventNote('n' * 2001),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}
