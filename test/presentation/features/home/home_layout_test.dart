import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/home/layout/home_layout.dart';
import 'package:ghina/presentation/features/home/layout/home_layout_store.dart';
import 'package:ghina/presentation/features/home/layout/home_presets.dart';
import 'package:ghina/presentation/features/home/pages/home_layout_editor.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shell/test_utils.dart';
import '_task_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    test('there are at least 10 presets, valid and uniquely named', () {
      expect(homePresets.length, greaterThanOrEqualTo(10));
      expect(homePresets.map((p) => p.id).toSet().length, homePresets.length);
      for (final p in homePresets) {
        final cards = p.entries.map((e) => e.card).toList();
        expect(cards, isNotEmpty, reason: p.id);
        expect(
          cards.toSet().length,
          cards.length,
          reason: '${p.id} duplicates',
        );
        for (final e in p.entries) {
          expect(e.card.sizes, contains(e.size), reason: '${p.id}/${e.card}');
        }
      }
      expect(homePresets.first.id, homeDefaultPresetId);
    });

    test(
      'encode/decode round-trips; unknown ids and duplicates are dropped',
      () {
        final l = const HomeLayout([
          HomeEntry(HomeCard.tasks),
          HomeEntry(HomeCard.agenda, HomeCardSize.small),
        ], presetId: 'produktif');
        expect(HomeLayout.decode(l.encode()), l);
        final odd = HomeLayout.decode(
          '{"cards":[{"id":"nope"},{"id":"tasks"},{"id":"tasks"},'
          '{"id":"agenda","size":"wide"}]}',
        )!;
        expect(odd.entries.map((e) => e.card), [
          HomeCard.tasks,
          HomeCard.agenda,
        ]);
        expect(HomeLayout.decode('garbage'), isNull);
        expect(HomeLayout.decode(null), isNull);
      },
    );

    test('a size the card cannot take falls back to its default', () {
      expect(
        const HomeEntry(HomeCard.tasks, HomeCardSize.small).size,
        HomeCardSize.medium,
      );
    });

    test('move, add, remove, resize', () {
      var l = const HomeLayout([
        HomeEntry(HomeCard.tasks),
        HomeEntry(HomeCard.habits),
        HomeEntry(HomeCard.menu),
      ]);
      l = l.move(0, 2);
      expect(l.entries.map((e) => e.card), [
        HomeCard.habits,
        HomeCard.menu,
        HomeCard.tasks,
      ]);
      l = l
          .remove(HomeCard.menu)
          .add(HomeCard.agenda)
          .resize(HomeCard.agenda, HomeCardSize.wide);
      expect(l.entries.map((e) => e.card), [
        HomeCard.habits,
        HomeCard.tasks,
        HomeCard.agenda,
      ]);
      expect(l.entries.last.size, HomeCardSize.wide);
      expect(l.hidden, contains(HomeCard.menu));
    });
  });

  group('storage', () {
    test('saved layout is loaded by a fresh container', () async {
      final a = ProviderContainer();
      addTearDown(a.dispose);
      a
          .read(homeLayoutProvider.notifier)
          .set(
            const HomeLayout([HomeEntry(HomeCard.menu)], presetId: 'keuangan'),
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final b = ProviderContainer();
      addTearDown(b.dispose);
      expect(
        b.read(homeLayoutProvider),
        homeDefaultLayout(),
      ); // until storage answers
      b.listen(homeLayoutProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(b.read(homeLayoutProvider).entries.map((e) => e.card), [
        HomeCard.menu,
      ]);
      expect(b.read(homeLayoutProvider).presetId, 'keuangan');
    });

    test('reset returns to the default', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(homeLayoutProvider.notifier)..set(const HomeLayout([]));
      n.reset();
      expect(c.read(homeLayoutProvider), homeDefaultLayout());
    });
  });

  group('screens', () {
    Future<void> load(WidgetTester t) async {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settle(t);
    }

    testWidgets(
      'hiding a card in the editor removes it from Beranda and sticks',
      (t) async {
        await pumpPage(
          t,
          const HomePage(),
          overrides: withTasks(pageOverrides()),
        );
        await load(t);
        expect(find.text('TOTAL SALDO'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('home-customize')));
        await settle(t);
        await t.tap(find.byKey(const ValueKey('layout-hide-balance')));
        await settle(t);
        expect(find.byKey(const ValueKey('layout-row-balance')), findsNothing);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('layout-add-balance')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey('layout-add-balance')),
          findsOneWidget,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('home.layout.v1'), isNot(contains('"balance"')));
        Navigator.of(t.element(find.byType(HomeLayoutEditorPage))).pop();
        await settle(t);
        expect(find.text('TOTAL SALDO'), findsNothing);
      },
    );

    testWidgets('dragging a card changes the order', (t) async {
      await pumpPage(
        t,
        const HomeLayoutEditorPage(),
        overrides: pageOverrides(),
      );
      final before = t
          .getTopLeft(find.byKey(const ValueKey('layout-row-balance')))
          .dy;
      await t.drag(
        find.byKey(const ValueKey('layout-handle-mascot')),
        const Offset(0, 160),
      );
      await settle(t);
      final c = ProviderScope.containerOf(
        t.element(find.byType(HomeLayoutEditorPage)),
      );
      final order = c
          .read(homeLayoutProvider)
          .entries
          .map((e) => e.card)
          .toList();
      expect(order.indexOf(HomeCard.mascot), greaterThan(0));
      expect(
        t.getTopLeft(find.byKey(const ValueKey('layout-row-balance'))).dy,
        lessThan(before),
      );
    });

    testWidgets('adding a card and picking a size', (t) async {
      await pumpPage(
        t,
        const HomeLayoutEditorPage(),
        overrides: pageOverrides(),
      );
      final add = find.byKey(const ValueKey('layout-add-agenda'));
      await t.scrollUntilVisible(
        add,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(add);
      await settle(t);
      final row = find.byKey(const ValueKey('layout-row-agenda'));
      await t.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey('layout-size-agenda')));
      await settle(t);
      await t.tap(find.text('Kecil').last);
      await settle(t);
      final c = ProviderScope.containerOf(
        t.element(find.byType(HomeLayoutEditorPage)),
      );
      final e = c
          .read(homeLayoutProvider)
          .entries
          .firstWhere((e) => e.card == HomeCard.agenda);
      expect(e.size, HomeCardSize.small);
    });

    testWidgets('picking a preset installs it, shows it and remains editable', (
      t,
    ) async {
      await pumpPage(
        t,
        const HomePage(),
        overrides: withTasks(pageOverrides()),
      );
      await load(t);
      await t.tap(find.byKey(const ValueKey('home-customize')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('layout-preset-card')));
      await settle(t);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('preset-keuangan')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey('preset-keuangan')));
      await settle(t);
      final c = ProviderScope.containerOf(
        t.element(find.byType(HomeLayoutEditorPage)),
      );
      expect(c.read(homeLayoutProvider).presetId, 'keuangan');
      expect(c.read(homeLayoutProvider).entries.length, 8);
      // Editable afterwards: the preset label turns into "(diubah)".
      await t.tap(find.byKey(const ValueKey('layout-hide-balance')));
      await settle(t);
      expect(find.textContaining('Keuangan'), findsWidgets);
      expect(find.textContaining('(diubah)'), findsOneWidget);
    });

    testWidgets('small cards share a row on Beranda', (t) async {
      SharedPreferences.setMockInitialValues({
        'home.layout.v1': const HomeLayout([
          HomeEntry(HomeCard.notes, HomeCardSize.small),
          HomeEntry(HomeCard.screener, HomeCardSize.small),
        ]).encode(),
      });
      await pumpPage(
        t,
        const HomePage(),
        overrides: withTasks(pageOverrides()),
      );
      await load(t);
      final a = t.getTopLeft(
        find.byKey(const ValueKey('home-tile-/notes-small')),
      );
      final b = t.getTopLeft(
        find.byKey(const ValueKey('home-tile-/investments/screener-small')),
      );
      expect(a.dy, b.dy);
      expect(b.dx, greaterThan(a.dx));
    });

    for (final p in homePresets) {
      testWidgets('preset ${p.id} renders on Beranda without errors', (
        t,
      ) async {
        SharedPreferences.setMockInitialValues({
          'home.layout.v1': p.toLayout().encode(),
        });
        await pumpPage(
          t,
          const HomePage(),
          overrides: withTasks(
            pageOverrides(
              extra: [
                watchReminderGroupsProvider.overrideWith(
                  (ref) => Stream.value((
                    overdue: <ReminderItem>[],
                    upcoming: <ReminderItem>[],
                    done: <ReminderItem>[],
                  )),
                ),
                watchCalendarEventsProvider.overrideWith(
                  (ref) => Stream.value(<CalendarEvent>[]),
                ),
                watchDreamsProvider.overrideWith(
                  (ref) => Stream.value(<Dream>[]),
                ),
                watchUpcomingPeopleProvider.overrideWith(
                  (ref) => Stream.value(<UpcomingEvent>[]),
                ),
              ],
            ),
          ),
        );
        await load(t);
        expect(t.takeException(), isNull);
      });
    }
  });
}
