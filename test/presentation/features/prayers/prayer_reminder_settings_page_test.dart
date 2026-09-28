import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/prayers/pages/prayer_reminder_settings_page.dart';
import 'package:ghina/presentation/features/prayers/pages/prayers_page.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/_helpers.dart' show loadGhinaFonts;
import '../profile/_harness.dart';

final _routes = [
  GoRoute(path: '/prayers', builder: (_, _) => const PrayersPage()),
  GoRoute(
    path: '/prayers/reminders',
    builder: (_, _) => const PrayerReminderSettingsPage(),
  ),
];

void main() {
  setUpAll(loadGhinaFonts);

  testWidgets('bell on the Sholat page opens the reminder settings', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    expect(find.byKey(const ValueKey('prayer-schedule')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prayer-reminders')));
    await settle(tester, 8);
    expect(find.text('Reminder Sholat'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('master switch, city, per-prayer options are saved', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/prayers/reminders',
      routes: _routes,
    );
    expect(find.text('Reminder Sholat'), findsOneWidget);
    expect(find.textContaining('Yogyakarta'), findsWidgets);

    // Master switch (no permission model under test → straight on).
    await tester.tap(find.byKey(const ValueKey('prayer-reminders-enabled')));
    await settle(tester, 8);
    expect(h.prayerReminders.value.enabled, isTrue);
    await drain(tester); // toast

    // Pick Bandung from the city list.
    await scrollTo(tester, find.byKey(const ValueKey('prayer-pick-city')));
    await tester.tap(find.byKey(const ValueKey('prayer-pick-city')));
    await settle(tester, 8);
    await tester.enterText(find.byKey(const ValueKey('city-search')), 'band');
    await settle(tester, 3);
    expect(find.byKey(const ValueKey('city-Bandung')), findsOneWidget);
    expect(find.byKey(const ValueKey('city-Jakarta')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('city-Bandung')));
    await settle(tester, 8);
    expect(h.prayerReminders.value.location.name, 'Bandung');
    expect(h.prayerReminders.value.location.isGps, isFalse);

    // Maghrib: expand, turn follow-ups off, correct the time by +1 minute.
    final maghrib = find.byKey(const ValueKey('prayer-slot-maghrib'));
    await scrollTo(tester, maghrib);
    await tester.tap(
      find.descendant(of: maghrib, matching: find.text('Maghrib')),
    );
    await settle(tester, 6);
    await scrollTo(tester, find.byKey(const ValueKey('slot-fu-maghrib')));
    await tester.tap(find.byKey(const ValueKey('slot-fu-maghrib')));
    await settle(tester, 4);
    expect(
      h.prayerReminders.value.slot(Prayer.maghrib).followUpEnabled,
      isFalse,
    );
    final offset = find.byKey(const ValueKey('slot-offset-maghrib'));
    await scrollTo(tester, offset);
    await tester.tap(
      find.descendant(of: offset, matching: find.byTooltip('Tambah')),
    );
    await settle(tester, 4);
    expect(h.prayerReminders.value.slot(Prayer.maghrib).offsetMinutes, 1);
    // Other prayers untouched.
    expect(h.prayerReminders.value.slot(Prayer.isya).followUpEnabled, isTrue);
    await drain(tester);
  });

  testWidgets('fits 360×640 at 1.3× text', (tester) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/prayers/reminders',
      routes: _routes,
      size: const Size(360, 640),
      textScale: 1.3,
    );
    final maghrib = find.byKey(const ValueKey('prayer-slot-maghrib'));
    await scrollTo(tester, maghrib);
    await tester.tap(
      find.descendant(of: maghrib, matching: find.text('Maghrib')),
    );
    await settle(tester, 6);
    await scrollTo(tester, find.byKey(const ValueKey('slot-offset-maghrib')));
    expect(tester.takeException(), isNull);
    await drain(tester);
  });
}
