# rust_builder / Rust core integration

This folder is the Flutter plugin that builds and bundles the embeddable
**EasyTier Rust core** (`libeasytier_ffi`) for each platform. When the real
core is present, the app's `EasyTierFfiBackend` loads it and drives the actual
mesh; otherwise the app falls back to the built-in mock backend.

## What the app expects

The Dart side (`lib/core/backend/ffi_backend.dart`) opens a dynamic library
with the platform-appropriate name:

| Platform | `libraryName`            |
|----------|--------------------------|
| Android  | `libeasytier_ffi.so`     |
| iOS      | `libeasytier_ffi.so`     |
| Linux    | `libeasytier_ffi.so`     |
| macOS    | `libeasytier_ffi.dylib`  |
| Windows  | `easytier_ffi.dll`       |

It calls the **C ABI** exposed by `easytier-contrib/easytier-ffi`:

- `parse_config`, `run_network_instance`
- `retain_network_instance`, `delete_network_instance`
- `list_instance`, `collect_network_infos`
- `set_tun_fd`, `call_json_rpc`
- `get_error_msg`, `free_string`

On Android the library is packaged under `app/src/main/jniLibs/<abi>/`.

## Building the library

The official EasyTier repo already ships an Android JNI build:

```
easytier-src/easytier-contrib/easytier-android-jni/build.sh
```

That builds `libeasytier_android_jni.so` **and** `libeasytier_ffi.so` via
`cargo-ndk`. Copy them into `android/app/src/main/jniLibs/arm64-v8a/` (and the
other ABIs you target).

For a fully automated setup, vendor the `easytier` Rust crate (as the reference
`astral` app does) and wire it through `cargokit`. That is intentionally left
out of this scaffold so the project compiles and runs on the emulator using the
mock backend; drop in the built `.so` files to switch to the real core.

## Notes

- The Kotlin `EasyTierJni` wrapper matches the official
  `com.easytier.jni.EasyTierJNI` surface, so the same `.so` works.
- The `EasyTierVpnService` hands the TUN fd to the core via `setTunFd`.
