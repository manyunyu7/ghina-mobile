import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One dictation event (Diagnostik › Log dikte).
@immutable
class DictationLogEntry {
  const DictationLogEntry({
    required this.time,
    required this.event,
    this.detail = '',
    this.count = 1,
  });

  final DateTime time;

  /// `mulai`, `sesi`, `ulang`, `selesai`, `gagal`, …
  final String event;
  final String detail;

  /// Consecutive identical entries folded together (silent sessions).
  final int count;

  Map<String, Object?> toJson() => {
    't': time.toIso8601String(),
    'e': event,
    'd': detail,
    'c': count,
  };

  static DictationLogEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final t = DateTime.tryParse('${raw['t']}');
    if (t == null) return null;
    return DictationLogEntry(
      time: t,
      event: '${raw['e'] ?? '?'}',
      detail: '${raw['d'] ?? ''}',
      count: raw['c'] is int ? raw['c'] as int : 1,
    );
  }

  String toLine() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = time;
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    return '$stamp $event${count > 1 ? ' x$count' : ''}'
        '${detail.isEmpty ? '' : ' · $detail'}';
  }
}

/// Short ring buffer of dictation session events (start, session end with
/// reason / error code / duration / word count, restarts, stop), so the owner
/// can send it when dictation still misbehaves. Kept apart from [ErrorLog] so
/// routine sessions never push real errors out. Max [maxEntries]; identical
/// consecutive events are folded (`x3`), so silence doesn't flood it.
class DictationLog extends ChangeNotifier {
  DictationLog({Future<File> Function()? file, this.persist = true})
    : _file = file ?? _defaultFile;

  /// In-memory only (tests).
  DictationLog.memory() : _file = _defaultFile, persist = false;

  static final DictationLog instance = DictationLog();

  static const maxEntries = 200;

  final Future<File> Function() _file;
  final bool persist;
  final _entries = <DictationLogEntry>[]; // newest first
  Future<void> _writing = Future<void>.value();
  Timer? _saveTimer;
  bool _loaded = false;

  List<DictationLogEntry> get entries => List.unmodifiable(_entries);

  static Future<File> _defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/ghina_dictation_log.json');
  }

  Future<void> load() async {
    if (_loaded || !persist) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      _entries.addAll([for (final e in raw) ?DictationLogEntry.tryParse(e)]);
      _trim();
      notifyListeners();
    } catch (_) {
      // A corrupt log must never break anything.
    }
  }

  void record(String event, [String detail = '']) {
    try {
      if (!_loaded) unawaited(load());
      final now = DateTime.now();
      final prev = _entries.isEmpty ? null : _entries.first;
      if (prev != null && prev.event == event && prev.detail == detail) {
        _entries[0] = DictationLogEntry(
          time: now,
          event: event,
          detail: detail,
          count: prev.count + 1,
        );
      } else {
        _entries.insert(
          0,
          DictationLogEntry(time: now, event: event, detail: detail),
        );
        _trim();
      }
      debugPrint('GhinaDikte $event${detail.isEmpty ? '' : ' · $detail'}');
      notifyListeners();
      _scheduleSave();
    } catch (_) {}
  }

  /// Plain text, oldest first (copy / share).
  String toText() => _entries.reversed.map((e) => e.toLine()).join('\n');

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }

  /// Completes when pending writes are done (tests).
  Future<void> flush() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      return _save();
    }
    return _writing;
  }

  void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  // Sessions end every few seconds: batch the file writes.
  void _scheduleSave() {
    if (!persist || (_saveTimer?.isActive ?? false)) return;
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() {
    if (!persist) return Future<void>.value();
    final snapshot = jsonEncode([for (final e in _entries) e.toJson()]);
    return _writing = _writing.then((_) async {
      try {
        final f = await _file();
        await f.parent.create(recursive: true);
        await f.writeAsString(snapshot, flush: true);
      } catch (_) {}
    });
  }
}
