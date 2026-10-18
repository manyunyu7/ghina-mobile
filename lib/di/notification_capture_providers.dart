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

/// Page of the log: filter + how many rows to show ("Muat lagi" grows it).
typedef NotificationLogQuery = ({NotificationLogFilter filter, int limit});

final watchCapturedNotificationsProvider = StreamProvider.autoDispose
    .family<List<CapturedNotification>, NotificationLogQuery>(
      (ref, q) => WatchCapturedNotifications(
        ref.watch(capturedNotificationRepositoryProvider),
      )(q.filter, limit: q.limit),
    );

/// Apps under a filter (its app ignored), most notifications first.
final watchNotificationSourcesProvider = StreamProvider.autoDispose
    .family<List<NotificationSource>, NotificationLogFilter>(
      (ref, f) => WatchNotificationSources(
        ref.watch(capturedNotificationRepositoryProvider),
      )(f),
    );

/// Entries per local day under a filter, oldest first.
final watchNotificationDayCountsProvider = StreamProvider.autoDispose
    .family<List<NotificationDayCount>, NotificationLogFilter>(
      (ref, f) => WatchNotificationDayCounts(
        ref.watch(capturedNotificationRepositoryProvider),
      )(f),
    );

/// `(id)` → deletes one log entry.
final deleteCapturedNotificationProvider = Provider<DeleteCapturedNotification>(
  (ref) => DeleteCapturedNotification(
    ref.watch(capturedNotificationRepositoryProvider),
  ),
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

/// `()` → reposts deleted from the existing log.
final removeNotificationRepostsProvider = Provider<RemoveNotificationReposts>(
  (ref) => RemoveNotificationReposts(
    ref.watch(capturedNotificationRepositoryProvider),
  ),
);

/// `(filter)` → the log under the filter as JSON + row count.
final exportCapturedNotificationsProvider =
    Provider<ExportCapturedNotifications>(
      (ref) => ExportCapturedNotifications(
        ref.watch(capturedNotificationRepositoryProvider),
        ref.watch(clockProvider),
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
