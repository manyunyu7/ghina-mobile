// Smoke test of the "Log Notifikasi" page: the real drift repository (in
// memory) behind the real use cases / providers.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/repositories/notification_log_repositories.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/notification_listener.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/notification_log/pages/notification_log_page.dart';
import 'package:ghina/presentation/state/notification_capture_controller.dart';

import 'transactions/_feature_harness.dart';

final _today = DateTime(2026, 10, 18);

class _Listener implements DeviceNotificationListener {
  @override
  bool get isSupported => true;
  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<void> openAccessSettings() async {}
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<bool> isRunning() async => true;
  @override
  Future<List<InstalledApp>> installedApps() async => const [];
  @override
  Future<String?> appLabel(String packageName) async => null;
}

class _Prefs implements NotificationCapturePrefs {
  @override
  Future<bool> loadEnabled() async => true;
  @override
  Future<void> saveEnabled(bool value) async {}
}

void main() {
  testWidgets('timeline by day, per-app view, filters', (t) async {
    final c = makeContainer(
      now: _today,
      overrides: [
        deviceNotificationListenerProvider.overrideWithValue(_Listener()),
        notificationCapturePrefsProvider.overrideWithValue(_Prefs()),
      ],
    );
    final db = c.read(appDatabaseProvider);
    Future<void> add(
      String pkg,
      String app,
      String title,
      String body,
      DateTime at,
    ) => insertCapturedNotification(
      db,
      packageName: pkg,
      appName: app,
      title: title,
      body: body,
      postedAt: at,
      capturedAt: at,
    ).then((_) {});
    await real(t, () async {
      await add(
        'com.jago',
        'Jago',
        'Jago',
        'You received Rp10.000 from Budi',
        _today.add(const Duration(hours: 9)),
      );
      await add(
        'com.wa',
        'WhatsApp',
        'Andi',
        'Halo bro',
        _today.add(const Duration(hours: 8)),
      );
      await add(
        'com.wa',
        'WhatsApp',
        'Sari',
        'Udah sampai?',
        _today.subtract(const Duration(hours: 3)),
      );
      await add(
        'com.shopee',
        'Shopee',
        'Promo',
        'Diskon gede',
        _today.subtract(const Duration(days: 3)),
      );
    });

    t.view.physicalSize = const Size(780, 3200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: NotificationLogPage(today: _today),
        ),
      ),
    );
    await settle(t);

    expect(find.textContaining('Hari ini ·'), findsOneWidget);
    expect(find.textContaining('Kemarin ·'), findsOneWidget);
    expect(find.text('Halo bro'), findsOneWidget);
    expect(find.text('Diskon gede'), findsOneWidget);

    // Only money.
    await t.tap(find.text('Ada nominal'));
    await settle(t);
    expect(find.text('Halo bro'), findsNothing);
    expect(find.text('You received Rp10.000 from Budi'), findsOneWidget);
    await t.tap(find.text('Semua'));
    await settle(t);

    // Today only.
    await t.tap(find.byKey(const ValueKey('notif-range-today')));
    await settle(t);
    expect(find.text('Udah sampai?'), findsNothing);
    expect(find.text('Halo bro'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('notif-range-all')));
    await settle(t);

    // Per app → tap WhatsApp → timeline of WhatsApp only.
    await t.tap(find.text('Per aplikasi'));
    await settle(t);
    expect(find.byKey(const ValueKey('notif-app-com.wa')), findsOneWidget);
    expect(find.byKey(const ValueKey('notif-app-com.shopee')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('notif-app-com.wa')));
    await settle(t);
    expect(find.byKey(const ValueKey('notif-app-chip')), findsOneWidget);
    expect(find.text('Halo bro'), findsOneWidget);
    expect(find.text('Diskon gede'), findsNothing);

    await tearDownApp(t, c);
  });
}
