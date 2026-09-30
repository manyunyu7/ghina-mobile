/// JSON of the Killa mobile API (`docs/killa.md` → "Mobile API"), parsed
/// leniently: a missing/invalid field falls back to a default, an unusable
/// item is skipped.
library;

import 'dart:convert';

import '../../domain/entities/killa.dart';
import 'wire.dart' show Json;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num && v.isFinite ? v.round() : 0;
double _double(Object? v) => v is num && v.isFinite ? v.toDouble() : 0;
DateTime? _dateN(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

Json _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Object?> _list(Object? v) => v is List ? v : const [];

KillaRole _role(Object? v) => switch (v) {
  'assistant' => KillaRole.assistant,
  'system' => KillaRole.system,
  _ => KillaRole.user,
};

KillaAttachment? killaAttachmentFromWire(Object? v) {
  if (v is String && v.isNotEmpty) {
    // Old rows: a bare URL/path.
    final name = v.split('/').last;
    return KillaAttachment(
      path: v,
      name: name,
      isImage: _looksLikeImage(name),
      fromEngine: !v.startsWith('/uploads/'),
    );
  }
  final j = _map(v);
  final path = _strN(j['path']);
  if (path == null) return null;
  final name = _strN(j['name']) ?? path.split('/').last;
  return KillaAttachment(
    path: path,
    name: name,
    isImage: j['kind'] == null ? _looksLikeImage(name) : j['kind'] == 'image',
    fromEngine: j['source'] == null
        ? !path.startsWith('/uploads/')
        : j['source'] == 'engine',
  );
}

bool _looksLikeImage(String name) =>
    RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false).hasMatch(name);

KillaMessage? killaMessageFromWire(Object? v) {
  final j = _map(v);
  final id = _strN(j['id']);
  if (id == null) return null;
  return KillaMessage(
    id: id,
    role: _role(j['role']),
    body: _str(j['body']),
    model: _strN(j['model']),
    channel: j['channel'] == 'wa' ? KillaChannel.wa : KillaChannel.app,
    attachments: [
      for (final a in _list(j['attachments'])) ?killaAttachmentFromWire(a),
    ],
    createdAt: _dateN(j['createdAt']) ?? DateTime.now(),
  );
}

KillaMessagePage killaChatPageFromWire(Object? v) {
  final j = _map(v);
  return KillaMessagePage(
    messages: [for (final m in _list(j['messages'])) ?killaMessageFromWire(m)],
    nextBefore: _strN(j['nextBefore']),
  );
}

KillaSendResult killaSendResultFromWire(Object? v) {
  final j = _map(v);
  final user = killaMessageFromWire(j['userMessage']);
  final reply = killaMessageFromWire(j['reply']);
  if (user == null || reply == null) {
    throw const FormatException('Jawaban Killa tidak lengkap');
  }
  return KillaSendResult(userMessage: user, reply: reply);
}

/// `{divider}` of `POST chat/new` (or a bare message).
KillaMessage? killaDividerFromWire(Object? v) {
  final j = _map(v);
  return killaMessageFromWire(j['divider'] ?? j);
}

Json killaMediaToWire(KillaOutgoingMedia m) => {
  'name': m.name,
  'mimeType': m.mimeType,
  'dataBase64': base64Encode(m.bytes),
};

KillaDirListing killaDirFromWire(Object? v, {String requested = ''}) {
  final j = _map(v);
  final entries =
      <KillaFileEntry>[
        for (final e in _list(j['entries']))
          if (_strN(_map(e)['name']) case final name?)
            KillaFileEntry(
              name: name,
              isDir: _map(e)['type'] == 'dir',
              size: _map(e)['size'] is num ? _int(_map(e)['size']) : null,
            ),
      ]..sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  return KillaDirListing(
    path: j['path'] is String ? j['path'] as String : requested,
    entries: entries,
  );
}

KillaFileContent killaFileFromWire(Object? v, {String requested = ''}) {
  final j = _map(v);
  return KillaFileContent(
    path: _strN(j['path']) ?? requested,
    content: _str(j['content']),
  );
}

List<KillaCommit> killaCommitsFromWire(Object? v) => [
  for (final c in _list(_map(v)['commits']))
    if (_strN(_map(c)['hash']) case final hash?)
      KillaCommit(
        hash: hash,
        subject: _str(_map(c)['subject']),
        date: _dateN(_map(c)['date']),
        author: _strN(_map(c)['author']),
      ),
];

List<KillaReminder> killaRemindersFromWire(Object? v) {
  final out = <KillaReminder>[];
  for (final r in _list(_map(v)['reminders'])) {
    final j = _map(r);
    final id = j['id'] is num ? '${_int(j['id'])}' : _strN(j['id']);
    if (id == null) continue;
    final next = j['nextAt'];
    out.add(
      KillaReminder(
        id: id,
        text: _str(j['text']),
        spec: _strN(j['spec']),
        nextAt: next is num && next.isFinite
            ? DateTime.fromMillisecondsSinceEpoch(next.round())
            : _dateN(next),
      ),
    );
  }
  out.sort((a, b) {
    final x = a.nextAt, y = b.nextAt;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return x.compareTo(y);
  });
  return out;
}

KillaUsageTotals killaTotalsFromWire(Object? v) {
  final j = _map(v);
  return KillaUsageTotals(
    turns: _int(j['turns']),
    inputTokens: _int(j['inputTokens']),
    outputTokens: _int(j['outputTokens']),
    cacheReadTokens: _int(j['cacheReadTokens']),
    cacheCreationTokens: _int(j['cacheCreationTokens']),
    costUsd: _double(j['costUsd']),
  );
}

KillaUsage killaUsageFromWire(Object? v) {
  final j = _map(v);
  final days = <KillaUsageDay>[
    for (final d in _list(j['days']))
      if (_strN(_map(d)['date']) case final date?)
        KillaUsageDay(date: date, totals: killaTotalsFromWire(d)),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return KillaUsage(
    since: _strN(j['since']),
    days: days,
    byModel: {
      for (final e in _map(j['byModel']).entries)
        e.key: killaTotalsFromWire(e.value),
    },
    total: killaTotalsFromWire(j['total']),
  );
}

/// `{model: string|null, options: string[]}` of `GET/POST model` (POST
/// answers `{ok, model}`: [options] is empty then). `"default"` / empty =
/// null.
KillaModelSetting killaModelFromWire(Object? v) {
  final j = _map(v);
  final m = _strN(j['model']);
  return KillaModelSetting(
    model: m == killaDefaultModel ? null : m,
    options: <String>{for (final o in _list(j['options'])) ?_strN(o)}.toList(),
  );
}
