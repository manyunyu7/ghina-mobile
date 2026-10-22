import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One captured error (Diagnostik › Log error).
@immutable
class ErrorEntry {
  const ErrorEntry({
    required this.time,
    required this.kind,
    required this.message,
    required this.stack,
    this.route,
    this.count = 1,
  });

  final DateTime time;

  /// Active go_router location when it happened, if known.
  final String? route;

  /// Exception type; framework errors add the library ("widgets library"),
  /// uncaught async errors are `async · <type>`.
  final String kind;
  final String message;

  /// Shortened stack trace.
  final String stack;

  /// Consecutive repeats folded into this entry (a broken build repeats per frame).
  final int count;

  ErrorEntry withCount(int c, DateTime t) => ErrorEntry(
    time: t,
    kind: kind,
    message: message,
    stack: stack,
    route: route,
    count: c,
  );

  Map<String, Object?> toJson() => {
    't': time.toIso8601String(),
    'r': route,
    'k': kind,
    'm': message,
    's': stack,
    'c': count,
  };

  static ErrorEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final t = DateTime.tryParse('${raw['t']}');
    if (t == null) return null;
    return ErrorEntry(
      time: t,
      route: raw['r'] is String ? raw['r'] as String : null,
      kind: '${raw['k'] ?? 'error'}',
      message: '${raw['m'] ?? ''}',
      stack: '${raw['s'] ?? ''}',
      count: raw['c'] is int ? raw['c'] as int : 1,
    );
  }

  /// Plain text for copy / share.
  String toText() {
    final b = StringBuffer()
      ..writeln('Waktu : ${time.toIso8601String()}')
      ..writeln('Rute  : ${route ?? '-'}')
      ..writeln('Jenis : $kind${count > 1 ? ' (x$count)' : ''}')
      ..writeln('Pesan : $message');
    if (stack.isNotEmpty) b.writeln('Stack :\n$stack');
    return b.toString();
  }
}

/// Global error capture: the last [maxEntries] errors, kept in memory and in a
/// small JSON file so they survive a crash. Install once from `main()`.
class ErrorLog extends ChangeNotifier {
  ErrorLog({Future<File> Function()? file}) : _file = file ?? _defaultFile;

  static final ErrorLog instance = ErrorLog();

  static const maxEntries = 50;
  static const _stackLines = 8;

  /// Reads the active route; set by the app shell (go_router).
  String? Function()? routeProbe;

  final Future<File> Function() _file;
  final _entries = <ErrorEntry>[]; // newest first
  Future<void> _writing = Future<void>.value();
  bool _loaded = false;

  List<ErrorEntry> get entries => List.unmodifiable(_entries);

  static Future<File> _defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/ghina_error_log.json');
  }

  /// Loads the saved entries (kept ahead of any recorded meanwhile).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      final saved = [for (final e in raw) ?ErrorEntry.tryParse(e)];
      _entries.addAll(saved);
      _trim();
      notifyListeners();
    } catch (_) {
      // A corrupt log file must never break startup.
    }
  }

  /// Records an error: one `GhinaError` line in logcat and an entry in the file.
  void record(Object error, StackTrace? stack, {String? kind}) {
    try {
      final now = DateTime.now();
      final msg = _oneLine('$error');
      final k = kind ?? error.runtimeType.toString();
      String? route;
      try {
        route = routeProbe?.call();
      } catch (_) {}
      debugPrint('GhinaError [$k]${route == null ? '' : ' @ $route'}: $msg');
      final prev = _entries.isEmpty ? null : _entries.first;
      if (prev != null && prev.kind == k && prev.message == msg) {
        _entries[0] = prev.withCount(prev.count + 1, now);
      } else {
        _entries.insert(
          0,
          ErrorEntry(
            time: now,
            route: route,
            kind: k,
            message: msg,
            stack: _shortStack(stack),
            count: 1,
          ),
        );
        _trim();
      }
      notifyListeners();
      _persist();
    } catch (_) {
      // Capturing an error must never throw another one.
    }
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> remove(ErrorEntry e) async {
    _entries.remove(e);
    notifyListeners();
    await _persist();
  }

  /// Completes when pending writes are done (tests).
  Future<void> flush() => _writing;

  void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  Future<void> _persist() {
    final snapshot = jsonEncode([for (final e in _entries) e.toJson()]);
    return _writing = _writing.then((_) async {
      try {
        final f = await _file();
        await f.parent.create(recursive: true);
        await f.writeAsString(snapshot, flush: true);
      } catch (_) {}
    });
  }

  static String _oneLine(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s*\n\s*'), ' | ');
    return t.length > 600 ? '${t.substring(0, 600)}…' : t;
  }

  static String _shortStack(StackTrace? st) {
    if (st == null) return '';
    final lines = st
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(_stackLines);
    return lines.join('\n');
  }

  /// Hooks Flutter / platform errors into [instance]. The previous handlers
  /// still run, so the default console dump is unchanged.
  static void install() {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      instance.record(
        details.exception,
        details.stack,
        kind: details.library == null
            ? details.exception.runtimeType.toString()
            : '${details.exception.runtimeType} · ${details.library}',
      );
      if (prevFlutter != null) {
        prevFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.record(error, stack, kind: 'async · ${error.runtimeType}');
      return prevPlatform?.call(error, stack) ?? false;
    };
  }
}
