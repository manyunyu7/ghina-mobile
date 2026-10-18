import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/stockbit.dart';
import '../../domain/services/stockbit_session_store.dart';

/// Keychain / Keystore backed store of the Stockbit tokens (device only).
final class SecureStockbitSessionStore implements StockbitSessionStore {
  SecureStockbitSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ghina.stockbit';
  final FlutterSecureStorage _storage;

  @override
  Future<StockbitTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final a = j['access'];
      final r = j['refresh'];
      return StockbitTokens(
        access: a is String && a.isNotEmpty ? a : null,
        refresh: r is String && r.isNotEmpty ? r : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StockbitTokens tokens) => _storage.write(
    key: _key,
    value: jsonEncode({'access': tokens.access, 'refresh': tokens.refresh}),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
