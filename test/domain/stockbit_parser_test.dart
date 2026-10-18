// Parsing of pasted Stockbit text, JWT expiry and session health. Tokens are
// obviously fake (unsigned, invented payloads).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

String _b64(Object o) =>
    base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');

/// A fake unsigned JWT that expires at [exp] (null = no `exp` claim).
String fakeJwt(DateTime? exp, {String tag = 'a'}) =>
    '${_b64({'alg': 'none'})}.${_b64({'sub': tag, if (exp != null) 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.fakesig$tag';

final _exp = DateTime(2026, 12, 1, 10);
final _access = fakeJwt(_exp, tag: 'access');
final _refresh = fakeJwt(DateTime(2027, 1, 1), tag: 'refresh');

StockbitTokens _ok(String text) {
  final r = parseStockbitInput(text);
  expect(r, isA<StockbitParsed>(), reason: text);
  return (r as StockbitParsed).tokens;
}

void main() {
  group('parseStockbitInput', () {
    test('a bare JWT', () {
      final t = _ok('  $_access \n');
      expect(t.access, _access);
      expect(t.refresh, isNull);
    });

    test('Bearer x and an Authorization header line', () {
      expect(_ok('Bearer $_access').access, _access);
      expect(_ok('Authorization: Bearer $_access').access, _access);
      expect(_ok('authorization: bearer $_access').access, _access);
    });

    test('DevTools "Copy as cURL"', () {
      final curl =
          "curl 'https://exodus.stockbit.com/emitten/ABCD/profile' \\\n"
          "  -H 'accept: application/json' \\\n"
          "  -H 'authorization: Bearer $_access' \\\n"
          "  -H 'origin: https://stockbit.com'";
      expect(_ok(curl).access, _access);
    });

    test('login answer: data.login.token_data.{access,refresh}', () {
      final body = jsonEncode({
        'message': 'ok',
        'data': {
          'login': {
            'token_data': {
              'access': {'token': _access, 'expired_at': 'x'},
              'refresh': {'token': _refresh},
            },
          },
        },
      });
      final t = _ok(body);
      expect(t.access, _access);
      expect(t.refresh, _refresh);
    });

    test('refresh answer: data.{access,refresh}', () {
      final t = _ok(
        jsonEncode({
          'data': {
            'access': {'token': _access},
            'refresh': {'token': _refresh},
          },
        }),
      );
      expect(t.access, _access);
      expect(t.refresh, _refresh);
    });

    test('only a refresh token is a valid pair', () {
      final t = _ok(
        jsonEncode({
          'data': {
            'refresh': {'token': _refresh},
          },
        }),
      );
      expect(t.access, isNull);
      expect(t.refresh, _refresh);
    });

    test('finds the pair inside arrays, up to depth 6 only', () {
      final inList = jsonEncode({
        'items': [
          {
            'x': {
              'access': {'token': _access},
            },
          },
        ],
      });
      expect(_ok(inList).access, _access);

      Object deep = {
        'access': {'token': _access},
      };
      for (var i = 0; i < 7; i++) {
        deep = {'n': deep};
      }
      expect(parseStockbitInput(jsonEncode(deep)), isA<StockbitUnrecognized>());
      Object shallow = {
        'access': {'token': _access},
      };
      for (var i = 0; i < 6; i++) {
        shallow = {'n': shallow};
      }
      expect(parseStockbitInput(jsonEncode(shallow)), isA<StockbitParsed>());
    });

    test('new_device without token_data waits for verification', () {
      final r = parseStockbitInput(
        jsonEncode({
          'data': {
            'new_device': true,
            'login': {'token': 'x'},
          },
        }),
      );
      expect(r, isA<StockbitPending>());
      expect(stockbitPendingMessage, contains('OTP'));
    });

    test('new_device WITH a pair is parsed as tokens', () {
      final r = parseStockbitInput(
        jsonEncode({
          'new_device': true,
          'data': {
            'login': {
              'token_data': {
                'access': {'token': _access},
              },
            },
          },
        }),
      );
      expect(r, isA<StockbitParsed>());
    });

    test('JSON without a pair is not recognized (no JWT guessing)', () {
      expect(
        parseStockbitInput(jsonEncode({'token': _access, 'note': 'x'})),
        isA<StockbitUnrecognized>(),
      );
      expect(parseStockbitInput('{"a": 1'), isA<StockbitUnrecognized>());
    });

    test('junk and empty', () {
      expect(parseStockbitInput(''), isA<StockbitUnrecognized>());
      expect(parseStockbitInput('halo dunia'), isA<StockbitUnrecognized>());
      expect(parseStockbitInput('Bearer pendek'), isA<StockbitUnrecognized>());
    });
  });

  group('jwtExpiry', () {
    test('reads exp without checking the signature', () {
      expect(jwtExpiry(_access), _exp);
      expect(StockbitTokens(access: _access).accessExpiresAt, _exp);
    });
    test('null when unreadable or without exp', () {
      expect(jwtExpiry('abc'), isNull);
      expect(jwtExpiry('a.b.c'), isNull);
      expect(jwtExpiry(fakeJwt(null)), isNull);
    });
  });

  group('stockbitHealth', () {
    final now = DateTime(2026, 10, 18, 12);
    StockbitTokens t({
      DateTime? access,
      DateTime? refresh,
      bool hasRefresh = false,
    }) => StockbitTokens(
      access: access == null ? null : fakeJwt(access),
      refresh: hasRefresh ? fakeJwt(refresh) : null,
    );

    test('none', () {
      expect(stockbitHealth(null, now), StockbitHealth.none);
      expect(stockbitHealth(const StockbitTokens(), now), StockbitHealth.none);
    });
    test('auto while the refresh token lives', () {
      expect(
        stockbitHealth(
          t(
            access: now.subtract(const Duration(days: 1)),
            hasRefresh: true,
            refresh: now.add(const Duration(days: 5)),
          ),
          now,
        ),
        StockbitHealth.auto,
      );
      // No exp claim on the refresh token: assume it lives.
      expect(stockbitHealth(t(hasRefresh: true), now), StockbitHealth.auto);
    });
    test('an expired refresh token falls back to the access token', () {
      expect(
        stockbitHealth(
          t(
            access: now.add(const Duration(hours: 5)),
            hasRefresh: true,
            refresh: now.subtract(const Duration(days: 1)),
          ),
          now,
        ),
        StockbitHealth.active,
      );
    });
    test('expired / expiring / active', () {
      expect(
        stockbitHealth(
          t(access: now.subtract(const Duration(minutes: 1))),
          now,
        ),
        StockbitHealth.expired,
      );
      expect(
        stockbitHealth(
          t(access: now.add(const Duration(hours: 2, minutes: 59))),
          now,
        ),
        StockbitHealth.expiring,
      );
      expect(
        stockbitHealth(t(access: now.add(const Duration(hours: 3))), now),
        StockbitHealth.active,
      );
      expect(
        stockbitHealth(StockbitTokens(access: fakeJwt(null)), now),
        StockbitHealth.active,
      );
    });
    test('usable', () {
      expect(StockbitHealth.auto.usable, isTrue);
      expect(StockbitHealth.expiring.usable, isTrue);
      expect(StockbitHealth.expired.usable, isFalse);
      expect(StockbitHealth.none.usable, isFalse);
    });
  });
}
