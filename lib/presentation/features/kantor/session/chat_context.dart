import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// Stable routing identity without exposing an authentication token in keys or
/// the persisted outbox. A different account on the same URL is a different chat.
String kantorConnectionKey(KantorConfig config) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
          config.token,
        ]),
      ),
    )
    .toString();

typedef KantorChatKey = ({String connection, String office, String sid});

class KantorChatMemory {
  TextEditingValue draft = TextEditingValue.empty;
  double scrollOffset = 0;
}

/// Kept for the lifetime of the app's ProviderScope, including route changes.
/// Drafts intentionally stay in memory rather than being written to disk.
final kantorChatMemoryProvider = Provider(
  (ref) => <KantorChatKey, KantorChatMemory>{},
);

String kantorOpenChatKey(String connection, String office, String sid) =>
    jsonEncode([connection, office, sid]);
