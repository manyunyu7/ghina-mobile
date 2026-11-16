import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ghina/app/kantor_routes.dart';
import 'package:ghina/app/ravel_app.dart';
import 'package:ghina/app/ravel_notifications.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/kantor_providers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('shared routes contain only Kantor pages', () {
    void check(List<RouteBase> routes, String base) {
      for (final route in routes.cast<GoRoute>()) {
        final path = '$base/${route.path}'.replaceAll('//', '/');
        expect(path, startsWith('/kantor'));
        check(route.routes, path);
      }
    }

    check(kantorRoutes, '');
  });

  test('notifications accept only Kantor navigation', () {
    expect(RavelNotifications.validRoute('/kantor'), isTrue);
    expect(RavelNotifications.validRoute('/kantor/o/my-pc/s/abc'), isTrue);
    for (final route in [
      null,
      '/kantor-other',
      '/home',
      '/login',
      'https://example.com',
    ]) {
      expect(RavelNotifications.validRoute(route), isFalse);
    }
  });

  test('notification target retains its connection, without credentials', () {
    final target = RavelNotifications.targetOf(
      '{"route":"/kantor/o/my-pc","baseUrl":"https://office.test"}',
    );
    expect(target?.route, '/kantor/o/my-pc');
    expect(target?.baseUrl, 'https://office.test');
    expect(
      RavelNotifications.targetOf(
        '{"route":"/home","baseUrl":"https://office.test"}',
      ),
      isNull,
    );
    expect(RavelNotifications.targetOf('/kantor'), isNull);
  });

  testWidgets('Ravel opens without Ghina login or finance database', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOnlyProvider.overrideWithValue(true),
          tokenStoreProvider.overrideWith(
            (_) => throw StateError('Ghina auth must not initialize'),
          ),
          appDatabaseProvider.overrideWith(
            (_) => throw StateError('Finance DB must not initialize'),
          ),
        ],
        child: const RavelApp(),
      ),
    );
    // The nested setup page can keep the underlying loading animation alive.
    // Bound the frames and assert the actual first-install screen.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Masuk'), findsNothing);
    expect(find.textContaining('Token'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
