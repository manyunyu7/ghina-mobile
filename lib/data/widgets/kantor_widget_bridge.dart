import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../datasources/remote/kantor_api.dart';
import 'kantor_widget_summary.dart';

/// Android home-screen widget "Kantor": the app (and a periodic background
/// task) pushes a [KantorWidgetSummary] into the widget's storage and asks it
/// to redraw. The widget itself is native (`KantorWidgetProvider.kt`).
///
/// Tokens never leave secure storage for the widget: the summary holds agent
/// names and numbers only, and the background task reads the token from secure
/// storage itself (a fresh headless engine, plugins registered by WorkManager).
abstract final class KantorWidgetBridge {
  static const providerName = 'KantorWidgetProvider';
  static const _dataKey = 'kantor_summary';
  static const _taskName = 'ghina.kantor.widget.refresh';
  static const _channel = MethodChannel('com.henryaugusta.ghina/kantor_widget');

  static bool get supported => Platform.isAndroid;

  /// One fetch of `/api/state` → widget. Never throws: a failed fetch marks
  /// the widget offline (keeping the last numbers).
  static Future<void> refresh(KantorConfig config, {DateTime? now}) async {
    if (!supported || !config.ready) return;
    final at = now ?? DateTime.now();
    String payload;
    try {
      final state = await KantorApi(config).get('/api/state');
      payload = KantorWidgetSummary.fromState(
        Map<String, dynamic>.from(state as Map),
        now: at,
      ).encode();
    } catch (_) {
      final previous = await HomeWidget.getWidgetData<String>(_dataKey);
      payload = KantorWidgetSummary.encodeOffline(previous: previous, now: at);
    }
    await _push(payload);
  }

  /// Settings were cleared: show the "open Ghina" state.
  static Future<void> clear() async {
    if (!supported) return;
    await _push('');
  }

  static Future<void> _push(String payload) async {
    try {
      await HomeWidget.saveWidgetData<String>(_dataKey, payload);
      await HomeWidget.updateWidget(androidName: providerName);
    } catch (_) {
      // No widget placed / plugin missing: nothing to update.
    }
  }

  /// Registers the ≥15 minute background refresh (WorkManager's floor).
  /// Idempotent. Needs the network; WorkManager defers it until then.
  static Future<void> scheduleBackground() async {
    if (!supported) return;
    try {
      await Workmanager().initialize(kantorWidgetDispatcher);
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  static Future<void> cancelBackground() async {
    if (!supported) return;
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (_) {}
  }

  /// A tap on the widget leaves its target route with the Android activity;
  /// returns (and clears) the one that cold-started the app.
  static Future<String?> takeLaunchRoute() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('takeRoute');
    } catch (_) {
      return null;
    }
  }

  /// Taps on the widget while the app is already running.
  static void onRoute(void Function(String route) handler) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'route' && call.arguments is String) {
        handler(call.arguments as String);
      }
    });
  }
}

/// WorkManager entry point (headless isolate).
@pragma('vm:entry-point')
void kantorWidgetDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      final config = await KantorConfigStore().load();
      await KantorWidgetBridge.refresh(config);
    } catch (_) {}
    return true;
  });
}
