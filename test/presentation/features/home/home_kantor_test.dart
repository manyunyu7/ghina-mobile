import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/features/home/widgets/home_kantor.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shell/test_utils.dart';

const _state = {
  'offices': [
    {
      'id': 'a',
      'name': 'Kantor A',
      'monthCost': 12.5,
      'sessions': [
        {
          'sid': 's1',
          'status': 'working',
          'tool': {'name': 'Bash', 'label': 'ls'},
          'look': {
            'name': 'Dina',
            'color': '#2F5D9E',
            'hair': '#2B1D14',
            'skin': '#F1C9A5',
          },
        },
      ],
    },
  ],
  'inbox': [
    {
      'id': 'i1',
      'office': 'a',
      'who': 'Dina',
      'tool': 'Bash',
      'summary': 'ls',
      'held': true,
    },
  ],
};

/// Buttons and pills render upper-case.
Finder label(String s) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.toLowerCase() == s.toLowerCase(),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'kantor.last_office': 'a'});
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    });
  });

  // Secure storage and prefs answer on the real event loop.
  Future<void> load(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(t);
  }

  List<Override> ov(Future<Map<String, dynamic>> Function() state) =>
      pageOverrides(extra: [kantorStateProvider.overrideWith((_) => state())]);

  testWidgets('not configured: invites setup and can be dismissed', (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    await pumpPage(
      t,
      const Scaffold(body: HomeKantorCard()),
      overrides: ov(() async => {}),
    );
    await load(t);
    expect(label('Atur Kantor'), findsOneWidget);
    await t.tap(label('Atur Kantor'));
    await settle(t);
    expect(find.text('ROUTE:/kantor/settings'), findsOneWidget);
  });

  testWidgets('dismissed invitation hides the card', (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'home.kantor_invite_dismissed': true,
    });
    await pumpPage(
      t,
      const Scaffold(body: HomeKantorCard()),
      overrides: ov(() async => {}),
    );
    await load(t);
    expect(find.byKey(const ValueKey('home-kantor')), findsNothing);
  });

  testWidgets('waiting permission, working agent, cost and shortcuts', (
    t,
  ) async {
    await pumpPage(
      t,
      const Scaffold(body: SingleChildScrollView(child: HomeKantorCard())),
      overrides: ov(() async => Map<String, dynamic>.from(_state)),
    );
    await load(t);
    expect(label('1 izin menunggu'), findsOneWidget);
    expect(label('Izinkan'), findsOneWidget);
    expect(find.textContaining('Dina · Bash ls'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kantor-cost')), findsOneWidget);
    expect(label(r'$13 bulan ini (estimasi)'), findsOneWidget);
    await t.tap(label('Suruh manager'));
    await settle(t);
    expect(find.text('ROUTE:/kantor/o/a'), findsOneWidget);
  });

  testWidgets('unreachable: says so and offers retry', (t) async {
    await pumpPage(
      t,
      const Scaffold(body: HomeKantorCard()),
      overrides: ov(
        () async => throw const KantorException(KantorFailure.unreachable, 'x'),
      ),
    );
    await load(t);
    expect(find.textContaining('Tailscale'), findsOneWidget);
    expect(label('Coba lagi'), findsOneWidget);
  });
}
