package com.easytier.client

import android.content.Context
import android.content.SharedPreferences

/**
 * Small state helper shared between the UI process and the `:vpn` service
 * process (Multi-process mode of SharedPreferences).
 *
 * `writeRunning`/`wasRunning` are a cross-process liveness hint: the
 * authoritative "is the VPN running" signal is the service binder's state
 * (STATE_RUNNING), with the hint used only while the binder is (re)attaching.
 */
object EasyTierStateStore {

    private const val PREFS = "easytier_vpn_state"
    private const val KEY_CONFIG = "config"
    private const val KEY_RUNNING = "running"
    private const val KEY_IPV4 = "ipv4"
    private const val KEY_DNS = "dns"
    private const val KEY_ROUTES = "routes"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun writeConfig(context: Context, toml: String) {
        prefs(context).edit().putString(KEY_CONFIG, toml).apply()
    }

    fun runningConfig(context: Context): String? =
        prefs(context).getString(KEY_CONFIG, null)

    fun clearConfig(context: Context) {
        prefs(context).edit().remove(KEY_CONFIG).apply()
    }

    fun writeRunning(context: Context, running: Boolean) {
        prefs(context).edit().putBoolean(KEY_RUNNING, running).apply()
    }

    fun wasRunning(context: Context): Boolean =
        prefs(context).getBoolean(KEY_RUNNING, false)

    fun writeTunParams(context: Context, ipv4: String, dns: String?, routes: Array<String>) {
        prefs(context).edit()
            .putString(KEY_IPV4, ipv4)
            .putString(KEY_DNS, dns)
            .putString(KEY_ROUTES, routes.joinToString(","))
            .apply()
    }

    fun readIpv4(context: Context): String? =
        prefs(context).getString(KEY_IPV4, null)

    fun readDns(context: Context): String? =
        prefs(context).getString(KEY_DNS, null)

    fun readRoutes(context: Context): Array<String> =
        prefs(context).getString(KEY_ROUTES, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?.toTypedArray()
            ?: emptyArray()
}
