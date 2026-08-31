import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/config/app_settings.dart';
import '../../data/config/app_theme.dart';
import '../../widgets/section_card.dart';

/// Settings screen: theme control, backend selection, and app behavior.
/// It calls back into the parent to restyle the app and to toggle the backend.
class SettingsScreen extends StatelessWidget {
  final AppSettings settings;
  final EasyTierController controller;
  final void Function(ThemeMode mode) onThemeMode;
  final void Function(Color color) onSeedColor;
  final void Function() onBackendChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.controller,
    required this.onThemeMode,
    required this.onSeedColor,
    required this.onBackendChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // --- Appearance ---
          SectionCard(
            title: '外观',
            icon: Icons.palette_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _modeSelector(context),
                const Divider(height: 28),
                _seedColorRow(context),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- Network behavior ---
          SectionCard(
            title: '网络行为',
            icon: Icons.bolt_outlined,
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.autoStart,
                  onChanged: (v) {
                    settings.setAutoStart(v);
                    onBackendChanged();
                  },
                  title: const Text('启动时自动连接'),
                  subtitle: const Text('使用已保存的配置在应用启动后自动组网'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- Network backend ---
          SectionCard(
            title: '网络引擎',
            icon: Icons.memory,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前后端: ${controller.backend.backendName}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: settings.developerMockBackend,
                  onChanged: (v) {
                    settings.setDeveloperMockBackend(v);
                    onBackendChanged();
                  },
                  title: const Text('模拟后端（开发预览）'),
                  subtitle: const Text('无真实 EasyTier 时用于预览界面与测试流程'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- About ---
          SectionCard(
            title: '关于',
            icon: Icons.info_outline,
            child: Column(
              children: [
                _aboutRow(scheme, '应用', 'EasyTier Flutter 客户端'),
                _aboutRow(scheme, '版本', '1.0.0'),
                _aboutRow(scheme, '目标平台', 'Android（跨平台）'),
                _aboutRow(scheme, '核心', 'EasyTier (Rust) 官方核心'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _modeChip(context, ThemeMode.light, Icons.light_mode, '浅色'),
        _modeChip(context, ThemeMode.dark, Icons.dark_mode, '深色'),
        _modeChip(context, ThemeMode.system, Icons.brightness_auto, '跟随系统'),
      ],
    );
  }

  Widget _modeChip(
      BuildContext context, ThemeMode mode, IconData icon, String label) {
    final selected = settings.themeMode == mode;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onThemeMode(mode),
      avatar: Icon(icon, size: 18, color: selected ? scheme.onPrimary : null),
      label: Text(label),
    );
  }

  Widget _seedColorRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const colors = <Color>[
      AppTheme.defaultSeed, // indigo
      Color(0xFF3D5AFE), // blue
      Color(0xFF00C853), // green
      Color(0xFFFF6D00), // orange
      Color(0xFFE91E63), // pink
      Color(0xFF00BCD4), // cyan
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: settings.seedColor,
              child: const Icon(Icons.palette, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('主题色',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors
              .map((color) => _seedColorDot(context, color))
              .toList(),
        ),
      ],
    );
  }

  Widget _seedColorDot(BuildContext context, Color color) {
    final selected = settings.seedColor == color;
    return InkWell(
      onTap: () => onSeedColor(color),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }

  Widget _aboutRow(ColorScheme scheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
