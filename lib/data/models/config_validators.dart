import 'network_config.dart';

/// Validation helpers for user-provided network configuration values.
class ConfigValidators {
  ConfigValidators._();

  static final RegExp _ipv4 = RegExp(
      r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$');

  static final RegExp _cidr = RegExp(
      r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}/([0-9]|[12]\d|3[0-2])$');

  static final RegExp _url = RegExp(r'^[a-z0-9]+://[^\s]+$', caseSensitive: false);

  /// Validates the whole config and returns a list of user-presentable
  /// problems. An empty list means the config is safe to start.
  static List<String> validate(NetworkConfig config) {
    final problems = <String>[];

    if (config.instanceName.trim().isEmpty) {
      problems.add('实例名称不能为空');
    }
    if (config.hostname.trim().isEmpty) {
      problems.add('主机名不能为空');
    }
    if (config.networkName.trim().isEmpty) {
      problems.add('网络名称不能为空');
    }
    if (config.networkSecret.isEmpty) {
      problems.add('网络密钥不能为空（所有节点必须一致）');
    }

    if (!config.dhcp) {
      final ip = (config.ipv4 ?? '').trim();
      if (!_cidr.hasMatch(ip)) {
        problems.add('静态 IP 需要 CIDR 格式，例如 10.144.144.100/24');
      }
    }

    for (final listener in config.listeners) {
      if (!_url.hasMatch(listener)) {
        problems.add('监听地址无效: $listener');
      }
    }
    for (final peer in config.peers) {
      if (!_url.hasMatch(peer)) {
        problems.add('种子节点地址无效: $peer');
      }
    }
    for (final route in config.routes) {
      if (!_cidr.hasMatch(route.trim())) {
        problems.add('子网路由无效: $route');
      }
    }
    for (final exit in config.exitNodes) {
      if (!_ipv4.hasMatch(exit.trim())) {
        problems.add('出口节点 IP 无效: $exit');
      }
    }

    return problems;
  }

  static bool isValidIpv4(String value) => _ipv4.hasMatch(value.trim());
  static bool isValidCidr(String value) => _cidr.hasMatch(value.trim());
}
