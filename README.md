# EasyTier Flutter 客户端

一个 **Material 3（Material You）** 风格的 **EasyTier 安卓客户端**，Flutter UI +
官方 EasyTier Rust 核心（vendored），设计与布局参考官方 **AstralET** 客户端。

## 特性

- **真实核心**：`rust/` 内是官方 EasyTier 核心的裁剪副本（`easytier-core` /
  `easytier-proto` / `easytier` / `easytier-ffi` / `easytier-android-jni`），
  GitHub Actions 用 `cargo-ndk` 交叉编译并打包进 APK（arm64-v8a /
  armeabi-v7a / x86_64），不需要手工下载任何 SDK。
- **正确的 Android 接法**：`EasyTierVpnService` 运行在独立 `:vpn` 进程，
  建 TUN → `runNetworkInstance(toml)` → `setTunFd`，与官方 Android 客户端相同；
  UI 进程通过 Binder（AIDL）查询状态。
- **生产级功能**：VPN 权限引导、前台常驻通知（含断开按钮）、配置校验、
  配置持久化、启动自动连接、错误信息回显、Magic DNS、出口节点、子网路由、
  节点/路由实时展示、浅色/深色/跟随系统主题与主题色。
- **双后端**：Android 上走 `:vpn` 服务进程；桌面走 `easytier-ffi` C ABI；
  无核心时回退到内存 Mock 后端（开发预览 / 测试）。

## 界面布局（Material 3 / astral 风格）

底部 `NavigationBar` 四个标签：

1. **首页**：连接 Hero 卡（状态环 + 连接按钮 + 上下行/延迟）、当前网络摘要、
   流量统计条、节点快照；
2. **网络**：分组表单（网络身份 / 地址模式 / 接入点 / 高级选项），
   保存并连接 / 仅保存 / 断开；
3. **节点**：可达节点列表（直连/中转、NAT 类型、延迟）与导出路由表；
4. **设置**：外观（主题模式/主题色）、网络行为（自动连接）、网络引擎、
   关于。

## 架构

```
easytier-flutter/
├── lib/
│   ├── main.dart                    # 入口：加载设置、构建后端、自动连接
│   ├── app.dart                     # 根组件：主题 + 四 tab 导航
│   ├── core/
│   │   ├── backend/
│   │   │   ├── easytier_backend.dart    # 后端抽象接口
│   │   │   ├── backend_factory.dart     # Android→service / 桌面→FFI / 回退 mock
│   │   │   ├── service_backend.dart     # Android：MethodChannel ↔ :vpn 进程
│   │   │   ├── ffi_backend.dart         # 桌面：easytier-ffi C ABI
│   │   │   ├── ffi_bindings.dart
│   │   │   └── mock_backend.dart        # 内存模拟引擎
│   │   └── state/
│   │       └── easytier_controller.dart # ChangeNotifier 状态中枢
│   ├── data/
│   │   ├── config/    app_settings.dart, app_theme.dart
│   │   └── models/    network_config.dart(+TOML), network_status.dart,
│   │                  peer_info.dart, tunnel_state.dart, status_json.dart,
│   │                  config_validators.dart
│   ├── screens/       home / networks / peers / settings
│   └── widgets/       astral_card, connection_hero_card, status_pill,
│                      section_card, section_header
├── android/
│   └── app/src/main/
│       ├── aidl/com/easytier/client/IEasyTierVpnService.aidl
│       ├── kotlin/com/easytier/client/
│       │   ├── MainActivity.kt          # MethodChannel + VPN 权限流程 + Binder 查询
│       │   ├── EasyTierVpnService.kt    # :vpn 进程：TUN + 核心生命周期
│       │   ├── EasyTierJni.kt           # JNI 桥（动态解析 C ABI）
│       │   └── EasyTierStateStore.kt    # 跨进程状态缓存
│       └── jniLibs/<abi>/               # 构建产物：libeasytier_*.so
└── rust/                              # vendored 官方核心 + build.sh
```

## 构建与发布

**无需本地 SDK**：推到 GitHub 后 `.github/workflows/build.yml` 会

1. 安装 Flutter + Android SDK/NDK + Rust 1.95 + cargo-ndk；
2. 运行 `rust/build.sh` 交叉编译三个 ABI 并放入 `jniLibs`；
3. `flutter analyze` → `flutter test` → `flutter build apk`（debug + release）；
4. 上传 artifact，并在 main/master 分支自动发布到 `latest` GitHub Release。

也可以本地复现（需 Flutter、Android SDK/NDK、Rust 1.95、cargo-ndk）：

```bash
cd easytier-flutter
(cd rust && ./build.sh arm64-v8a armeabi-v7a x86_64)
flutter pub get
flutter analyze && flutter test
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。

## 配置说明

- **网络名称 / 网络密钥**：所有节点必须一致；密钥是网络凭证。
- **DHCP（推荐）**：由网络自动分配虚拟 IPv4；静态模式手动填写 `IP/前缀`。
- **种子节点**：没有公网 IP 时填写公共/自建中继，如 `tcp://public.easytier.cn:11010`。
- **允许作为出口节点**：其他节点可经本机代理外网流量（可限制仅特定节点 IP）。
- **Magic DNS**：可用节点主机名互相访问（`100.100.100.101`）。
- **无 TUN 模式**：仅作子网路由节点，不占用本机 VPN。

## 说明与范围

- Android 为第一优先级；桌面（Linux/macOS/Windows）保留 FFI 后端路径，
  目录结构可继续扩展。
- 首次启动会请求系统 VPN 授权；连接期间通过前台通知保活，可从通知直接断开。
- 无核心的环境（纯 UI 预览/单测）自动回退 Mock 后端。

## 参考

- [EasyTier/EasyTier](https://github.com/EasyTier/EasyTier) —— Rust 实现的去中心化 mesh VPN。
- [EasyTier/astral](https://github.com/EasyTier/astral) —— 参考的 Flutter + Rust 客户端设计。
