import 'package:flutter/material.dart';

import 'core/state/easytier_controller.dart';
import 'data/config/app_settings.dart';
import 'data/config/app_theme.dart';
import 'screens/home/home_screen.dart';
import 'screens/networks/networks_screen.dart';
import 'screens/peers/peers_screen.dart';
import 'screens/settings/settings_screen.dart';

/// The root widget that owns navigation between the four tabs and drives
/// app-level theme changes. The backend controller is owned by the entrypoint
/// (`main.dart`) and passed in; a callback lets the app swap it at runtime.
class EasyTierApp extends StatefulWidget {
  final EasyTierController controller;
  final void Function(EasyTierController next)? onControllerChanged;

  const EasyTierApp({
    super.key,
    required this.controller,
    this.onControllerChanged,
  });

  @override
  State<EasyTierApp> createState() => _EasyTierAppState();
}

class _EasyTierAppState extends State<EasyTierApp> {
  final AppSettings _settings = AppSettings.instance;
  late EasyTierController _controller = widget.controller;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyTier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seedColor: _settings.seedColor),
      darkTheme: AppTheme.dark(seedColor: _settings.seedColor),
      themeMode: _settings.themeMode,
      home: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            controller: _controller,
            onGoConfig: () => setState(() => _tab = 1),
          ),
          NetworksScreen(controller: _controller),
          PeersScreen(controller: _controller),
          SettingsScreen(
            settings: _settings,
            controller: _controller,
            onThemeMode: (mode) {
              _settings.setThemeMode(mode);
              setState(() {});
            },
            onSeedColor: (color) {
              _settings.setSeedColor(color);
              setState(() {});
            },
            onBackendChanged: _swapBackend,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_ethernet_outlined),
            selectedIcon: Icon(Icons.settings_ethernet),
            label: '网络',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: '节点',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  Future<void> _swapBackend() async {
    final next = await EasyTierController.create(
      forceMock: _settings.developerMockBackend,
    );
    final old = _controller;
    setState(() {
      _controller = next;
      _controller.addListener(_onControllerChanged);
    });
    old.dispose();
    widget.onControllerChanged?.call(next);
  }
}
