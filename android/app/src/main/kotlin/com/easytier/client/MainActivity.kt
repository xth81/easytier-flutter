package com.easytier.client

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Flutter entry activity. Hosts the `com.easytier.client/vpn` MethodChannel
 * used by the Dart [AndroidServiceBackend] to control the `:vpn` process.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "EasyTierMain"
        private const val CHANNEL = "com.easytier.client/vpn"
        private const val VPN_PREPARE_REQUEST = 0xE7E1
        private const val NOTIFICATION_PERMISSION_REQUEST = 0xE7E2
    }

    private var channel: MethodChannel? = null
    private var vpnService: IEasyTierVpnService? = null
    private var serviceConnection: ServiceConnection? = null
    private var pendingPrepareResult: MethodChannel.Result? = null
    private var pendingConnectArgs: Map<String, Any?>? = null

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == EasyTierVpnService.ACTION_STATE_CHANGED) {
                Log.d(TAG, "vpn service state changed")
                notifyDartServiceStateChanged()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ContextCompat.registerReceiver(
            this,
            stateReceiver,
            IntentFilter(EasyTierVpnService.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(stateReceiver)
        } catch (_: Exception) {
        }
        try {
            unbindVpnService()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    EasyTierJni.load()
                    result.success(EasyTierJni.isAvailable)
                }

                "prepareVpn" -> prepareVpn(result)

                "startVpn" -> {
                    // Android requires the VPN consent dialog to be triggered
                    // by an activity context; startForegroundService must be
                    // called after consent is granted.
                    val configToml = call.argument<String>("config") ?: ""
                    val ipv4 = call.argument<String>("ipv4") ?: "10.144.144.100"
                    val routes = call.argument<List<String>>("routes") ?: emptyList()
                    val dns = call.argument<String>("dns")
                    startVpnAfterPermission(configToml, ipv4, routes, dns, result)
                }

                "stopVpn" -> {
                    EasyTierVpnService.stop(this)
                    result.success(null)
                }

                "isRunning" -> {
                    val state = vpnServiceOrNull()?.state()
                    // The authoritative signal is the :vpn process state;
                    // while the binder is not attached yet, fall back to the
                    // flag the service maintains across processes.
                    result.success(
                        state == EasyTierVpnService.STATE_RUNNING ||
                            (state == null && EasyTierStateStore.wasRunning(this)),
                    )
                }

                "collectInfos" -> result.success(vpnServiceOrNull()?.collectInfos())

                "state" -> result.success(
                    vpnServiceOrNull()?.state() ?: EasyTierVpnService.STATE_STOPPED,
                )

                "lastError" -> result.success(vpnServiceOrNull()?.lastError ?: "")

                "getVersion" -> result.success(
                    BuildConfig.VERSION_NAME.takeIf { it.isNotBlank() } ?: "0.0.0",
                )

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PREPARE_REQUEST) {
            val pending = pendingPrepareResult
            pendingPrepareResult = null
            val args = pendingConnectArgs
            pendingConnectArgs = null
            if (resultCode == Activity.RESULT_OK) {
                val granted = EasyTierVpnService.prepare(this)
                if (args != null && pending != null) {
                    doStartVpn(args, pending)
                } else {
                    pending?.success(granted)
                }
            } else {
                pending?.success(false)
            }
        }
    }

    // ---- VPN permission / start flow ----

    private fun prepareVpn(result: MethodChannel.Result) {
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent == null) {
            result.success(true)
            return
        }
        pendingPrepareResult = result
        startActivityForResult(prepareIntent, VPN_PREPARE_REQUEST)
    }

    private fun startVpnAfterPermission(
        configToml: String,
        ipv4: String,
        routes: List<String>,
        dns: String?,
        result: MethodChannel.Result,
    ) {
        val args = mapOf(
            "config" to configToml,
            "ipv4" to ipv4,
            "routes" to routes,
            "dns" to dns,
        )
        if (VpnService.prepare(this) == null) {
            doStartVpn(args, result)
            return
        }
        // Keep the args around; the result is delivered from onActivityResult.
        pendingConnectArgs = args
        pendingPrepareResult = result
        startActivityForResult(VpnService.prepare(this)!!, VPN_PREPARE_REQUEST)
    }

    private fun doStartVpn(args: Map<String, Any?>, result: MethodChannel.Result) {
        val config = args["config"] as? String ?: ""
        val ipv4 = args["ipv4"] as? String ?: "10.144.144.100"
        val routes = (args["routes"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        val dns = args["dns"] as? String

        EasyTierStateStore.writeTunParams(this, ipv4, dns, routes.toTypedArray())

        // Android 13+: the foreground service notification is hidden without
        // this permission. Request it opportunistically; the VPN still works
        // if the user denies it.
        requestNotificationsPermission()

        try {
            EasyTierVpnService.start(
                this,
                config,
                ipv4,
                routes.toTypedArray(),
                dns,
            )
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "failed to start VPN service", e)
            result.success(false)
        }
    }

    private fun requestNotificationsPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    // ---- Binder plumbing (queries only) ----

    private fun vpnServiceOrNull(): IEasyTierVpnService? {
        vpnService?.let { return it }
        // Try to bind lazily so queries work even before the first connect.
        bindVpnService()
        return vpnService
    }

    private fun bindVpnService() {
        if (serviceConnection != null) return
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                vpnService = IEasyTierVpnService.Stub.asInterface(service)
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                vpnService = null
            }
        }
        serviceConnection = connection
        try {
            bindService(
                Intent(this, EasyTierVpnService::class.java),
                connection,
                Context.BIND_AUTO_CREATE,
            )
        } catch (_: Exception) {
            serviceConnection = null
        }
    }

    private fun unbindVpnService() {
        serviceConnection?.let {
            try {
                unbindService(it)
            } catch (_: Exception) {
            }
        }
        serviceConnection = null
        vpnService = null
    }

    private fun notifyDartServiceStateChanged() {
        val infos = vpnServiceOrNull()?.collectInfos()
        channel?.invokeMethod(
            "serviceStateChanged",
            buildString {
                append("{")
                if (!infos.isNullOrBlank()) {
                    append("\"infos\":")
                    append(JSONObject.quote(infos))
                    append(",")
                }
                append("\"running\":")
                append(
                    vpnServiceOrNull()?.state() == EasyTierVpnService.STATE_RUNNING ||
                        EasyTierStateStore.wasRunning(this),
                )
                append("}")
            },
        )
    }
}
