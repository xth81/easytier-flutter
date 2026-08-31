# Rust 核心集成（vendored EasyTier）

本目录是 **官方 EasyTier Rust 核心的裁剪副本**（上游：https://github.com/EasyTier/EasyTier ），
包含客户端需要的 5 个 crate：

```
rust/
├── Cargo.toml                  # 精简后的 workspace（默认成员为 android-jni）
├── build.sh                    # 交叉编译脚本（cargo-ndk + NDK）
├── easytier-core/              # 可移植核心（组网、路由、加密、NAT 穿透）
├── easytier-proto/             # protobuf 类型与 RPC
├── easytier/                   # 原生组合层（TUN、TCP/UDP/WS/QUIC 引擎）
└── easytier-contrib/
    ├── easytier-ffi/           # C ABI（run_network_instance / collect_network_infos / set_tun_fd / ...）
    └── easytier-android-jni/   # JNI 封装（Java_com_easytier_jni_EasyTierJNI_* 导出）
```

## 为什么这样集成

- **同进程运行**（参考官方 Android 客户端）：`EasyTierVpnService`（`android:process=":vpn"`）
  在独立进程里执行 `System.loadLibrary` → `runNetworkInstance(toml)` →
  轮询 `collectNetworkInfos` 拿到本机虚拟 IP（DHCP 模式必须等核心分配）→
  `Builder().establish()` 建立 TUN → `setTunFd(instance, fd)` 把 fd 交给核心。
- **VPN 声明**：静态模式用用户填写的 IP；DHCP 模式先启动核心、等
  `virtual_ipv4` 出现再建 TUN。TUN 路由/DNS 通过 service intent 传入，
  核心内置 IP 段为 `10.144.144.0/24`。
- **核心上报**：Dart 侧通过 Binder 查询 `collectNetworkInfos()`，由
  `lib/data/models/status_json.dart` 按官方 protobuf JSON 结构解析
  （`my_node_info.virtual_ipv4`、`routes[].hostname/proxy_cidrs/path_latency`、
  `peers[].conns[].stats.latency_us` 等）。

## 对上游做的修改（务必保留）

| 文件 | 修改 | 原因 |
|------|------|------|
| `easytier/Cargo.toml` | `service-manager` 改为 `optional = true` 并加入 `management` feature | 该依赖走 git + 固定分支，移动端构建不启用 management，避免 CI 拉取 |
| `easytier/Cargo.toml` | 默认 features 移除 `kcp` / `upnp` / `management` / `linux-netlink` | 见下方「协议与特性」 |
| `easytier/Cargo.toml` | `extended-services` 不再包含 `public-ipv6-provider`（其依赖 `linux-netlink`） | Android 无 netlink |
| `easytier/Cargo.toml` | 移除 `thunk-rs`（Windows-only）build 依赖 | Android 交叉编译用不到，减少网络依赖 |
| `easytier/build/main.rs`、`easytier-contrib/easytier-ffi/build.rs` | 移除 thunk-rs 调用 | 同上 |

其余代码与上游一致（EasyTier `2.6.4` 系列，rust-version 1.95）。

## 本地/CI 构建

```bash
# 需要: Rust 1.95、cargo-ndk、Android NDK（NDK_HOME / ANDROID_NDK_HOME）
./build.sh                     # 默认 arm64-v8a armeabi-v7a x86_64
./build.sh arm64-v8a           # 只构建一个 ABI
```

脚本会把 `libeasytier_android_jni.so` 与 `libeasytier_ffi.so` 复制到
`android/app/src/main/jniLibs/<abi>/`，随后 `flutter build apk` 自动打包。

> 说明：`easytier-android-jni` 的 `build.rs` 使用 linker version-script 只导出
> `Java_com_easytier_jni_EasyTierJNI_*` 符号；同时构建 `libeasytier_ffi.so`
> 供桌面/模拟器 FFI 后端使用（Kotlin 侧动态查找 C ABI 符号）。

## 协议与特性

移动端构建默认启用：
`wireguard / websocket / smoltcp / tun / socks5 / quic / faketcp / magic-dns /
zstd / icmp-proxy / endpoint-discovery / extended-services / tcp-hole-punch`

刻意不启用（Android 无意义或增加 CI 负担）：
`kcp`（会拉取 kcp-sys 的 git 依赖并交叉编译其 C 代码）、`upnp`、
`management`（service-manager git 依赖）、`linux-netlink` /
`public-ipv6-provider`（netlink 是 Linux 桌面特性）。

加密：`wireguard` feature 带来 `ring-crypto`，默认 AES-GCM 加密走 ring
后端，跨节点兼容官方客户端。
