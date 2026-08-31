package com.easytier.client

import java.util.concurrent.ConcurrentHashMap

/**
 * Kotlin JNI bridge to the vendored EasyTier Rust core.
 *
 * `libeasytier_android_jni.so` is built from `rust/easytier-contrib/easytier-android-jni`
 * (official EasyTier Android JNI crate) and exported methods follow the
 * Java signatures defined there. Method name resolution is therefore dynamic,
 * which also lets the Flutter FFI backend use the same symbol name scheme.
 *
 * When the native libraries are absent (pure emulator preview), every method
 * returns a sentinel and [getLastError] explains why.
 */
object EasyTierJni {

    private var loaded = false
    private var loadFailure: String? = "native libraries not loaded yet"

    /** Per-thread last-error strings (the core stores errors per thread). */
    private val lastErrors = ConcurrentHashMap<Long, String>()

    fun load() {
        if (loaded) return
        try {
            System.loadLibrary("easytier_ffi")
            System.loadLibrary("easytier_android_jni")
            loaded = true
            loadFailure = null
        } catch (e: UnsatisfiedLinkError) {
            loadFailure = "failed to load EasyTier native libraries: ${e.message}"
        }
    }

    val isAvailable: Boolean
        get() = loaded

    /** Whether the app process (FFI mode) can load the plain FFI library. */
    fun canLoadFfi(): Boolean {
        if (loaded) return true
        return try {
            System.loadLibrary("easytier_ffi")
            true
        } catch (_: UnsatisfiedLinkError) {
            false
        }
    }

    fun lastError(): String = lastErrors[Thread.currentThread().id] ?: loadFailure ?: ""

    // ---- exported native methods (see easytier-android-jni/src/lib.rs) ----

    @JvmStatic
    external fun parseConfig(config: String): Int

    @JvmStatic
    external fun runNetworkInstance(config: String): Int

    @JvmStatic
    external fun retainNetworkInstance(instanceNames: Array<String>?): Int

    @JvmStatic
    external fun deleteNetworkInstance(instanceName: String): Int

    @JvmStatic
    external fun listInstances(maxLength: Int): String?

    @JvmStatic
    external fun collectNetworkInfos(maxLength: Int): String?

    @JvmStatic
    external fun setTunFd(instanceName: String, fd: Int): Int

    @JvmStatic
    external fun callJsonRpc(
        serviceName: String,
        methodName: String,
        domainName: String,
        payloadJson: String,
    ): String?

    @JvmStatic
    external fun getLastError(): String?

    // ---- helpers ----

    private fun guard(): Boolean {
        load()
        if (!loaded) {
            lastErrors[Thread.currentThread().id] = loadFailure ?: "native libraries unavailable"
            return false
        }
        return true
    }

    /** Run a native call and record its per-thread error on failure. */
    private inline fun <T> safeCall(
        sentinel: T,
        block: () -> T,
    ): T {
        if (!guard()) return sentinel
        return try {
            block()
        } catch (e: Throwable) {
            val nativeError = try {
                getLastError()
            } catch (_: Throwable) {
                null
            }
            val msg = nativeError?.takeIf { it.isNotBlank() }
                ?: e.message
                ?: e.javaClass.simpleName
            lastErrors[Thread.currentThread().id] = msg
            sentinel
        }
    }

    fun parseConfigSafe(config: String): Int =
        safeCall(-1) { parseConfig(config) }

    fun runNetworkInstanceSafe(config: String): Int =
        safeCall(-1) { runNetworkInstance(config) }

    fun retainNetworkInstanceSafe(instanceNames: Array<String>?): Int =
        safeCall(-1) { retainNetworkInstance(instanceNames) }

    fun deleteNetworkInstanceSafe(instanceName: String): Int =
        safeCall(-1) { deleteNetworkInstance(instanceName) }

    fun listInstancesSafe(): String? =
        safeCall(null) { listInstances(8) }

    fun collectNetworkInfosSafe(): String? =
        safeCall(null) { collectNetworkInfos(8) }

    fun setTunFdSafe(instanceName: String, fd: Int): Int =
        safeCall(-1) { setTunFd(instanceName, fd) }

    fun callJsonRpcSafe(
        serviceName: String,
        methodName: String,
        domainName: String,
        payloadJson: String,
    ): String? =
        safeCall(null) { callJsonRpc(serviceName, methodName, domainName, payloadJson) }

    /** Clear any stale error so the next failure reports accurately. */
    fun clearError() {
        lastErrors.remove(Thread.currentThread().id)
    }
}