/// Port for copying "Log Notifikasi" to a file that can be pulled over adb from an
/// authorised computer (tool/pull_notification_log.sh). Android only; a no-op where
/// the log doesn't exist.
abstract interface class NotificationLogExport {
  /// Writes the whole log; returns how many entries, or null when not supported.
  Future<int?> export();
}
