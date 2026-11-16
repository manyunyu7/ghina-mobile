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

  static Future<void> showInbox(Map item, {required String baseUrl}) async {
    try {
      final office = item['office']?.toString();
      final route = office == null || office.isEmpty
          ? '/kantor'
          : '/kantor/o/${Uri.encodeComponent(office)}';
      // Only navigates to freshly loaded inbox; notifications never approve an action.
      await _plugin.show(
        id: 8500000 + ('${item['id']}'.hashCode & 0xfffff),
        title: '${item['who'] ?? 'Agen'} menunggu izin',
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
