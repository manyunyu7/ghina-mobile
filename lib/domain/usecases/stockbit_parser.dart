/// Reads what the user pasted from Stockbit (pure Dart, a port of the
/// server's parser): a bare JWT, `Bearer x`, an `Authorization:` header line,
/// DevTools "Copy as cURL" or a JSON body. Nothing is sent anywhere here.
library;

import 'dart:convert';

import '../entities/stockbit.dart';

/// Outcome of [parseStockbitInput].
sealed class StockbitParse {
  const StockbitParse();
}

/// Tokens were found (either may be null, never both).
final class StockbitParsed extends StockbitParse {
  const StockbitParsed(this.tokens);
  final StockbitTokens tokens;
}

/// A login answer that still waits for the OTP / device approval.
final class StockbitPending extends StockbitParse {
  const StockbitPending();
}

/// Neither a token nor a token pair in the text.
final class StockbitUnrecognized extends StockbitParse {
  const StockbitUnrecognized();
}

/// User-facing text for [StockbitPending].
const stockbitPendingMessage =
    'Selesaikan OTP/persetujuan dulu, lalu tempel respons verify yang terakhir.';

const _maxDepth = 6;
final _jwt = RegExp(r'^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*$');
final _bearer = RegExp(
  r'(?:authorization["\x27]?\s*[:=]\s*["\x27]?\s*)?bearer\s+([A-Za-z0-9._~+/=-]+)',
  caseSensitive: false,
);

StockbitParse parseStockbitInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return const StockbitUnrecognized();

  if (text.startsWith('{') || text.startsWith('[')) {
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      json = null;
    }
    if (json != null) {
      final tokens = _findPair(json);
      if (tokens != null) return StockbitParsed(tokens);
      if (text.contains('"new_device"') && !text.contains('"token_data"')) {
        return const StockbitPending();
      }
    }
    // Never regex-guess JWTs inside JSON.
    return const StockbitUnrecognized();
  }

  if (_jwt.hasMatch(text)) return StockbitParsed(StockbitTokens(access: text));

  // `Authorization: Bearer x`, `Bearer x`, or a cURL with such a header.
  for (final m in _bearer.allMatches(text)) {
    final t = m.group(1)!;
    if (_jwt.hasMatch(t)) return StockbitParsed(StockbitTokens(access: t));
  }
  return const StockbitUnrecognized();
}

/// Breadth-first search (depth ≤ 6) for the first object with an
/// `access.token` and/or `refresh.token`.
StockbitTokens? _findPair(Object? root) {
  var level = <Object?>[root];
  for (var depth = 0; depth <= _maxDepth && level.isNotEmpty; depth++) {
    final next = <Object?>[];
    for (final node in level) {
      if (node is Map) {
        final access = _token(node['access']);
        final refresh = _token(node['refresh']);
        if (access != null || refresh != null) {
          return StockbitTokens(access: access, refresh: refresh);
        }
        next.addAll(node.values);
      } else if (node is List) {
        next.addAll(node);
      }
    }
    level = next;
  }
  return null;
}

String? _token(Object? v) {
  if (v is Map) {
    final t = v['token'];
    if (t is String && t.trim().isNotEmpty) return t.trim();
  }
  return null;
}

/// `exp` of a JWT as a local time, without checking the signature; null when
/// the token isn't a readable JWT.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final json = jsonDecode(payload);
    final exp = json is Map ? json['exp'] : null;
    if (exp is! num || !exp.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
  } catch (_) {
    return null;
  }
}

/// Health of the on-device session at [now] (inject the clock).
StockbitHealth stockbitHealth(StockbitTokens? tokens, DateTime now) {
  if (tokens == null || tokens.isEmpty) return StockbitHealth.none;
  if (tokens.refresh != null) {
    final rexp = tokens.refreshExpiresAt;
    if (rexp == null || rexp.isAfter(now)) return StockbitHealth.auto;
  }
  if (tokens.access == null) return StockbitHealth.expired;
  final exp = tokens.accessExpiresAt;
  if (exp == null) return StockbitHealth.active;
  final left = exp.difference(now);
  if (left <= Duration.zero) return StockbitHealth.expired;
  if (left < stockbitExpiringSoon) return StockbitHealth.expiring;
  return StockbitHealth.active;
}

/// An access token with less time left than this counts as "segera berakhir".
const stockbitExpiringSoon = Duration(hours: 3);
