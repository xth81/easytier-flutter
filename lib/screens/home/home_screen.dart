import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/models/tunnel_state.dart';
import '../../widgets/astral_card.dart';
import '../../widgets/connection_hero_card.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_pill.dart';

/// The primary dashboard screen: connection hero, quick config summary,
/// and a compact mesh snapshot.
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
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
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
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final status = controller.status;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyTier'),
        actions: [
          IconButton(
            tooltip: '配置网络',
            onPressed: widget.onGoConfig,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            ConnectionHeroCard(
              controller: controller,
              onToggle: () => controller.toggle(),
              onEditConfig: widget.onGoConfig,
            ),
            const SizedBox(height: 16),
            // Network identity + local node summary in one compact card.
            SectionCard(
              title: '当前网络',
              icon: Icons.dns_outlined,
              trailing: StatusPill(
                label: status.isRunning ? '运行中' : '已停止',
                color: status.isRunning ? const Color(0xFF00C853) : scheme.outline,
                icon: status.isRunning ? Icons.circle : Icons.pause_circle_outline,
              ),
              child: Column(
                children: [
                  _kv('网络名称', controller.activeConfig?.networkName ?? '--', Icons.group_outlined),
                  _kv('虚拟 IPv4', status.ipv4 ?? '未分配', Icons.lan_outlined),
                  _kv('后端', controller.backend.backendName, Icons.memory),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Quick mesh stats strip.
            _StatsStrip(controller: controller),
            const SizedBox(height: 16),
            // Compact peers preview; full table lives in the peers tab.
            SectionCard(
              title: '节点 (${controller.peers.length})',
              icon: Icons.hub_outlined,
              trailing: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('节点')),
                      body: _PeerList(controller: controller),
                    ),
                  ),
                ),
                child: const Text('全部'),
              ),
              child: _PeerPreview(controller: controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final EasyTierController controller;

  const _StatsStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = controller.status;
    return AstralCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _stat('延迟', status.latencyMs != null ? '${status.latencyMs}ms' : '--'),
          _divider(scheme),
          _stat('下行', _fmt(status.rxBytesPerSec)),
          _divider(scheme),
          _stat('上行', _fmt(status.txBytesPerSec)),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
        width: 1,
        height: 32,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      );

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _fmt(int bps) {
    if (bps >= 1024 * 1024) return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }
}

class _PeerPreview extends StatelessWidget {
  final EasyTierController controller;

  const _PeerPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peers = controller.peers.take(3).toList();
    if (peers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.hub_outlined, size: 36, color: scheme.outline),
              const SizedBox(height: 8),
              Text(
                controller.status.state == TunnelState.connected
                    ? '暂无其它节点加入'
                    : '连接后显示可达节点',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final (index, peer) in peers.indexed) ...[
          if (index > 0) const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.computer, size: 16, color: scheme.onPrimaryContainer),
            ),
            title: Text(peer.hostname,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('${peer.ipv4} · ${peer.natType}',
                style: const TextStyle(fontSize: 12)),
            trailing: Text('${peer.latencyMs}ms',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ],
    );
  }
}

class _PeerList extends StatelessWidget {
  final EasyTierController controller;

  const _PeerList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peers = controller.peers;
    if (peers.isEmpty) {
      return Center(
        child: Text('暂无节点',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: peers.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final peer = peers[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.computer, color: scheme.onPrimaryContainer),
          ),
          title: Text(peer.hostname,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${peer.ipv4} · ${peer.natType}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${peer.latencyMs}ms',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              StatusPill(
                label: peer.direct ? '直连' : '中转',
                color: peer.direct
                    ? const Color(0xFF00C853)
                    : scheme.tertiary,
                filled: false,
              ),
            ],
          ),
        );
      },
    );
  }
}
