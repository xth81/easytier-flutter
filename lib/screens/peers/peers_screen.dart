import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/models/peer_info.dart';
import '../../widgets/astral_card.dart';
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
    if (controller.peers.isEmpty && controller.routes.isEmpty) {
      return _empty(controller);
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AstralCard(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: '可达节点 (${controller.peers.length})',
                  icon: Icons.hub_outlined,
                ),
                const SizedBox(height: 8),
                if (controller.peers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('暂无节点',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  )
                else
                  ...controller.peers
                      .map((p) => _peerTile(context, p))
                      .expand((t) => [t, const Divider(height: 1)]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AstralCard(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: '导出路由 (${controller.routes.length})',
                  icon: Icons.alt_route,
                ),
                const SizedBox(height: 8),
                if (controller.routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('暂无路由',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  )
                else
                  ...controller.routes
                      .map((r) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.route),
                            title: Text(r.network),
                            subtitle: Text('下一跳 ${r.nextHop}'),
                            trailing: Text('${r.cost}'),
                          )),
              ],
            ),
          ),
        ],
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
      title: Text(peer.hostname, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${peer.ipv4}  ·  ${peer.natType}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${peer.latencyMs}ms',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          StatusPill(label: peer.direct ? '直连' : '中转', color: color, filled: false),
        ],
      ),
    );
  }

  Widget _empty(EasyTierController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          const Text('暂无节点信息'),
          const SizedBox(height: 8),
          Text('启动网络后，这里会显示加入的节点',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
