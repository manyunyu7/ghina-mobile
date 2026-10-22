import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/usecases/prayer_reminder_rules.dart'
    show isPrayerNotificationId;
import '../datasources/remote/api_client.dart';
import 'notification_gateway.dart';
import 'reminder_codec.dart';

/// A notice from Kantor Claude (`GET /api/mobile/kantor/notices`).
class KantorNotice {
  const KantorNotice({
    required this.id,
    required this.title,
    required this.body,
    this.event,
    this.office,
    this.path,
    this.sid,
  });

  final String id;
  final String title;
  final String body;

  /// `permission` | `question` | `meeting_done` | `pratinjau` (free text).
  final String? event;

  final String? office;

  /// Legacy Kantor hash route (informational).
  final String? path;
  final String? sid;

  /// Route handed to go_router: the agent session for permission/question,
  /// the meetings tab for `meeting_done`, the item for `pratinjau`, else
  /// Kantor home.
  String get route {
    final o = office;
    if (o == null || o.isEmpty) return '/kantor';
    final base = '/kantor/o/${Uri.encodeComponent(o)}';
    if (event == 'meeting_done') return '$base?tab=rapat';
    if (event == 'pratinjau') {
      // The item id rides in the legacy hash route `#/o/<office>/pratinjau/<id>`.
      final m = RegExp(r'/pratinjau/([^/?#]+)').firstMatch(path ?? '');
      final id = m?.group(1);
      return id == null || id.isEmpty
          ? '$base/pratinjau'
          : '$base/pratinjau/${Uri.encodeComponent(Uri.decodeComponent(id))}';
    }
    final s = sid;
    if (s != null && s.isNotEmpty) return '$base/s/${Uri.encodeComponent(s)}';
    return '/kantor';
  }

  /// Notification payload; `r` is read by [notificationRouteOf].
  String get payload => jsonEncode({
    'kind': 'kantor',
    'r': route,
    'office': ?office,
    'sid': ?sid,
    'n': id,
  });

  static KantorNotice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || title is! String) return null;
    String? str(String k) => raw[k] is String ? raw[k] as String : null;
    return KantorNotice(
      id: id,
      title: title,
      body: str('body') ?? '',
      event: str('event'),
      office: str('office'),
      path: str('path'),
      sid: str('sid'),
    );
  }
}

/// Polls the Ghina server for Kantor Claude notices and shows each as a
/// notification (channel "Kantor Claude"). There is no push channel (no FCM):
/// the owner calls [poll] while the app is in the foreground and on resume.
///
/// The first poll only records the server cursor (no history replay). The
/// cursor is kept in shared_preferences, so a notice is shown at most once per
/// install.
class KantorNoticePoller {
  KantorNoticePoller(this._client, this._gateway, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ApiClient _client;
  final NotificationGateway _gateway;
  final DateTime Function() _now;

  /// While the endpoint answers 404 (server not deployed yet) polls are
  /// skipped: the first wait is [missingBackoffStart], doubling up to
  /// [missingBackoffMax]. One log line, then silence.
  static const missingBackoffStart = Duration(minutes: 2);
  static const missingBackoffMax = Duration(minutes: 30);
  DateTime? _skipUntil;
  Duration _missingWait = Duration.zero;

  static const cursorKey = 'kantor.notice_cursor';

  bool _busy = false;
  Future<void>? _init;

  /// One poll; never throws. Returns how many notifications were shown.
  Future<int> poll() async {
    if (_busy) return 0;
    final skip = _skipUntil;
    if (skip != null && _now().isBefore(skip)) return 0;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final after = prefs.getInt(cursorKey);
      final r = await _client.dio.get<Object?>(
        '/api/mobile/kantor/notices',
        queryParameters: {'after': ?after},
      );
      final data = r.data;
      if (data is! Map) return 0;
      final notices = [
        for (final n in (data['notices'] as List? ?? const []))
          ?KantorNotice.tryParse(n),
      ];
      var shown = 0;
      if (notices.isNotEmpty) {
        await (_init ??= _gateway.initialize((_) {}));
        for (final n in notices) {
          try {
            await _gateway.show(
              NotificationRequest(
                id: idFor(n.id),
                title: n.title,
                body: n.body,
                fireAt: DateTime.now(),
                payload: n.payload,
                exact: false,
                channel: NotificationChannelKind.kantor,
              ),
            );
            shown++;
          } catch (e) {
            debugPrint('Kantor notice not shown: $e');
          }
        }
      }
      final cursor = data['cursor'];
      if (cursor is int) await prefs.setInt(cursorKey, cursor);
      _skipUntil = null;
      _missingWait = Duration.zero;
      return shown;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) {
        if (_missingWait == Duration.zero) {
          debugPrint(
            'Kantor poll: endpoint not available yet (404); '
            'retrying quietly with backoff',
          );
          _missingWait = missingBackoffStart;
        } else {
          _missingWait = _missingWait * 2 > missingBackoffMax
              ? missingBackoffMax
              : _missingWait * 2;
        }
        _skipUntil = _now().add(_missingWait);
      } else {
        debugPrint('Kantor poll failed: ${code ?? e.type}');
      }
      return 0;
    } catch (e) {
      debugPrint('Kantor poll failed: $e');
      return 0;
    } finally {
      _busy = false;
    }
  }

  /// Stable notification id, kept clear of Reminder Sholat's id block.
  @visibleForTesting
  static int idFor(String noticeId) {
    var id = reminderNotificationId('kantor:$noticeId');
    while (isPrayerNotificationId(id)) {
      id = (id + 1) & kMaxNotificationId;
    }
    return id;
  }
}
