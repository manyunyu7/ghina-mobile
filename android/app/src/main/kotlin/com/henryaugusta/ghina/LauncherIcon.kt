package com.henryaugusta.ghina

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * The launcher icon follows "Pilih maskot": AndroidManifest.xml declares one
 * activity-alias per mascot (`.Launcher<Id>`, all targeting MainActivity, only the tree
 * enabled by default). Switching enables the chosen alias first, then disables the
 * others, so the app is never without a launcher entry. The Android 12+ splash shows
 * the icon of the alias it was launched from, so it follows too.
 *
 * Disabling the alias the running task was launched from closes that task, so [set]
 * only records the choice; MainActivity.onStop calls [applyPending] once Ghina is in
 * the background.
 *
 * Ids are MascotKind.id (lib/presentation/design_system/mascot/mascot_kind.dart).
 */
object LauncherIcon {
    private val IDS = listOf(
        "pohon", "ayam", "kucing", "kapibara", "loko", "bibit", "koin", "hantu",
        "kura", "dompet", "beluga", "hiupaus", "komodo", "orangutan", "cendrawasih",
    )
    private const val DEFAULT = "pohon"
    private const val PREFS = "ghina_launcher_icon"
    private const val KEY_PENDING = "pending"

    private fun component(context: Context, id: String) = ComponentName(
        context.packageName,
        "com.henryaugusta.ghina.Launcher" + id.replaceFirstChar { it.uppercase() },
    )

    private fun isEnabled(context: Context, id: String): Boolean =
        when (context.packageManager.getComponentEnabledSetting(component(context, id))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> id == DEFAULT
            else -> false
        }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** The chosen mascot: the pending one, else the one whose alias is enabled. */
    fun current(context: Context): String? = runCatching {
        prefs(context).getString(KEY_PENDING, null)
            ?: IDS.firstOrNull { isEnabled(context, it) }
    }.getOrNull()

    /** Records the choice for [applyPending]. False for an unknown id. */
    fun set(context: Context, id: String): Boolean {
        if (id !in IDS) return false
        val p = prefs(context)
        if (IDS.filter { isEnabled(context, it) } == listOf(id)) {
            p.edit().remove(KEY_PENDING).apply()
        } else {
            p.edit().putString(KEY_PENDING, id).apply()
        }
        return true
    }

    /** Switches to the recorded choice, if any. Call while Ghina is not in front. */
    fun applyPending(context: Context) {
        val p = prefs(context)
        val id = p.getString(KEY_PENDING, null) ?: return
        if (switchTo(context, id)) p.edit().remove(KEY_PENDING).apply()
    }

    private fun switchTo(context: Context, id: String): Boolean {
        if (id !in IDS) return true
        return runCatching {
            val pm = context.packageManager
            val enabled = IDS.filter { isEnabled(context, it) }
            if (enabled == listOf(id)) return true
            pm.setComponentEnabledSetting(
                component(context, id),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            for (other in enabled) {
                if (other == id) continue
                pm.setComponentEnabledSetting(
                    component(context, other),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            true
        }.getOrDefault(false)
    }
}
