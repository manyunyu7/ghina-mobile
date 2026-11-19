import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart';

void main() {
  test('parses CLIENT_ID:CLIENT_SECRET into Cloudflare Access headers', () {
    expect(kantorEdgeHeaders(' abc.access:cfast_x:y '), {
      'CF-Access-Client-Id': 'abc.access',
      'CF-Access-Client-Secret': 'cfast_x:y',
    });
  });

  test('malformed or empty edge gives no headers', () {
    for (final s in ['', 'abc', ':secret', 'id:', 'id:se cret', 'id\n:x']) {
      expect(kantorEdgeHeaders(s), isEmpty, reason: s);
    }
  });

  test('profile keeps edge through JSON and into its config and headers', () {
    const p = KantorComplexProfile(
      id: '1',
      name: 'Mini',
      baseUrl: 'https://ravel.example',
      token: 't',
      edge: 'id.access:sec',
    );
    final back = KantorComplexProfile.fromJson(p.toJson());
    expect(back.edge, 'id.access:sec');
    final api = KantorApi(back.config);
    expect(api.authHeaders['CF-Access-Client-Id'], 'id.access');
    expect(api.authHeaders['CF-Access-Client-Secret'], 'sec');
    expect(api.authHeaders['Authorization'], 'Bearer t');
  });

  test('old profiles without edge send no Cloudflare headers', () {
    final p = KantorComplexProfile.fromJson({
      'id': '1',
      'name': 'Mini',
      'baseUrl': 'https://office.example',
      'token': 't',
    });
    expect(p.toJson().containsKey('edge'), isFalse);
    expect(KantorApi(p.config).authHeaders.keys, ['Authorization']);
  });
}
