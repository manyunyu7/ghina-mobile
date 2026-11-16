import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Ravel initializes only immediate Kantor notifications. No exact alarms,
/// prayer callbacks, Ghina API credentials, or background notification listener.
abstract final class RavelNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _routes = StreamController<String>.broadcast();
  static String? _launchRoute;
  static Stream<String> get routes => _routes.stream;

  static bool validRoute(String? route) =>
      route != null && (route == '/kantor' || route.startsWith('/kantor/'));

  /// Keeps a notice from one connection from opening an identically named
  /// office on another connection after the owner switches profiles.
  static ({String route, String baseUrl})? targetOf(String? payload) {
    try {
      final value = jsonDecode(payload ?? '');
      if (value is! Map ||
          value['route'] is! String ||
          value['baseUrl'] is! String) {
        return null;
      }
      final route = value['route'] as String;
      if (!validRoute(route)) return null;
      return (route: route, baseUrl: value['baseUrl'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<void> initialize() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_ghina'),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (targetOf(response.payload) != null) {
            _routes.add(response.payload!);
          }
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final route = launch?.notificationResponse?.payload;
        if (targetOf(route) != null) _launchRoute = route;
      }
    } catch (e) {
      debugPrint('Ravel notifications unavailable: ${e.runtimeType}');
    }
  }

  static String? takeLaunchRoute() {
    final route = _launchRoute;
    _launchRoute = null;
    return route;
  }

  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Judul notifikasi izin. Sesi berlabel: "`Nama agen` · `label`" (label
  /// dipotong sekitar 40 karakter); tanpa label: "`Nama agen` menunggu izin".
  static String inboxTitle(Map item, {String? label}) {
    final who = '${item['who'] ?? 'Agen'}';
    final l = label?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (l.isEmpty) return '$who menunggu izin';
    return '$who · ${l.length > 40 ? '${l.substring(0, 39).trimRight()}…' : l}';
  }

  /// Label pemilik sesi milik [item] inbox: dari item itu sendiri bila server
  /// menyertakannya, kalau tidak dari sesi yang sama di [state] (`/api/state`,
  /// data segar yang memicu notifikasi ini).
  static String? inboxLabel(Map? state, Map item) {
    String? of(Object? s) {
      if (s is! Map) return null;
      final k = s['konteks'];
      final l = k is Map ? k['label'] : null;
      final t = l is Map ? '${l['text'] ?? ''}'.trim() : '';
      return t.isEmpty ? null : t;
    }

    final own = of(item) ?? of(item['session']);
    if (own != null) return own;
    final sid = item['sid'];
    if (sid == null || state == null) return null;
    final offices = state['offices'];
    final loose = state['loose'];
    for (final o in [
      if (offices is List) ...offices,
      {'sessions': loose},
    ]) {
      final list = o is Map ? o['sessions'] : null;
      if (list is! List) continue;
      for (final s in list) {
        if (s is Map && s['sid'] == sid) return of(s);
      }
    }
    return null;
  }

  static Future<void> showInbox(
    Map item, {
    required String baseUrl,
    String? label,
  }) async {
    try {
      final office = item['office']?.toString();
      final route = office == null || office.isEmpty
          ? '/kantor'
          : '/kantor/o/${Uri.encodeComponent(office)}';
      // Only navigates to freshly loaded inbox; notifications never approve an action.
      await _plugin.show(
        id: 8500000 + ('${item['id']}'.hashCode & 0xfffff),
        title: inboxTitle(item, label: label),
        body: '${item['summary'] ?? 'Buka Kantor untuk melihat permintaan.'}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'kantor_claude',
            'Kantor',
            icon: 'ic_stat_ghina',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode({'route': route, 'baseUrl': baseUrl}),
      );
    } catch (e) {
      debugPrint('Ravel notice not shown: ${e.runtimeType}');
    }
  }
}
