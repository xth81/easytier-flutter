import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/models/connection_state.dart';
import '../../data/models/peer_info.dart';
import '../../widgets/astral_card.dart';
import '../../widgets/connection_hero_card.dart';
import '../../widgets/status_pill.dart';

/// The primary dashboard screen: connection hero, node info, and a snapshot of
/// the mesh peers/routes.
class HomeScreen extends StatefulWidget {
  final EasyTierController controller;
  /// Navigate to the networks (config) tab.
  final VoidCallback onGoConfig;

  const HomeScreen({
    super.key,
    required this.controller,
    required this.onGoConfig,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _clock;
  int _uptime = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      // Refresh uptime tick; status updates flow through ChangeNotifier.
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        ConnectionHeroCard(
          controller: controller,
          onToggle: () => controller.toggle(),
          onEditConfig: widget.onGoConfig,
        ),
        const SizedBox(height: 16),
        _NodeInfoCard(controller: controller),
        const SizedBox(height: 16),
        _PeersCard(controller: controller),
      ],
    );
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }
}

class _NodeInfoCard extends StatelessWidget {
  final EasyTierController controller;
  const _NodeInfoCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final scheme = Theme.of(context).colorScheme;
    return AstralCard(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '本机节点',
            icon: Icons.dns_outlined,
            trailing: StatusPill(
              label: status.running ? '运行中' : '已停止',
              color: status.running ? const Color(0xFF00C853) : scheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          _kv(context, '主机名', controller.activeConfig?.hostname ?? '--', scheme),
          _kv(context, '虚拟 IPv4', status.ipv4 ?? '未分配', scheme),
          _kv(context, '网络名称', controller.activeConfig?.networkName ?? '--', scheme),
          _kv(context, '后端', controller.backend.backendName, scheme),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
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

class _PeersCard extends StatelessWidget {
  final EasyTierController controller;
  const _PeersCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    final scheme = Theme.of(context).colorScheme;
    return AstralCard(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: '节点', icon: Icons.hub_outlined),
          const SizedBox(height: 12),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  controller.status.state == ConnectionState.connected
                      ? '暂无其它节点加入'
                      : '连接后显示可达节点',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ...peers.map((p) => divider(context, _peerTile(context, p, scheme))),
        ],
      ),
    );
  }

  Widget _peerTile(BuildContext context, PeerInfo peer, ColorScheme scheme) {
    final color = peer.direct ? const Color(0xFF00C853) : scheme.tertiary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.computer, color: scheme.onPrimaryContainer),
      ),
      title: Text(peer.hostname, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${peer.ipv4}  ·  ${peer.natType}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${peer.latencyMs}ms',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          StatusPill(
            label: peer.direct ? '直连' : '中转',
            color: color,
            filled: false,
          ),
        ],
      ),
    );
  }

  Widget divider(BuildContext context, Widget tile) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        tile,
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ],
    );
  }
}
