import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/config/app_settings.dart';
import '../../widgets/astral_card.dart';

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // --- Appearance ---
        AstralCard(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: '外观', icon: Icons.palette_outlined),
              const SizedBox(height: 8),
              _modeSelector(context),
              const Divider(height: 24),
              _seedColorRow(context),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // --- Network backend ---
        AstralCard(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: '网络引擎', icon: Icons.memory),
              const SizedBox(height: 12),
              Text(
                '当前后端: ${controller.backend.backendName}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
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
        AstralCard(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: '关于', icon: Icons.info_outline),
              const SizedBox(height: 12),
              _aboutRow(scheme, '应用', 'EasyTier Flutter 客户端'),
              _aboutRow(scheme, '版本', '0.1.0'),
              _aboutRow(scheme, '目标平台', 'Android（跨平台）'),
              _aboutRow(scheme, '核心', 'EasyTier (Rust)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeSelector(BuildContext context) {
    return Row(
      children: [
        _modeChip(context, ThemeMode.light, Icons.light_mode, '浅色'),
        const SizedBox(width: 8),
        _modeChip(context, ThemeMode.dark, Icons.dark_mode, '深色'),
        const SizedBox(width: 8),
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
      Color(0xFF6750A4), // indigo
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
              backgroundColor: settings.seedColor,
              child: const Icon(Icons.palette, color: Colors.white),
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
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
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
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
