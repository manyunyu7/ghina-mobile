package com.henryaugusta.ghina

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.util.Log
import im.zoe.labs.flutter_notification_listener.NotificationsHandlerService
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Keeps "Log Notifikasi" listening when the ROM gets in the way.
 *
 * flutter_notification_listener's service has no reconnect logic: once the system
 * unbinds it (Samsung freezes / kills Ghina in the background, notification access
 * re-toggled, process death) it stays deaf until Ghina is opened again, and the log
 * gets 10–20 hour holes. Every [check] (app resume + a periodic job, see
 * [ListenerWatchdogJob]):
 *
 *  1. not connected → NotificationListenerService.requestRebind; if that didn't help
 *     since the previous check, disable + re-enable the service component, which
 *     makes the system bind it afresh on ROMs that ignore requestRebind;
 *  2. connected → backfill: notifications still in the shade that were posted since
 *     the previous backfill go through the plugin's own onNotificationPosted, so the
 *     Dart callback stores them (insertCapturedNotification drops duplicates).
 *
 * Each check appends one line to Android/data/<pkg>/files/notification-log/
 * listener-watchdog.jsonl (pulled by tool/pull_notification_log.sh), so holes in the
 * log can be told apart from quiet hours.
 */
object NotificationListenerWatchdog {
    private const val TAG = "GhinaListenerWatchdog"
    private const val PREFS = "ghina_listener_watchdog"
    private const val KEY_BACKFILLED_AT = "backfilledAt"
    private const val KEY_FAILURES = "failures"

    /** First backfill (or after a long outage): the shade rarely holds older ones. */
    private const val MAX_BACKFILL_AGE_MS = 48L * 60 * 60 * 1000

    /** Overlap with the previous backfill; duplicates are dropped on the Dart side. */
    private const val BACKFILL_OVERLAP_MS = 5L * 60 * 1000

    private const val EVENTS_FILE = "notification-log/listener-watchdog.jsonl"
    private const val EVENTS_MAX_BYTES = 256L * 1024

    private val main = Handler(Looper.getMainLooper())

    /** UTC ISO-8601 like the log export (java.time needs API 26; minSdk is 24). */
    private fun isoNow(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date())

    /** Safe from any thread; the work runs on the main thread like the plugin's. */
    fun check(context: Context, reason: String) {
        val app = context.applicationContext
        main.post { runCatching { checkNow(app, reason) }.onFailure { Log.w(TAG, "check failed", it) } }
    }

    private fun checkNow(context: Context, reason: String) {
        if (!NotificationsHandlerService.permissionGiven(context)) {
            record(context, reason, "no-access")
            return
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val service = NotificationsHandlerService.instance
        val active = service?.let { s ->
            // Throws SecurityException while the listener isn't bound.
            runCatching { s.activeNotifications }.getOrNull()
        }
        if (service == null || active == null) {
            val failures = prefs.getInt(KEY_FAILURES, 0) + 1
            prefs.edit().putInt(KEY_FAILURES, failures).apply()
            val component = ComponentName(context, NotificationsHandlerService::class.java)
            if (failures >= 2) {
                runCatching {
                    val pm = context.packageManager
                    pm.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                    pm.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }
            }
            runCatching { NotificationListenerService.requestRebind(component) }
            record(
                context,
                reason,
                if (failures >= 2) "rebind+toggle" else "rebind",
                "failures" to failures,
                "instance" to (service != null),
            )
            return
        }

        val now = System.currentTimeMillis()
        val since = maxOf(
            prefs.getLong(KEY_BACKFILLED_AT, 0L) - BACKFILL_OVERLAP_MS,
            now - MAX_BACKFILL_AGE_MS,
        )
        var replayed = 0
        for (sbn in active) {
            if (sbn.packageName == context.packageName || sbn.postTime < since) continue
            runCatching { service.onNotificationPosted(sbn) }.onSuccess { replayed++ }
        }
        prefs.edit().putLong(KEY_BACKFILLED_AT, now).putInt(KEY_FAILURES, 0).apply()
        record(context, reason, "ok", "active" to active.size, "replayed" to replayed)
    }

    private fun record(context: Context, reason: String, result: String, vararg extra: Pair<String, Any>) {
        Log.i(TAG, "$reason: $result ${extra.joinToString()}")
        runCatching {
            val base = context.getExternalFilesDir(null) ?: return
            val file = File(base, EVENTS_FILE)
            file.parentFile?.mkdirs()
            if (file.length() > EVENTS_MAX_BYTES) {
                // Keep the newer half.
                val lines = file.readLines()
                file.writeText(lines.drop(lines.size / 2).joinToString("\n", postfix = "\n"))
            }
            val line = JSONObject()
                .put("at", isoNow())
                .put("reason", reason)
                .put("result", result)
            for ((k, v) in extra) line.put(k, v)
            file.appendText(line.toString() + "\n")
        }
    }
}

/**
 * Periodic [NotificationListenerWatchdog.check] (every 15 min, the JobScheduler
 * minimum; persisted across reboots). Running it also starts Ghina's process, which
 * is what lets the rebind happen while the app is closed.
 */
class ListenerWatchdogJob : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        NotificationListenerWatchdog.check(this, "job")
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = true

    companion object {
        private const val JOB_ID = 0x6e6f7466 // "notf"
        private const val INTERVAL_MS = 15L * 60 * 1000

        /** Idempotent: keeps an already scheduled job (and its timing). */
        fun schedule(context: Context) {
            runCatching {
                val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
                if (scheduler.getPendingJob(JOB_ID) != null) return
                val job = JobInfo.Builder(JOB_ID, ComponentName(context, ListenerWatchdogJob::class.java))
                    .setPeriodic(INTERVAL_MS)
                    .setPersisted(true)
                    .build()
                scheduler.schedule(job)
            }
        }
    }
}
