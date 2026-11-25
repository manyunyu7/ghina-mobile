import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart';
import 'package:ghina/presentation/features/remote/remote_auth.dart';

void main() {
  test('pair request from POST /api/remote/pair', () {
    final r = RemotePairRequest.fromJson({
      'id': 'rp_1',
      'claim': 'c',
      'device': 'Ravel HP',
      'expiresAt': '2026-11-25T10:05:00.000Z',
      'hostsNotified': 2,
    });
    expect(r.id, 'rp_1');
    expect(r.hostsNotified, 2);
    expect(r.expiresAt.toUtc(), DateTime.utc(2026, 11, 25, 10, 5));
    expect(
      () => RemotePairRequest.fromJson({'id': 'x'}),
      throwsA(isA<KantorException>()),
    );
  });

  test('devices and pending requests', () {
    final d = RemoteDevice.fromJson({
      'id': 'rd_1',
      'device': 'Fold',
      'lastUsed': '2026-11-25T10:00:00Z',
      'via': 'kode',
      'current': true,
    })!;
    expect((d.device, d.current, d.via), ('Fold', true, 'kode'));
    expect(RemoteDevice.fromJson({'device': 'no id'}), isNull);
    expect(
      RemotePendingPair.fromJson({'id': 'rp_2', 'device': 'Tab'})!.device,
      'Tab',
    );
  });

  test('viewer token is stored per Kantor address', () {
    expect(
      RemoteDeviceStore.keyFor('http://kantor.example:8787/'),
      RemoteDeviceStore.keyFor('http://kantor.example:8787'),
    );
    expect(
      RemoteDeviceStore.keyFor('http://a:1'),
      isNot(RemoteDeviceStore.keyFor('http://b:1')),
    );
  });

  test('viewer client keeps the address, swaps the token', () {
    final owner = KantorApi(
      const KantorConfig(baseUrl: 'http://k:8787', token: 'owner'),
    );
    final v = RemoteAuth.viewerApi(owner, 'kcview_abc');
    expect(v.config.baseUrl, 'http://k:8787');
    expect(v.authHeaders['Authorization'], 'Bearer kcview_abc');
  });
}
