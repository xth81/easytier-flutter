import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/models/peer_info.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_pill.dart';

/// Dedicated peer & route inspector. Shows every reachable node and the routes
/// it exports, mirroring EasyTier's `ListPeer` / `ListRoute` views.
class PeersScreen extends StatefulWidget {
  final EasyTierController controller;

  const PeersScreen({super.key, required this.controller});

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(PeersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('节点与路由')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SectionCard(
              title: '可达节点 (${controller.peers.length})',
              icon: Icons.hub_outlined,
              trailing: StatusPill(
                label: controller.isConnected ? '在线' : '离线',
                color: controller.isConnected
                    ? const Color(0xFF00C853)
                    : scheme.outline,
                icon: controller.isConnected
                    ? Icons.circle
                    : Icons.pause_circle_outline,
              ),
              child: _PeersContent(controller: controller),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '导出路由 (${controller.routes.length})',
              icon: Icons.alt_route,
              child: _RoutesContent(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeersContent extends StatelessWidget {
  final EasyTierController controller;

  const _PeersContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peers = controller.peers;
    if (peers.isEmpty) {
      return _empty(context, Icons.hub_outlined, '暂无节点',
          '启动网络后，这里会显示加入的节点');
    }
    return Column(
      children: [
        for (final (index, peer) in peers.indexed) ...[
          if (index > 0) const Divider(height: 1),
          _peerTile(context, peer),
        ],
      ],
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: scheme.outline),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(hint,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _peerTile(BuildContext context, PeerInfo peer) {
    final scheme = Theme.of(context).colorScheme;
    final color = peer.direct ? const Color(0xFF00C853) : scheme.tertiary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.computer, color: scheme.onPrimaryContainer),
      ),
      title: Text(peer.hostname,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${peer.ipv4} · ${peer.natType.isEmpty ? '未知 NAT' : peer.natType}',
      ),
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
}

class _RoutesContent extends StatelessWidget {
  final EasyTierController controller;

  const _RoutesContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final routes = controller.routes;
    if (routes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.alt_route, size: 36, color: scheme.outline),
              const SizedBox(height: 8),
              Text('暂无路由',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12.5)),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final (index, route) in routes.indexed) ...[
          if (index > 0) const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.route, color: scheme.primary),
            title: Text(route.network,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    fontSize: 14)),
            subtitle: Text(
              '下一跳 ${route.nextHop.isEmpty ? '未知' : route.nextHop}'
              '${route.latencyMs != null ? ' · ${route.latencyMs}ms' : ''}',
            ),
            trailing: Text('cost ${route.cost}',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12.5)),
          ),
        ],
      ],
    );
  }
}
