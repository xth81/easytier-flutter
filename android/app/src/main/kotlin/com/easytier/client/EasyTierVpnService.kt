package com.easytier.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * Android [VpnService] that owns the TUN interface and hands its file
 * descriptor to the EasyTier core.
 *
 * When the user connects from the Flutter UI, the app requests the VPN by
 * starting this service via [prepare] / [startVpn]. The service:
 *   1. Establishes a VPN interface using a virtual address + DNS + routes.
 *   2. Calls the native EasyTier JNI `setTunFd(instanceName, fd)` so the Rust
 *      core can read/write TUN packets.
 *   3. Shows a persistent foreground notification while connected.
 *
 * The service is deliberately decoupled from the Flutter engine: it can run
 * (and hold the tunnel) even if the UI process is backgrounded.
 */
class EasyTierVpnService : VpnService() {

    companion object {
        private const val TAG = "EasyTierVpnService"
        private const val CHANNEL_ID = "easytier_vpn"
        private const val NOTIFICATION_ID = 1001

        /** Instance name the native core registered, e.g. "easytier". */
        const val EXTRA_INSTANCE_NAME = "instance_name"
        /** Virtual IPv4 to assign to this node, e.g. "10.144.144.100". */
        const val EXTRA_IPV4 = "ipv4"
        /** Optional DNS server for the tunnel. */
        const val EXTRA_DNS = "dns"
        /** Optional routes pushed into the tunnel, e.g. "10.144.144.0/24". */
        const val EXTRA_ROUTES = "routes"

        fun prepare(context: Context): Boolean {
            val intent = VpnService.prepare(context)
            return intent == null
        }
    }

    private var tun: ParcelFileDescriptor? = null
    private var instanceName = "easytier"

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == "stop") {
            disconnect()
            return START_NOT_STICKY
        }

        instanceName = intent?.getStringExtra(EXTRA_INSTANCE_NAME) ?: "easytier"
        val ipv4 = intent?.getStringExtra(EXTRA_IPV4) ?: "10.144.144.100"
        val dns = intent?.getStringExtra(EXTRA_DNS) ?: ""
        val routes = intent?.getStringArrayExtra(EXTRA_ROUTES)
            ?: arrayOf("10.144.144.0/24")

        startForeground(NOTIFICATION_ID, buildNotification())

        // Rebuild the tunnel (idempotent)
        if (tun == null) {
            tun = establishTunnel(ipv4, dns, routes)
            tun?.let { fd ->
                val rc = EasyTierJni.setTunFd(instanceName, fd.fd)
                if (rc != 0) {
                    Log.e(TAG, "setTunFd failed with rc=$rc")
                } else {
                    Log.i(TAG, "TUN fd handed to core: ${fd.fd}")
                }
            }
        }

        return START_STICKY
    }

    private fun establishTunnel(
        ipv4: String,
        dns: String,
        routes: Array<String>,
    ): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession("EasyTier")
            .setMtu(1380)

        // Assign the node's virtual address.
        val cidrParts = ipv4.split("/")
        builder.addAddress(cidrParts[0], if (cidrParts.size > 1) cidrParts[1].toInt() else 24)

        if (dns.isNotEmpty()) {
            dns.split(",").forEach { builder.addDnsServer(it.trim()) }
        }

        // Add each route.
        routes.forEach { route -> addRoute(builder, route) }

        builder.addRoute("0.0.0.0", 0) // default route (optional fallback)
        return builder.establish()
    }

    private fun addRoute(builder: Builder, cidr: String) {
        val parts = cidr.split("/")
        val addr = parts[0]
        val prefix = if (parts.size > 1) parts[1].toInt() else 24
        // VpnService.Builder.addRoute(String, int) accepts a dotted-quad IPv4.
        builder.addRoute(addr, prefix)
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "EasyTier VPN", NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }

        val contentIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, EasyTierVpnService::class.java).setAction("stop"),
            PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }

        return builder
            .setContentTitle("EasyTier 已连接")
            .setContentText("正在运行 $instanceName")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(contentIntent)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_dialog_info),
                    "断开",
                    stopIntent
                ).build()
            )
            .build()
    }

    private fun disconnect() {
        try {
            // Stop the tunnel; the core will notice the fd close.
            tun?.close()
            tun = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing tun: ${e.message}")
        }
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }
}
