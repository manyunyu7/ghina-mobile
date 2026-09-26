import '../entities/entities.dart';

/// Port for the device notification listener ("Log Notifikasi"). Android only:
/// iOS has no API to read other apps' notifications, so [isSupported] is false
/// there and every call is a no-op.
///
/// Notification access is not a runtime permission: the user grants it in
/// Settings › Notification access ([openAccessSettings]).
abstract interface class DeviceNotificationListener {
  bool get isSupported;

  /// Notification access granted to this app.
  Future<bool> hasAccess();

  /// Opens Settings › Notification access.
  Future<void> openAccessSettings();

  /// Starts capturing (needs access). False when it couldn't start.
  Future<bool> start();

  /// Stops capturing (the listener service is disabled until [start]).
  Future<void> stop();

  Future<bool> isRunning();

  /// Launchable apps, sorted by label (for picking a rule's source app).
  Future<List<InstalledApp>> installedApps();

  /// The launcher label of [packageName], or null when unknown.
  Future<String?> appLabel(String packageName);
}
