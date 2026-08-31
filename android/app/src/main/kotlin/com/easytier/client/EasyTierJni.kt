package com.easytier.client

/**
 * Thin Kotlin bridge to the embeddable EasyTier core.
 *
 * On a real device this loads the native `libeasytier_android_jni.so`
 * (which in turn links `libeasytier_ffi.so`) and exposes the same surface as
 * `com.easytier.jni.EasyTierJNI` from the official
 * `easytier-contrib/easytier-android-jni` crate. The method signatures here
 * match that crate so the app can be pointed at the real library drop-in.
 *
 * When no native library is present (emulator / preview), these methods return
 * sentinel values and the Flutter layer falls back to the mock backend.
 */
object EasyTierJni {

    private val available: Boolean by lazy {
        try {
            System.loadLibrary("easytier_android_jni")
            true
        } catch (_: UnsatisfiedLinkError) {
            false
        }
    }

    val isAvailable: Boolean get() = available

    /** Attach a TUN file descriptor to a named instance. Returns 0 on success. */
    fun setTunFd(instanceName: String, fd: Int): Int =
        if (available) nativeSetTunFd(instanceName, fd) else -1

    private external fun nativeSetTunFd(instanceName: String, fd: Int): Int
}
