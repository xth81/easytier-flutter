import 'package:flutter/material.dart';

import '../core/state/easytier_controller.dart';
import '../data/models/network_status.dart';
import '../data/models/tunnel_state.dart';
import 'astral_card.dart';

/// The hero status card on the home screen: a compact connection action with
/// an animated status indicator, live metrics, and the primary toggle.
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
    final color = _colorFor(status, scheme);

    return AstralCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(status.state),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(status),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusIndicator(status: status, color: color),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        status.isRunning ? scheme.error : scheme.primary,
                    foregroundColor:
                        status.isRunning ? scheme.onError : scheme.onPrimary,
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: onToggle,
                  icon: Icon(status.isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.power_settings_new),
                  label: Text(
                    status.isRunning ? '断开连接' : '开始连接',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (onEditConfig != null) ...[
                const SizedBox(width: 12),
                IconButton.outlined(
                  onPressed: onEditConfig,
                  tooltip: '配置网络',
                  icon: const Icon(Icons.tune),
                ),
              ],
            ],
          ),
          if (status.lastError != null && status.lastError!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: status.lastError!),
          ],
          if (status.isRunning) ...[
            const SizedBox(height: 20),
            _MetricsRow(status: status, scheme: scheme),
          ],
        ],
      ),
    );
  }

  static Color _colorFor(NetworkStatus status, ColorScheme scheme) =>
      switch (status.state) {
        TunnelState.connected => const Color(0xFF00C853),
        TunnelState.connecting => scheme.tertiary,
        TunnelState.waiting => scheme.primary,
        TunnelState.error => scheme.error,
        TunnelState.disconnected => scheme.outline,
      };

  String _title(TunnelState state) => switch (state) {
        TunnelState.disconnected => '未连接',
        TunnelState.connecting => '正在连接',
        TunnelState.connected => '已连接',
        TunnelState.error => '连接出错',
        TunnelState.waiting => '等待节点',
      };

  String _subtitle(NetworkStatus status) {
    if (status.state == TunnelState.connected) {
      final ip = status.ipv4 ?? 'IP 分配中';
      return '$ip · ${status.peerCount} 个节点可达';
    }
    if (status.state == TunnelState.connecting) {
      return '正在建立到其它节点的连接…';
    }
    if (status.state == TunnelState.waiting) {
      return '网络已启动，等待节点接入';
    }
    if (status.state == TunnelState.error) {
      return '启动失败，请检查配置';
    }
    return '点击按钮加入 EasyTier 网络';
  }
}

class _StatusIndicator extends StatelessWidget {
  final NetworkStatus status;
  final Color color;

  const _StatusIndicator({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connecting = status.state == TunnelState.connecting;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (connecting)
            CircularProgressIndicator(
              strokeWidth: 3,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            )
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
                border: Border.all(color: color.withValues(alpha: 0.45), width: 2),
              ),
            ),
          Icon(
            status.state == TunnelState.connected
                ? Icons.check_rounded
                : status.state == TunnelState.error
                    ? Icons.priority_high_rounded
                    : Icons.shield_outlined,
            size: 26,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  final NetworkStatus status;
  final ColorScheme scheme;

  const _MetricsRow({required this.status, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _metric(Icons.arrow_downward, _fmt(status.rxBytesPerSec), '下行',
            scheme.primary),
        const SizedBox(width: 32),
        _metric(Icons.arrow_upward, _fmt(status.txBytesPerSec), '上行',
            scheme.tertiary),
        const SizedBox(width: 32),
        _metric(Icons.speed,
            status.latencyMs != null ? '${status.latencyMs} ms' : '--', '延迟',
            scheme.secondary),
      ],
    );
  }

  Widget _metric(IconData icon, String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  String _fmt(int bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }
}
