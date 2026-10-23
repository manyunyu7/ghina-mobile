import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'migrates legacy credentials once while concurrent callers load',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'kantor.url': 'https://old.example',
        'kantor.token': 'legacy-secret',
      });
      final store = KantorConfigStore();
      await Future.wait([
        store.load(),
        store.loadProfiles(),
        store.loadActiveId(),
      ]);
      final profiles = await store.loadProfiles();
      expect(profiles.single.name, 'old.example');
      expect(profiles.single.config.token, 'legacy-secret');
      expect(await store.loadActiveId(), profiles.single.id);
      final raw = await const FlutterSecureStorage().read(
        key: 'kantor.complexes.v1',
      );
      expect((jsonDecode(raw!) as Map)['profiles'], hasLength(1));
    },
  );

  test('saved inactive profile keeps active credentials isolated', () async {
    final store = KantorConfigStore();
    const a = KantorComplexProfile(
      id: 'a',
      name: 'Mac Mini',
      baseUrl: 'https://a.example',
      token: 'a-secret',
    );
    const b = KantorComplexProfile(
      id: 'b',
      name: 'VPS',
      baseUrl: 'https://b.example',
      token: 'b-secret',
    );
    await store.upsert(a, activate: true);
    await store.upsert(b);
    expect((await store.load()).token, 'a-secret');
    await store.activate('b');
    expect((await store.load()).baseUrl, b.baseUrl);
    expect((await store.load()).token, b.token);
    await expectLater(store.remove('b'), throwsA(isA<KantorException>()));
    await store.remove('a');
    expect((await store.loadProfiles()).single.id, 'b');
  });

  test(
    'concurrent upserts preserve both profiles and legacy save edits active',
    () async {
      final store = KantorConfigStore();
      await Future.wait([
        store.upsert(
          const KantorComplexProfile(
            id: 'a',
            name: 'One',
            baseUrl: 'https://a.example',
            token: 'a',
          ),
          activate: true,
        ),
        store.upsert(
          const KantorComplexProfile(
            id: 'b',
            name: 'Two',
            baseUrl: 'https://b.example',
            token: 'b',
          ),
        ),
      ]);
      await store.save(
        const KantorConfig(baseUrl: 'https://new.example', token: 'new'),
      );
      final profiles = await store.loadProfiles();
      expect(profiles, hasLength(2));
      expect(profiles.first.id, 'a');
      expect(profiles.first.name, 'One');
      expect(profiles.first.baseUrl, 'https://new.example');
      await expectLater(
        store.activate('missing'),
        throwsA(isA<KantorException>()),
      );
      expect(await store.loadActiveId(), 'a');
    },
  );
}
