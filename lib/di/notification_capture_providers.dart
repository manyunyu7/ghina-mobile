/// Composition root, part 5: "Log Notifikasi" (Android notification listener)
/// and the parsing rules that turn notifications into transactions.
///
/// Writes: `await ref.read(saveNotificationRuleProvider)(id, input)` →
/// `Result<NotificationRule>`. Streams: `ref.watch(watchCapturedNotificationsProvider(query))`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import 'core_providers.dart';
import 'usecase_providers.dart' show createTransactionProvider;

export 'core_providers.dart' show deviceNotificationListenerProvider;

// ---------------------------------------------------------------- log

/// Filter of the notification log.
typedef NotificationLogQuery = ({String? packageName, String? search});

final watchCapturedNotificationsProvider = StreamProvider.autoDispose
    .family<List<CapturedNotification>, NotificationLogQuery>(
      (ref, q) => WatchCapturedNotifications(
        ref.watch(capturedNotificationRepositoryProvider),
      )(packageName: q.packageName, search: q.search),
    );

/// Apps in the log (per-app filter chips), most notifications first.
final watchNotificationSourcesProvider =
    StreamProvider.autoDispose<List<NotificationSource>>(
      (ref) => WatchNotificationSources(
        ref.watch(capturedNotificationRepositoryProvider),
      )(),
    );

/// Rows not yet checked against the rules (drives the processor).
final watchUnprocessedNotificationCountProvider =
    StreamProvider.autoDispose<int>(
      (ref) => ref
          .watch(capturedNotificationRepositoryProvider)
          .watchUnprocessedCount(),
    );

/// `({packageName})` → rows deleted.
final clearCapturedNotificationsProvider = Provider<ClearCapturedNotifications>(
  (ref) => ClearCapturedNotifications(
    ref.watch(capturedNotificationRepositoryProvider),
  ),
);

/// Checks pending log rows against the rules and creates transactions.
final processCapturedNotificationsProvider =
    Provider<ProcessCapturedNotifications>((ref) {
      final listener = ref.watch(deviceNotificationListenerProvider);
      return ProcessCapturedNotifications(
        ref.watch(capturedNotificationRepositoryProvider),
        ref.watch(notificationRuleRepositoryProvider),
        ref.watch(walletRepositoryProvider),
        ref.watch(createTransactionProvider),
        listener.appLabel,
      );
    });

/// Launchable apps (rule source picker). Empty on iOS.
final installedAppsProvider = FutureProvider.autoDispose<List<InstalledApp>>(
  (ref) => ref.watch(deviceNotificationListenerProvider).installedApps(),
);

// ---------------------------------------------------------------- rules

final watchNotificationRulesProvider =
    StreamProvider.autoDispose<List<NotificationRule>>(
      (ref) => WatchNotificationRules(
        ref.watch(notificationRuleRepositoryProvider),
      )(),
    );

final watchNotificationRuleProvider = StreamProvider.autoDispose
    .family<NotificationRule?, String>(
      (ref, id) => WatchNotificationRule(
        ref.watch(notificationRuleRepositoryProvider),
      )(id),
    );

/// `(id?, NotificationRuleInput)` → the saved rule.
final saveNotificationRuleProvider = Provider<SaveNotificationRule>(
  (ref) => SaveNotificationRule(
    ref.watch(notificationRuleRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteNotificationRuleProvider = Provider<DeleteNotificationRule>(
  (ref) =>
      DeleteNotificationRule(ref.watch(notificationRuleRepositoryProvider)),
);

/// `(id, enabled)`.
final setNotificationRuleEnabledProvider = Provider<SetNotificationRuleEnabled>(
  (ref) => SetNotificationRuleEnabled(
    ref.watch(notificationRuleRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(presetKey)` → creates the preset's rule (or re-enables it).
final enableNotificationRulePresetProvider =
    Provider<EnableNotificationRulePreset>(
      (ref) => EnableNotificationRulePreset(
        ref.watch(notificationRuleRepositoryProvider),
        ref.watch(saveNotificationRuleProvider),
        ref.watch(setNotificationRuleEnabledProvider),
      ),
    );
