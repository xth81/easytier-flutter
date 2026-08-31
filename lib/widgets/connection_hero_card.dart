import 'package:flutter/material.dart';

import '../core/state/easytier_controller.dart';
import '../data/models/tunnel_state.dart';
import '../data/models/network_status.dart';
import 'astral_card.dart';

/// The hero "status" card on the home screen: a large connecting action button
/// with an animated status ring and live metrics.
class ConnectionHeroCard extends StatelessWidget {
  final EasyTierController controller;
  final VoidCallback onToggle;
  final VoidCallback? onEditConfig;

  const ConnectionHeroCard({
    super.key,
    required this.controller,
    required this.onToggle,
    this.onEditConfig,
  });

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final scheme = Theme.of(context).colorScheme;

    return AstralCard(
      maxWidth: 560,
      child: Column(
        children: [
          _StatusRing(status: status, scheme: scheme),
          const SizedBox(height: 20),
          Text(
            _title(status.state),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(status),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _connectButton(status, scheme),
          if (status.isRunning) ...[
            const SizedBox(height: 20),
            _TrafficRow(status: status, scheme: scheme),
          ],
        ],
      ),
    );
  }

  String _title(TunnelState state) {
    switch (state) {
      case TunnelState.disconnected:
        return '未连接';
      case TunnelState.connecting:
        return '正在连接';
      case TunnelState.connected:
        return '已连接';
      case TunnelState.error:
        return '连接出错';
      case TunnelState.waiting:
        return '等待节点';
    }
    // Defensive fallback (unreachable for a closed enum).
    return '未知状态';
  }

  String _subtitle(NetworkStatus status) {
    if (status.state == TunnelState.connected) {
      final ip = status.ipv4 ?? 'IP 未分配';
      return '虚拟 IP: $ip  ·  ${status.peerCount} 个节点可达';
    }
    if (status.state == TunnelState.connecting) {
      return '正在建立到其它节点的连接…';
    }
    if (status.state == TunnelState.waiting) {
      return '网络已启动，等待节点接入';
    }
    return '点击按钮加入 EasyTier 网络';
  }

  Widget _connectButton(NetworkStatus status, ColorScheme scheme) {
    final active = status.isRunning;
    final bg = active ? scheme.error : scheme.primary;
    final fg = active ? scheme.onError : scheme.onPrimary;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(220, 56),
      ),
      onPressed: onToggle,
      icon: Icon(active ? Icons.stop_circle : Icons.power_settings_new),
      label: Text(active ? '断开连接' : '开始连接', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _StatusRing extends StatelessWidget {
  final NetworkStatus status;
  final ColorScheme scheme;
  const _StatusRing({required this.status, required this.scheme});

  Color get _color {
    switch (status.state) {
      case TunnelState.connected:
        return const Color(0xFF00C853);
      case TunnelState.connecting:
        return scheme.tertiary;
      case TunnelState.waiting:
        return scheme.primary;
      case TunnelState.error:
        return scheme.error;
      case TunnelState.disconnected:
        return scheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final isConnecting = status.state == TunnelState.connecting;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isConnecting)
            CircularProgressIndicator(
              strokeWidth: 3,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            )
          else
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
              ),
            ),
          Icon(
            status.state == TunnelState.connected
                ? Icons.check_rounded
                : Icons.shield_outlined,
            size: 40,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _TrafficRow extends StatelessWidget {
  final NetworkStatus status;
  final ColorScheme scheme;
  const _TrafficRow({required this.status, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _metric(
          Icons.arrow_downward,
          _fmt(status.rxBytesPerSec),
          '下行',
          scheme.primary,
        ),
        const SizedBox(width: 40),
        _metric(
          Icons.arrow_upward,
          _fmt(status.txBytesPerSec),
          '上行',
          scheme.tertiary,
        ),
        const SizedBox(width: 40),
        _metric(
          Icons.speed,
          status.latencyMs != null ? '${status.latencyMs} ms' : '--',
          '延迟',
          scheme.secondary,
        ),
      ],
    );
  }

  Widget _metric(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  String _fmt(int bps) {
    if (bps >= 1024 * 1024) return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }
}
