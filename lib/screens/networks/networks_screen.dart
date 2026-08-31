import 'package:flutter/material.dart';

import '../../core/state/easytier_controller.dart';
import '../../data/config/app_settings.dart';
import '../../data/models/config_validators.dart';
import '../../data/models/network_config.dart';
import '../../widgets/section_card.dart';

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
  late TextEditingController _routes;
  late TextEditingController _exitNodes;

  bool _dhcp = true;
  bool _enableExitNode = false;
  bool _noTun = false;
  bool _magicDns = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(AppSettings.instance.effectiveConfig);
  }

  @override
  void didUpdateWidget(NetworksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when the controller swapped (backend toggle) or another screen
    // saved a new config.
    if (oldWidget.controller != widget.controller) {
      final cfg = widget.controller.activeConfig ??
          AppSettings.instance.effectiveConfig;
      _load(cfg);
    }
  }

  void _load(NetworkConfig cfg) {
    _networkName = TextEditingController(text: cfg.networkName);
    _networkSecret = TextEditingController(text: cfg.networkSecret);
    _instanceName = TextEditingController(text: cfg.instanceName);
    _hostname = TextEditingController(text: cfg.hostname);
    _ipv4 = TextEditingController(text: cfg.ipv4 ?? '10.144.144.100/24');
    _listeners = TextEditingController(text: cfg.listeners.join(', '));
    _peers = TextEditingController(text: cfg.peers.join(', '));
    _routes = TextEditingController(text: cfg.routes.join(', '));
    _exitNodes = TextEditingController(text: cfg.exitNodes.join(', '));
    _dhcp = cfg.dhcp;
    _enableExitNode = cfg.enableExitNode;
    _noTun = cfg.noTun;
    _magicDns = cfg.extraFlags['accept_dns'] == true;
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
    _routes.dispose();
    _exitNodes.dispose();
    super.dispose();
  }

  NetworkConfig _buildConfig() {
    return NetworkConfig(
      instanceName: _instanceName.text.trim().isEmpty
          ? NetworkConfig.defaultInstanceName
          : _instanceName.text.trim(),
      hostname:
          _hostname.text.trim().isEmpty ? 'easytier' : _hostname.text.trim(),
      networkName: _networkName.text.trim(),
      networkSecret: _networkSecret.text.trim(),
      listeners: _split(_listeners.text),
      peers: _split(_peers.text),
      ipv4: _dhcp ? null : _ipv4.text.trim(),
      dhcp: _dhcp,
      enableExitNode: _enableExitNode,
      exitNodes: _split(_exitNodes.text),
      noTun: _noTun,
      routes: _split(_routes.text),
      extraFlags: {
        if (_magicDns) 'accept_dns': true,
      },
    );
  }

  List<String> _split(String text) => text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save({required bool connect}) async {
    final cfg = _buildConfig();

    // Persist immediately so a failed connect keeps the user's edits.
    AppSettings.instance.setSavedConfig(cfg);
    AppSettings.instance.setEnableMagicDns(_magicDns);

    final problems = ConfigValidators.validate(cfg);
    if (problems.isNotEmpty) {
      _snack(problems.first);
      return;
    }

    if (!connect) {
      _snack('配置已保存');
      return;
    }

    setState(() => _saving = true);
    final ok = await widget.controller.start(cfg);
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      _snack('已应用配置并启动');
    } else {
      _snack(widget.controller.lastError ?? '启动失败，请检查配置');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('网络配置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionCard(
            title: '网络身份',
            icon: Icons.badge_outlined,
            child: Column(
              children: [
                _field(_networkName, '网络名称', '与其它节点保持一致，如 my-network'),
                _field(_instanceName, '实例名称', '本机实例标识（默认 easytier）'),
                _field(_hostname, '主机名', '显示给其它节点的名称'),
                _secretField(_networkSecret, '网络密钥'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '地址模式',
            icon: Icons.lan_outlined,
            child: Column(
              children: [
                SwitchListTile(
                  value: _dhcp,
                  onChanged: (v) => setState(() => _dhcp = v),
                  title: const Text('自动分配 IP (DHCP)'),
                  subtitle: const Text('由 EasyTier 网络自动指定虚拟 IPv4（推荐）'),
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
          SectionCard(
            title: '接入点',
            icon: Icons.public_outlined,
            child: Column(
              children: [
                _field(_peers, '种子节点 (Peers)', '每行一个，如 tcp://1.2.3.4:11010'),
                _field(_listeners, '监听地址', '如 tcp://0.0.0.0:11010'),
                _field(_routes, '本地子网路由', '分享给其它节点的子网，如 192.168.1.0/24'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '高级选项',
            icon: Icons.tune_outlined,
            child: Column(
              children: [
                SwitchListTile(
                  value: _enableExitNode,
                  onChanged: (v) => setState(() => _enableExitNode = v),
                  title: const Text('允许作为出口节点'),
                  subtitle: const Text('为网络中的其它节点代理转发外网流量'),
                  contentPadding: EdgeInsets.zero,
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _enableExitNode
                      ? _field(
                          _exitNodes,
                          '允许经由本节点的节点 IP',
                          '仅这些节点可走本机出口；留空表示允许全部',
                        )
                      : const SizedBox.shrink(),
                ),
                const Divider(),
                SwitchListTile(
                  value: _magicDns,
                  onChanged: (v) => setState(() => _magicDns = v),
                  title: const Text('启用 Magic DNS'),
                  subtitle: const Text('用节点主机名互相访问（100.100.100.101）'),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                SwitchListTile(
                  value: _noTun,
                  onChanged: (v) => setState(() => _noTun = v),
                  title: const Text('无 TUN 模式 (no_tun)'),
                  subtitle: const Text('仅作为子网路由节点运行，不占用本机 VPN'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '提示：修改配置后点击「保存并连接」重启网络；已保存的配置会在下次启动时自动填充。',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (widget.controller.isRunning) ...[
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      await widget.controller.stop();
                      _snack('已断开连接');
                    },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('断开连接'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(connect: false),
            icon: const Icon(Icons.save_outlined),
            label: const Text('仅保存'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(connect: true),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_saving ? '正在启动…' : '保存并连接'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
        autocorrect: false,
        enableSuggestions: false,
      ),
    );
  }

  Widget _secretField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: '网络共享密钥（所有节点必须一致）',
        ),
        autocorrect: false,
        enableSuggestions: false,
      ),
    );
  }
}
