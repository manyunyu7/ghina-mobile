/// Killa — the personal Claude agent (`docs/killa.md`). Online-only: nothing
/// here is stored or synced locally.
library;

import 'dart:typed_data';

/// Wire value that clears the persisted model back to the engine default.
const killaDefaultModel = 'default';

/// The engine's persisted model (`GET/POST /api/mobile/killa/model`), shared
/// with the WhatsApp chat. [model] null = the engine default.
final class KillaModelSetting {
  const KillaModelSetting({this.model, this.options = const []});

  final String? model;

  /// Selectable values offered by the server.
  final List<String> options;

  /// [model] with null shown as [killaDefaultModel].
  String get active => model ?? killaDefaultModel;

  KillaModelSetting withModel(String? m) =>
      KillaModelSetting(model: m, options: options);
}

enum KillaRole { user, assistant, system }

/// Where a message was sent from.
enum KillaChannel { app, wa }

/// An attachment of a message. `upload` = a user's file under `/uploads/…`
/// (public); `engine` = an agent output path, served by the Bearer media proxy.
final class KillaAttachment {
  const KillaAttachment({
    required this.path,
    required this.name,
    required this.isImage,
    required this.fromEngine,
  });

  final String path;
  final String name;

  /// `kind: "image"` (else `"file"`).
  final bool isImage;

  /// `source: "engine"` (else `"upload"`).
  final bool fromEngine;

  bool get isPdf => name.toLowerCase().endsWith('.pdf');
}

final class KillaMessage {
  const KillaMessage({
    required this.id,
    required this.role,
    required this.body,
    required this.createdAt,
    this.model,
    this.channel = KillaChannel.app,
    this.attachments = const [],
  });

  final String id;
  final KillaRole role;

  /// Markdown for assistant replies; may be `""` when only files.
  final String body;

  /// `fable | opus | sonnet | haiku`, null = engine default.
  final String? model;
  final KillaChannel channel;
  final List<KillaAttachment> attachments;
  final DateTime createdAt;
}

/// One page of the chat log, oldest first. [nextBefore] = the `before` cursor
/// of the previous (older) page; null = the start was reached.
final class KillaMessagePage {
  const KillaMessagePage({required this.messages, this.nextBefore});
  final List<KillaMessage> messages;
  final String? nextBefore;
}

/// Answer of `POST chat`.
final class KillaSendResult {
  const KillaSendResult({required this.userMessage, required this.reply});
  final KillaMessage userMessage;
  final KillaMessage reply;
}

/// A file to send with a chat message (≤ 3; JPEG/PNG/WebP/GIF/PDF, ≤ 8 MB).
final class KillaOutgoingMedia {
  const KillaOutgoingMedia({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.startsWith('image/');
}

/// A raw media file fetched through the media proxy.
final class KillaMediaFile {
  const KillaMediaFile({required this.bytes, this.contentType, this.localPath});
  final Uint8List bytes;
  final String? contentType;

  /// Cached copy on the device (for the photo viewer / opening a file), if
  /// it could be written.
  final String? localPath;

  bool get isImage => contentType?.startsWith('image/') ?? false;
}

// ---------------------------------------------------------------- workspace

final class KillaFileEntry {
  const KillaFileEntry({required this.name, required this.isDir, this.size});

  final String name;
  final bool isDir;

  /// Bytes (files); null when unknown.
  final int? size;
}

final class KillaDirListing {
  const KillaDirListing({required this.path, required this.entries});

  /// `""` = workspace root.
  final String path;

  /// Directories first, then files, each by name.
  final List<KillaFileEntry> entries;
}

final class KillaFileContent {
  const KillaFileContent({required this.path, required this.content});
  final String path;
  final String content;

  bool get isMarkdown {
    final p = path.toLowerCase();
    return p.endsWith('.md') || p.endsWith('.markdown');
  }
}

final class KillaCommit {
  const KillaCommit({
    required this.hash,
    required this.subject,
    this.date,
    this.author,
  });

  final String hash;
  final String subject;
  final DateTime? date;
  final String? author;

  String get shortHash => hash.length > 7 ? hash.substring(0, 7) : hash;
}

// ---------------------------------------------------------------- reminders

/// A reminder scheduled by the agent ("Pengingat Killa"; fires on WhatsApp /
/// the engine, not as a local notification).
final class KillaReminder {
  const KillaReminder({
    required this.id,
    required this.text,
    this.spec,
    this.nextAt,
  });

  final String id;
  final String text;

  /// Schedule as written (`"every day 07:00"`, …).
  final String? spec;
  final DateTime? nextAt;
}

// ---------------------------------------------------------------- usage

final class KillaUsageTotals {
  const KillaUsageTotals({
    this.turns = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.costUsd = 0,
  });

  final int turns;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;

  /// API-price estimate, not a bill.
  final double costUsd;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens;
}

final class KillaUsageDay {
  const KillaUsageDay({required this.date, required this.totals});

  /// `YYYY-MM-DD`.
  final String date;
  final KillaUsageTotals totals;
}

final class KillaUsage {
  const KillaUsage({
    required this.days,
    required this.byModel,
    required this.total,
    this.since,
  });

  final String? since;

  /// Oldest first.
  final List<KillaUsageDay> days;
  final Map<String, KillaUsageTotals> byModel;
  final KillaUsageTotals total;
}

// ---------------------------------------------------------------- errors

enum KillaErrorKind {
  /// 403 `{"error":"forbidden"}`: this account isn't allowlisted.
  forbidden,

  /// 401: the session expired.
  unauthorized,

  /// 503: Killa isn't configured / the engine is off.
  engineOff,

  /// 504 or a client timeout: the engine took too long (the reply may still
  /// be recorded).
  timeout,

  /// 502: the engine failed or is unreachable.
  engineError,

  /// 413: file too large.
  tooLarge,

  /// 415: unsupported file type / not a text file.
  unsupported,

  /// 400: invalid input.
  invalid,

  /// 404.
  notFound,

  /// No connection.
  network,
  unknown,
}

/// What every Killa call throws. [message] is friendly Indonesian copy.
final class KillaException implements Exception {
  const KillaException(this.kind, this.message, {this.status});

  final KillaErrorKind kind;
  final String message;
  final int? status;

  @override
  String toString() => 'KillaException($kind, $status): $message';
}
