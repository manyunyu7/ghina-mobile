#!/usr/bin/env bash
# Pulls the "Log Notifikasi" copy from the phone over adb (USB or wireless debugging).
#
#   tool/pull_notification_log.sh            # → ~/.local/share/ghina/notification-log/
#   GHINA_NOTIF_DIR=/elsewhere tool/pull_notification_log.sh
#
# The app rewrites Android/data/<pkg>/files/notification-log/{notifications.jsonl,meta.json}
# (plus listener-watchdog.jsonl, appended by NotificationListenerWatchdog.kt)
# on start, on resume and after processing (lib/data/platform/notification_log_exporter.dart).
# This opens Ghina to trigger that, waits for meta.json to change, then pulls. The phone must
# be unlocked for the app to come to the front; otherwise the last copy is pulled as-is.
# Output stays outside any repo (0700): it is every notification on the phone.
set -euo pipefail

PKG=com.henryaugusta.ghina
SRC=/sdcard/Android/data/$PKG/files/notification-log
DEST=${GHINA_NOTIF_DIR:-$HOME/.local/share/ghina/notification-log}

adb get-state >/dev/null 2>&1 || { echo "HP tidak terhubung (adb devices kosong)." >&2; exit 1; }

meta() { adb shell cat "$SRC/meta.json" 2>/dev/null | tr -d '\r' || true; }
before=$(meta)

# Bring Ghina to the front: a fresh start or a resume both export.
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true

now=$before
for _ in $(seq 1 30); do
  sleep 1
  now=$(meta)
  [ -n "$now" ] && [ "$now" != "$before" ] && break
done

if [ -z "$now" ]; then
  echo "Belum ada salinan log di HP. Buka Ghina sekali (versi ≥ 1.5.1) lalu ulangi." >&2
  exit 1
fi
[ "$now" = "$before" ] && echo "Peringatan: salinan tidak diperbarui (HP terkunci / Ghina baru saja diekspor) — menarik salinan terakhir." >&2

mkdir -p "$DEST"
chmod 700 "$DEST"
adb pull "$SRC/notifications.jsonl" "$DEST/notifications.jsonl" >/dev/null
printf '%s\n' "$now" > "$DEST/meta.json"
chmod 600 "$DEST/notifications.jsonl" "$DEST/meta.json"
# Listener watchdog checks (rebinds, backfills) — tells holes in the log from quiet hours.
if adb pull "$SRC/listener-watchdog.jsonl" "$DEST/listener-watchdog.jsonl" >/dev/null 2>&1; then
  chmod 600 "$DEST/listener-watchdog.jsonl"
fi

lines=$(wc -l < "$DEST/notifications.jsonl" | tr -d ' ')
echo "OK: $lines notifikasi → $DEST/notifications.jsonl"
echo "meta: $now"
