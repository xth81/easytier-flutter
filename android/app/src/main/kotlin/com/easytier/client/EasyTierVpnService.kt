package com.easytier.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Android [VpnService] that owns the TUN interface and runs the vendored
 * EasyTier Rust core **in a separate process** (`:vpn`).
 *
 * Lifecycle, mirroring how the official EasyTier mobile client works:
 *   1. The UI process asks the user for the VPN permission (`VpnService.prepare`),
 *      then starts this service with ACTION_CONNECT + the TOML config.
 *   2. The service establishes the TUN (address/DNS/routes/MTU) and calls the
 *      native core: `runNetworkInstance` followed by `setTunFd(instance, fd)`.
 *   3. A persistent foreground notification with a disconnect action keeps the
 *      tunnel alive in the background.
 *   4. The Flutter UI talks to the service through the
 *      [IEasyTierVpnService] Binder interface (queries only — all control
 *      happens through ACTION_CONNECT / ACTION_DISCONNECT so the service can
 *      also be stopped from its notification).
 */
class EasyTierVpnService : VpnService() {

    companion object {
        private const val TAG = "EasyTierVpnService"
        private const val CHANNEL_ID = "easytier_vpn"
        private const val NOTIFICATION_ID = 1001

        const val ACTION_CONNECT = "com.easytier.client.action.CONNECT"
        const val ACTION_DISCONNECT = "com.easytier.client.action.DISCONNECT"
        const val ACTION_STOP = "com.easytier.client.action.STOP"
        const val EXTRA_CONFIG_TOML = "config_toml"
        const val EXTRA_INSTANCE_NAME = "instance_name"
        const val EXTRA_IPV4 = "ipv4"
        const val EXTRA_ROUTES = "routes"
        const val EXTRA_DNS = "dns"
        const val EXTRA_MTU = "mtu"

        /** Binder state values (also returned through AIDL). */
        const val STATE_STOPPED = 0
        const val STATE_RUNNING = 1
        const val STATE_ERROR = -1

        /** Broadcast sent to the UI process whenever the tunnel state changes. */
        const val ACTION_STATE_CHANGED = "com.easytier.client.action.STATE_CHANGED"
        const val EXTRA_RUNNING = "running"

        /** Binder-backed query surface exposed to the UI process. */
        @Volatile
        private var binder: IEasyTierVpnService? = null

        /**
         * Prepare (request) the VPN permission. Returns true when the user has
         * already granted the system VPN consent.
         */
        fun prepare(context: Context): Boolean =
            VpnService.prepare(context) == null

        fun prepareIntent(context: Context): Intent? = VpnService.prepare(context)

        fun isRunning(): Boolean = binder?.state() == STATE_RUNNING

        fun start(
            context: Context,
            configToml: String,
            ipv4: String,
            routes: Array<String>,
            dns: String?,
        ) {
            val intent = Intent(context, EasyTierVpnService::class.java)
                .setAction(ACTION_CONNECT)
                .putExtra(EXTRA_CONFIG_TOML, configToml)
                .putExtra(EXTRA_INSTANCE_NAME, extractInstanceNameStatic(configToml))
                .putExtra(EXTRA_IPV4, ipv4)
                .putExtra(EXTRA_ROUTES, routes)
                .putExtra(EXTRA_DNS, dns)
            context.startForegroundService(intent)
        }

        private fun extractInstanceNameStatic(toml: String): String {
            val match = Regex("""(?m)^\s*instance_name\s*=\s*"([^"]+)"""")
                .find(toml)
            return match?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() } ?: "easytier"
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, EasyTierVpnService::class.java).setAction(ACTION_DISCONNECT),
            )
        }
    }

    private var tun: ParcelFileDescriptor? = null
    private var instanceName = "easytier"
    private var lastError: String? = null
    private var coreExecutor: ExecutorService? = null
    private var localBroadcastManager: LocalBroadcastManager? = null
    private var stateReceiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val binderImpl = object : IEasyTierVpnService.Stub() {
        override fun start(configToml: String): Int = doStart(configToml)

        override fun stop(): Int = doStop()

        override fun state(): Int = currentState()

        override fun collectInfos(): String? = collectInfosJson()

        override fun getLastError(): String = lastError ?: ""
    }

    override fun onBind(intent: Intent?): android.os.IBinder {
        binder = binderImpl
        return binderImpl
    }

    override fun onUnbind(intent: Intent?): Boolean {
        binder = null
        // Return false so a new client can bind again (standard pattern).
        return false
    }

    override fun onCreate() {
        super.onCreate()
        EasyTierJni.load()
        binder = binderImpl
        localBroadcastManager = LocalBroadcastManager.getInstance(this)
        stateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_DISCONNECT || intent?.action == ACTION_STOP) {
                    doStop()
                }
            }
        }
        localBroadcastManager.registerReceiver(
            stateReceiver!!,
            IntentFilter().apply {
                addAction(ACTION_DISCONNECT)
                addAction(ACTION_STOP)
            },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT, ACTION_STOP, "stop" -> {
                doStop()
                return START_NOT_STICKY
            }

            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG_TOML)
                if (config.isNullOrBlank()) {
                    lastError = "missing EasyTier config in connect intent"
                    return START_NOT_STICKY
                }
                EasyTierStateStore.writeTunParams(
                    this,
                    intent.getStringExtra(EXTRA_IPV4) ?: "10.144.144.100",
                    intent.getStringExtra(EXTRA_DNS),
                    intent.getStringArrayExtra(EXTRA_ROUTES) ?: emptyArray(),
                )
                doStart(config)
                return START_STICKY
            }

            null -> {
                // Restarted by the system after being killed: try to restore
                // the last known config, otherwise stop quietly.
                val config = EasyTierStateStore.runningConfig(this)
                if (config.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                doStart(config)
                return START_STICKY
            }

            else -> return START_NOT_STICKY
        }
    }

    private fun doStart(configToml: String): Int {
        if (EasyTierStateStore.runningConfig(this) == configToml &&
            currentState() == STATE_RUNNING && tun != null
        ) {
            // Idempotent restart with the same config.
            return 0
        }

        lastError = null
        EasyTierJni.clearError()

        // Tear down any previous instance/tunnel first (re-connect).
        teardownCore()
        tun?.close()
        tun = null
        stopForeground(STOP_FOREGROUND_REMOVE)

        // Parse the instance name from the TOML (instance_name = "...").
        instanceName = extractInstanceName(configToml)

        EasyTierStateStore.writeConfig(this, configToml)
        EasyTierStateStore.writeRunning(this, true)

        val executor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "easytier-core").apply { isDaemon = false }
        }
        coreExecutor = executor

        executor.execute {
            try {
                val rc = EasyTierJni.runNetworkInstanceSafe(configToml)
                if (rc != 0) {
                    lastError = "run_network_instance failed: ${EasyTierJni.lastError()}"
                    Log.e(TAG, lastError!!)
                    EasyTierStateStore.writeRunning(this, false)
                    notifyStateChanged()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return@execute
                }
                Log.i(TAG, "network instance '$instanceName' started")
            } catch (e: Throwable) {
                lastError = "failed to start network instance: ${e.message}"
                Log.e(TAG, lastError!!, e)
                EasyTierStateStore.writeRunning(this, false)
                notifyStateChanged()
                stopSelf()
                return@execute
            }

            // Wait for the core to report this node's virtual IP before
            // building the TUN. This mirrors the official client: in DHCP
            // mode the address must be the one the core actually assigned.
            val assignedIpv4 = awaitNodeIpv4()

            // TUN must be established on a looper/main thread of the service;
            // hop back to the main thread, then hand the fd to the core.
            mainHandler.post {
                try {
                    val descriptor = establishTunnel(assignedIpv4)
                    tun = descriptor
                    startForeground(NOTIFICATION_ID, buildNotification(instanceName))

                    val fd = descriptor.fd
                    val rc = EasyTierJni.setTunFdSafe(instanceName, fd)
                    if (rc != 0) {
                        lastError = "setTunFd failed: ${EasyTierJni.lastError()}"
                        Log.e(TAG, lastError!!)
                    } else {
                        Log.i(TAG, "TUN fd $fd attached to instance '$instanceName'")
                    }
                    notifyStateChanged()
                } catch (e: Throwable) {
                    lastError = "failed to establish VPN tunnel: ${e.message}"
                    Log.e(TAG, lastError!!, e)
                    EasyTierStateStore.writeRunning(this, false)
                    notifyStateChanged()
                    stopSelf()
                }
            }
        }
        return 0
    }

    /**
     * Poll `collectNetworkInfos` until this instance's `virtual_ipv4` is
     * available (up to ~20s). Returns the plain address (no prefix) to put
     * on the VPN interface, or falls back to the placeholder address.
     */
    private fun awaitNodeIpv4(): String {
        val placeholder = EasyTierStateStore.readIpv4(this)
            ?.substringBefore("/")
            ?.takeIf { it.isNotBlank() }
            ?: "10.144.144.100"
        val deadline = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < deadline) {
            try {
                val infos = EasyTierJni.collectNetworkInfosSafe() ?: return placeholder
                val json = org.json.JSONObject(infos)
                val map = json.optJSONObject("map") ?: json
                val entry = map.optJSONObject(instanceName) ?: map.optJSONObject("easytier")
                val node = entry?.optJSONObject("my_node_info")
                val v4 = node?.optJSONObject("virtual_ipv4")
                val addr = v4?.optJSONObject("address")
                val raw = addr?.opt("addr")
                val ip = when (raw) {
                    is org.json.JSONArray ->
                        (0 until raw.length()).joinToString(".") { raw.getInt(it).toString() }
                    is Number -> {
                        val value = raw.toLong()
                        listOf(
                            (value shr 24) and 0xFF,
                            (value shr 16) and 0xFF,
                            (value shr 8) and 0xFF,
                            value and 0xFF,
                        ).joinToString(".")
                    }
                    else -> null
                }
                if (!ip.isNullOrBlank() && ip != "0.0.0.0") {
                    Log.i(TAG, "core assigned virtual IPv4 $ip")
                    return ip
                }
            } catch (_: Throwable) {
                // keep polling
            }
            Thread.sleep(500)
        }
        Log.w(TAG, "virtual IPv4 not assigned in time; using $placeholder")
        return placeholder
    }

    private fun doStop(): Int {
        teardownCore()
        try {
            tun?.close()
        } catch (e: Exception) {
            Log.w(TAG, "error closing tun: ${e.message}")
        }
        tun = null
        EasyTierStateStore.writeRunning(this, false)
        EasyTierStateStore.clearConfig(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        notifyStateChanged()
        stopSelf()
        return 0
    }

    private fun teardownCore() {
        try {
            coreExecutor?.shutdownNow()
        } catch (_: Exception) {
        }
        coreExecutor = null
        if (instanceName.isNotBlank()) {
            try {
                EasyTierJni.retainNetworkInstanceSafe(emptyArray())
            } catch (_: Throwable) {
            }
        }
    }

    private fun currentState(): Int = when {
        // The service considers itself running from the moment the core was
        // asked to start; the TUN may attach a moment later.
        EasyTierStateStore.wasRunning(this) -> STATE_RUNNING
        lastError != null -> STATE_ERROR
        else -> STATE_STOPPED
    }

    private fun collectInfosJson(): String? = EasyTierJni.collectNetworkInfosSafe()

    private fun notifyStateChanged() {
        val intent = Intent(ACTION_STATE_CHANGED)
            .putExtra(EXTRA_RUNNING, currentState() == STATE_RUNNING)
            .setPackage(packageName)
        localBroadcastManager?.sendBroadcast(intent)
        sendBroadcast(intent)
    }

    private fun extractInstanceName(toml: String): String {
        val match = Regex("""(?m)^\s*instance_name\s*=\s*"([^"]+)"""")
            .find(toml)
        return match?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() } ?: "easytier"
    }

    // ---- VPN tunnel ----

    private fun establishTunnel(ipv4: String): ParcelFileDescriptor {
        val builder = Builder()
            .setSession("EasyTier")
            .setMtu(1380)
            .setBlocking(false)

        // The address was either user-specified (static mode) or read back
        // from the core (DHCP mode) in awaitNodeIpv4().
        val cidr = ipv4.split("/")
        val prefix = if (cidr.size > 1) cidr[1].toIntOrNull() ?: 24 else 24
        builder.addAddress(cidr[0], prefix)

        EasyTierStateStore.readDns(this)
            ?.takeIf { it.isNotBlank() }
            ?.let { dns -> dns.split(",").forEach { builder.addDnsServer(it.trim()) } }

        EasyTierStateStore.readRoutes(this)
            .forEach { route -> addRoute(builder, route) }

        return builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
    }

    private fun addRoute(builder: Builder, cidr: String) {
        val parts = cidr.split("/")
        if (parts.size != 2) throw IllegalArgumentException("invalid route: $cidr")
        val prefix = parts[1].toIntOrNull() ?: throw IllegalArgumentException("invalid route prefix: $cidr")
        builder.addRoute(parts[0], prefix)
    }

    private fun buildNotification(name: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "EasyTier VPN",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val disconnectIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, EasyTierVpnService::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("EasyTier 已连接")
            .setContentText("节点: $name")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "断开",
                    disconnectIntent,
                ).build(),
            )
            .build()
    }

    override fun onDestroy() {
        try {
            teardownCore()
            try {
                tun?.close()
            } catch (_: Exception) {
            }
            tun = null
        } catch (_: Throwable) {
        }
        try {
            stateReceiver?.let { localBroadcastManager?.unregisterReceiver(it) }
        } catch (_: Exception) {
        }
        stateReceiver = null
        super.onDestroy()
    }
}
