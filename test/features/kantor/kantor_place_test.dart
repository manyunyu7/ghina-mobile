import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ghina/presentation/features/kantor/kantor_place.dart';

Map<String, dynamic> _state({bool ended = false}) => {
  'offices': [
    {
      'id': 'o1',
      'sessions': [
        {'sid': 's1', 'status': ended ? 'ended' : 'working'},
      ],
    },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves and restores per complex, independently', () async {
    await KantorPlaceStore.update(
      'A',
      (_) => KantorPlace.atSession(null, 'o1', 's1', 'terminal'),
    );
    await KantorPlaceStore.update(
      'B',
      (_) => KantorPlace.atOffice('o2', 'board'),
    );
    final a = await KantorPlaceStore.load('A');
    final b = await KantorPlaceStore.load('B');
    expect(a?.sid, 's1');
    expect(a?.sessionTab, 'terminal');
    expect(b, KantorPlace.atOffice('o2', 'board'));
    expect(await KantorPlaceStore.load('C'), isNull);
  });

  test('session keeps the office tab of the same office', () {
    final prev = KantorPlace.atOffice('o1', 'wiki');
    expect(KantorPlace.atSession(prev, 'o1', 's1', 'chat').tab, 'wiki');
    expect(KantorPlace.atSession(prev, 'o9', 's1', 'chat').tab, isNull);
  });

  test('opening an office clears the session', () async {
    await KantorPlaceStore.update(
      'A',
      (_) => KantorPlace.atSession(null, 'o1', 's1', 'terminal'),
    );
    await KantorPlaceStore.update(
      'A',
      (_) => KantorPlace.atOffice('o1', 'agen'),
    );
    expect((await KantorPlaceStore.load('A'))?.sid, isNull);
  });

  test('garbage in storage is ignored', () async {
    SharedPreferences.setMockInitialValues({'kantor.place.v1.A': '{{bad'});
    expect(await KantorPlaceStore.load('A'), isNull);
    expect(KantorPlace.fromJson({'office': ''}), isNull);
    expect(KantorPlace.fromJson({'office': 'o', 'tab': '../x'})?.tab, isNull);
  });

  test('resume paths: office, tab and live session on top', () {
    final p = KantorPlace.atSession(
      KantorPlace.atOffice('o1', 'wiki'),
      'o1',
      's1',
      'terminal',
    );
    expect(kantorResumePaths(p, _state()), [
      '/kantor/o/o1?tab=wiki',
      '/kantor/o/o1/s/s1?tab=terminal',
    ]);
  });

  test('ended or unknown session falls back to the office and its tab', () {
    final p = KantorPlace.atSession(
      KantorPlace.atOffice('o1', 'wiki'),
      'o1',
      's1',
      'terminal',
    );
    expect(kantorResumePaths(p, _state(ended: true)), [
      '/kantor/o/o1?tab=wiki',
    ]);
    final gone = KantorPlace.atSession(null, 'o1', 'zzz', 'chat');
    expect(kantorResumePaths(gone, _state()), ['/kantor/o/o1']);
  });

  test('missing office or no place falls back to the complex page', () {
    expect(kantorResumePaths(KantorPlace.atOffice('x', 'agen'), _state()), []);
    expect(kantorResumePaths(null, _state()), []);
    expect(kantorResumePaths(KantorPlace.atOffice('o1', null), {}), []);
  });

  test('leaving a session keeps the office and its tab', () {
    final at = KantorPlace.atSession(
      KantorPlace.atOffice('o1', 'wiki'),
      'o1',
      's1',
      'terminal',
    );
    expect(at.withoutSession(), KantorPlace.atOffice('o1', 'wiki'));
  });

  // Explicit navigation (agent picked in the switcher, notification deep link)
  // builds its own route and never calls kantorResumePaths; only /kantor does.
}
