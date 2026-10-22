package com.henryaugusta.ghina

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget "Kantor": pending permissions, working/idle counts and the top
 * agents. Pure display; the data is pushed by Dart (lib/data/widgets/
 * kantor_widget_bridge.dart) into home_widget's "HomeWidgetPreferences" as one JSON
 * string under [DATA_KEY] (keys: ok, waiting, working, idle, updatedAt, checkedAt,
 * agents[{name, action, waiting, route}]). No token ever reaches this class.
 *
 * Taps open MainActivity with [EXTRA_ROUTE] (a /kantor… go_router path); MainActivity
 * hands it to Dart (see the "kantor_widget" channel there).
 */
class KantorWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle?,
    ) {
        render(context, manager, id)
    }

    companion object {
        const val ACTION_OPEN = "com.henryaugusta.ghina.KANTOR_OPEN"
        const val EXTRA_ROUTE = "kantor_route"
        private const val PREFS = "HomeWidgetPreferences"
        private const val DATA_KEY = "kantor_summary"
        private const val WIDE_MIN_DP = 180

        private val rowIds = arrayOf(
            Triple(R.id.kw_row1, R.id.kw_row1_name, R.id.kw_row1_action),
            Triple(R.id.kw_row2, R.id.kw_row2_name, R.id.kw_row2_action),
            Triple(R.id.kw_row3, R.id.kw_row3_name, R.id.kw_row3_action),
        )

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val wide = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) >= WIDE_MIN_DP
            val views = RemoteViews(
                context.packageName,
                if (wide) R.layout.kantor_widget_wide else R.layout.kantor_widget_small,
            )
            val data = read(context)
            views.setOnClickPendingIntent(R.id.kw_root, openIntent(context, id * 10, "/kantor"))

            val ok = data?.optBoolean("ok", false) == true
            val hasNumbers = data?.has("updatedAt") == true
            val agents = data?.optJSONArray("agents")

            when {
                data == null -> {
                    views.setTextViewText(R.id.kw_count, "–")
                    views.setTextViewText(R.id.kw_label, "Buka Ghina & isi token Kantor")
                    views.setTextViewText(R.id.kw_stats, "")
                    views.setTextViewText(R.id.kw_updated, "")
                }
                !ok && !hasNumbers -> {
                    views.setTextViewText(R.id.kw_count, "–")
                    views.setTextViewText(R.id.kw_label, "Tidak terhubung (Tailscale?)")
                    views.setTextViewText(R.id.kw_stats, "")
                    views.setTextViewText(R.id.kw_updated, "Dicek ${clock(data.optLong("checkedAt"))}")
                }
                else -> {
                    views.setTextViewText(R.id.kw_count, data.optInt("waiting").toString())
                    views.setTextViewText(
                        R.id.kw_label,
                        if (ok) "izin menunggu" else "Tidak terhubung (Tailscale?)",
                    )
                    views.setTextViewText(
                        R.id.kw_stats,
                        "${data.optInt("working")} bekerja · ${data.optInt("idle")} idle",
                    )
                    views.setTextViewText(
                        R.id.kw_updated,
                        if (ok) "Diperbarui ${clock(data.optLong("updatedAt"))}"
                        else "Terakhir tahu ${clock(data.optLong("updatedAt"))}",
                    )
                }
            }

            if (wide) {
                val count = if (ok || hasNumbers) agents?.length() ?: 0 else 0
                rowIds.forEachIndexed { i, (row, name, action) ->
                    val a = if (i < count) agents?.optJSONObject(i) else null
                    if (a == null) {
                        views.setViewVisibility(row, View.GONE)
                        return@forEachIndexed
                    }
                    views.setViewVisibility(row, View.VISIBLE)
                    views.setTextViewText(name, a.optString("name"))
                    views.setTextViewText(action, a.optString("action"))
                    views.setTextColor(
                        action,
                        context.getColor(
                            if (a.optBoolean("waiting")) R.color.kantor_widget_accent
                            else R.color.kantor_widget_text_secondary,
                        ),
                    )
                    val route = a.optString("route")
                    if (route.startsWith("/kantor")) {
                        views.setOnClickPendingIntent(row, openIntent(context, id * 10 + 1 + i, route))
                    }
                }
                views.setViewVisibility(
                    R.id.kw_empty,
                    if (data != null && (ok || hasNumbers) && count == 0) View.VISIBLE else View.GONE,
                )
            }
            manager.updateAppWidget(id, views)
        }

        private fun read(context: Context): JSONObject? {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(DATA_KEY, null)
            if (raw.isNullOrBlank()) return null
            return runCatching { JSONObject(raw) }.getOrNull()
        }

        private fun clock(millis: Long): String =
            if (millis <= 0) "–" else SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(millis))

        private fun openIntent(context: Context, requestCode: Int, route: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .putExtra(EXTRA_ROUTE, route)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
