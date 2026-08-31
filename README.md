# EasyTier Flutter 客户端

一个 **Material 3（Material You）** 风格的 **EasyTier 跨平台客户端**，采用 Flutter 编写，优先完成 **Android** 端。设计与架构参考了官方的 **AstralET**（`EasyTier/astral`）——一个基于 Flutter + Rust（easytier）的游戏联机工具。

## 设计语言（astral / Material 3）

- **种子色主题**：整套配色由单个种子色动态派生，浅色 / 深色 / 跟随系统三种模式，可在设置中切换主题色。
- **卡片式仪表盘**：圆角大卡片（`AstralCard`）、柔和表面、状态胶囊、动画状态环。
- **布局**：底部 `NavigationBar` 四个标签 —— 首页 / 网络 / 节点 / 设置。

## 架构

本项目把「UI」与「引擎」解耦，通过一个可插拔的 `EasyTierBackend` 接口连接真实核心：

```
easytier-flutter/
├── lib/
│   ├── main.dart                 # 入口：加载设置、构建控制器、启动 App
│   ├── app.dart                  # 根组件：主题 + 四个 tab 的导航
│   ├── core/
│   │   ├── backend/
│   │   │   ├── easytier_backend.dart  # 后端抽象接口
│   │   │   ├── backend_factory.dart   # 自动选择 mock/FFI
│   │   │   ├── ffi_bindings.dart      # easytier-ffi C ABI 的 Dart FFI 绑定
│   │   │   ├── ffi_backend.dart       # 真实 Rust 核心后端
│   │   │   └── mock_backend.dart      # 内存模拟后端（预览/测试）
│   │   └── state/
│   │       └── easytier_controller.dart  # 状态中枢（ChangeNotifier）
│   ├── data/
│   │   ├── config/  app_settings.dart, app_theme.dart
│   │   ├── models/  network_config.dart, network_status.dart,
│   │   │            peer_info.dart, connection_state.dart
│   ├── screens/     home / networks / peers / settings
│   └── widgets/     astral_card.dart, status_pill.dart,
│                    connection_hero_card.dart
├── android/                       # Android 目标
│   └── app/src/main/
│       ├── kotlin/com/easytier/client/
│       │   ├── MainActivity.kt
│       │   ├── EasyTierVpnService.kt   # VpnService：TUN + setTunFd
│       │   └── EasyTierJni.kt          # 原生 JNI 桥（匹配官方接口）
│       └── AndroidManifest.xml
└── rust_builder/                  # 集成真实 Rust 核心的插件占位
```

## 引擎（后端）如何工作

1. **FFI 后端（真实核心）**：通过 `easytier-ffi` 的 C ABI 加载 `libeasytier_ffi`，调用
   `parse_config` / `run_network_instance` / `collect_network_infos` /
   `set_tun_fd` 等函数。在 Android 上核心 `.so` 会打进 APK。
2. **模拟后端（Mock）**：一个完整的、有状态的内存引擎，复现「连接 → 组网 → 流量」的完整链路，
   用于在没有真机/真核心时预览界面、跑测试。可在设置中强制开启。

`EasyTierBackendFactory.create()` 会根据平台和开发者开关自动选择后端。

## 构建与运行

### 环境要求
- Flutter SDK（稳定版）
- Android SDK，`ANDROID_HOME` 指向 SDK 目录
- Java 17+（Gradle 需要）

### 步骤

```bash
# 1. 进入项目
cd easytier-flutter

# 2. 安装依赖
flutter pub get

# 3. 运行到已连接的设备/模拟器
flutter run

# 4. 构建 Android APK
flutter build apk --debug
flutter build apk --release
```

### 检查 / 测试

```bash
flutter analyze
flutter test
```

### 用 GitHub Actions 自动构建

仓库内已提供 `.github/workflows/build.yml`，推到 GitHub 后会在 `ubuntu-latest`
上自动执行 `flutter pub get` → `flutter analyze` → `flutter test` →
`flutter build apk --debug/--release`，并上传 APK 作为 artifact。

要本地复现 CI，可在仓库根目录（或 `easytier-flutter/` 子目录）触发 workflow_dispatch 即可。

## 连接到真实 EasyTier 核心

默认运行使用 **Mock 后端**，在有真实核心的 Android 设备上会自动切换到 FFI 后端。
要接入真实核心：

1. 使用官方
   [`easytier-android-jni/build.sh`](https://github.com/EasyTier/EasyTier)
   交叉编译出 `libeasytier_ffi.so`（以及 `libeasytier_android_jni.so`）。
2. 拷贝到 `android/app/src/main/jniLibs/<abi>/`（如 `arm64-v8a`）。
3. 重新构建 APK。

详见 `rust_builder/README.md`。

## 说明与范围

- **当前已交付**：完整、可运行的 Material 3 客户端 UI、状态机、网络配置表单、
  节点/路由展示、设置（主题/后端/关于），以及 Android 端的 `VpnService` 与 JNI 桥骨架，
  和 FFI 真实核心的 Dart 绑定。
- **需要真机验证**：`VpnService` 的 TUN 建立与 `setTunFd`，以及真实核心联网。
- **跨平台**：目录结构已为 iOS/Windows/Linux/macOS 预留（`rust_builder` 已声明这些平台），
  后续可逐步补齐各平台目标。

## 参考
- [EasyTier/EasyTier](https://github.com/EasyTier/EasyTier) —— Rust 实现的去中心化 mesh VPN。
- [EasyTier/astral](https://github.com/EasyTier/astral) —— 参考的 Flutter + Rust 客户端设计。
