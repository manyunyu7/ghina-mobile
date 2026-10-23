import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer containerFor(String url, {bool legacy = true}) {
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': url,
      'kantor.token': 'test',
      if (!legacy)
        'kantor.complexes.v1': jsonEncode({
          'activeId': 'new',
          'profiles': [
            KantorComplexProfile(
              id: 'new',
              name: 'Other',
              baseUrl: url,
              token: 'test',
            ).toJson(),
          ],
        }),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test(
    'last office belongs to its server, including trailing slash aliases',
    () async {
      await rememberKantorOffice('office-a', baseUrl: 'https://a.test/');
      await rememberKantorOffice('office-b', baseUrl: 'https://b.test');
      final a = containerFor('https://a.test');
      await a.read(kantorConfigProvider.future);
      expect(await a.read(kantorLastOfficeProvider.future), 'office-a');
      final b = containerFor('https://b.test');
      await b.read(kantorConfigProvider.future);
      expect(await b.read(kantorLastOfficeProvider.future), 'office-b');
    },
  );

  test('legacy last office migrates only to the original complex', () async {
    SharedPreferences.setMockInitialValues({
      'kantor.last_office': 'old-office',
    });
    final original = containerFor('https://old.test');
    await original.read(kantorConfigProvider.future);
    expect(await original.read(kantorLastOfficeProvider.future), 'old-office');
    final other = containerFor('https://other.test', legacy: false);
    await other.read(kantorConfigProvider.future);
    expect(await other.read(kantorLastOfficeProvider.future), isNull);
  });
}
