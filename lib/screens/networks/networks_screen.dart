import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/models/network_config.dart';
import '../../widgets/astral_card.dart';

/// The network configuration screen. Lets the user edit the network identity,
/// seed peers, IP/address mode and advanced behavior, then apply it.
class NetworksScreen extends StatefulWidget {
  final EasyTierController controller;

  const NetworksScreen({super.key, required this.controller});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen> {
  late TextEditingController _networkName;
  late TextEditingController _networkSecret;
  late TextEditingController _instanceName;
  late TextEditingController _hostname;
  late TextEditingController _ipv4;
  late TextEditingController _listeners;
  late TextEditingController _peers;

  bool _dhcp = true;
  bool _enableExitNode = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final cfg = widget.controller.activeConfig ?? NetworkConfig.defaults();
    _networkName = TextEditingController(text: cfg.networkName);
    _networkSecret = TextEditingController(text: cfg.networkSecret);
    _instanceName = TextEditingController(text: cfg.instanceName);
    _hostname = TextEditingController(text: cfg.hostname);
    _ipv4 = TextEditingController(text: cfg.ipv4 ?? '10.144.144.100');
    _listeners = TextEditingController(text: cfg.listeners.join(', '));
    _peers = TextEditingController(text: cfg.peers.join(', '));
    _dhcp = cfg.dhcp;
    _enableExitNode = cfg.enableExitNode;
  }

  @override
  void dispose() {
    _networkName.dispose();
    _networkSecret.dispose();
    _instanceName.dispose();
    _hostname.dispose();
    _ipv4.dispose();
    _listeners.dispose();
    _peers.dispose();
    super.dispose();
  }

  NetworkConfig _buildConfig() {
    return NetworkConfig(
      instanceName: _instanceName.text.trim().isEmpty
          ? NetworkConfig.defaultInstanceName
          : _instanceName.text.trim(),
      hostname: _hostname.text.trim().isEmpty ? 'easytier' : _hostname.text.trim(),
      networkName: _networkName.text.trim(),
      networkSecret: _networkSecret.text.trim(),
      listeners: _split(_listeners.text),
      peers: _split(_peers.text),
      ipv4: _dhcp ? null : _ipv4.text.trim(),
      dhcp: _dhcp,
      enableExitNode: _enableExitNode,
      extraFlags: const {},
    );
  }

  List<String> _split(String text) => text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final cfg = _buildConfig();
    if (cfg.networkName.isEmpty || cfg.networkSecret.isEmpty) {
      _snack('网络名称和网络密钥不能为空');
      return;
    }
    await widget.controller.start(cfg);
    _snack('已应用配置并启动');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        AstralCard(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: '网络身份', icon: Icons.badge_outlined),
              const SizedBox(height: 16),
              _field(_networkName, '网络名称', '与其它节点保持一致，如 easytier'),
              _field(_instanceName, '实例名称', '本机唯一标识'),
              _field(_hostname, '主机名', '显示给其它节点的名称'),
              _secretField(_networkSecret, '网络密钥'),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _dhcp,
                onChanged: (v) => setState(() => _dhcp = v),
                title: const Text('自动分配 IP (DHCP)'),
                subtitle: const Text('由 EasyTier 自动指定虚拟 IPv4'),
                contentPadding: EdgeInsets.zero,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _dhcp
                    ? const SizedBox.shrink()
                    : _field(_ipv4, '静态 IP', '如 10.144.144.100/24'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AstralCard(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: '接入点与节点', icon: Icons.public_outlined),
              const SizedBox(height: 16),
              _field(_peers, '种子节点 (Peer)', '每行一个，如 tcp://1.2.3.4:11010'),
              const SizedBox(height: 16),
              _field(_listeners, '监听地址', '如 tcp://0.0.0.0:11010'),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _enableExitNode,
                onChanged: (v) => setState(() => _enableExitNode = v),
                title: const Text('允许作为出口节点'),
                subtitle: const Text('为本网络其它节点代理转发流量'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AstralCard(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: '高级选项', icon: Icons.tune_outlined),
              const SizedBox(height: 8),
              Text(
                '这些选项可通过 TOML 配置 / RPC 进一步控制加密、协议与 P2P 行为。',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ActionChip(
                label: const Text(_showAdvanced ? '收起高级选项' : '查看高级选项'),
                avatar: Icon(_showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          maxWidth: 560,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.play_arrow),
            label: const Text('应用并连接'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          maxWidth: 560,
          child: OutlinedButton.icon(
            onPressed: () async {
              await widget.controller.stop();
              _snack('已断开连接');
            },
            icon: const Icon(Icons.stop),
            label: const Text('断开连接'),
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _secretField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(labelText: label, hintText: '网络共享密钥（明文发送给节点）'),
      ),
    );
  }
}
