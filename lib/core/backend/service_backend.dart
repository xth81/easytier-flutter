import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../data/models/network_config.dart';
import '../../data/models/network_status.dart';
import '../../data/models/peer_info.dart';
import '../../data/models/status_json.dart';
import '../../data/models/tunnel_state.dart';
import 'easytier_backend.dart';

/// Android backend that drives the `:vpn` service process.
///
/// The service runs the vendored EasyTier Rust core in its own process:
///  * [start] asks the user for the VPN consent, then starts the service with
///    the TOML config; the service establishes the TUN and calls the core.
///  * [refresh] queries the service through the MethodChannel (the native side
///    forwards the call over Binder to the `:vpn` process) and parses the
///    official `collect_network_infos` JSON snapshot.
///  * The service also pushes state changes back through the channel.
///
/// TUN parameters (routes, DNS) follow the official client's model:
///  * announce local [NetworkConfig.routes] verbatim;
///  * route all remote subnet proxies (peers' `proxy_cidrs`);
///  * use the core's magic DNS (100.100.100.101) when DNS is enabled.
class AndroidServiceBackend implements EasyTierBackend {
  AndroidServiceBackend({this.pollInterval = const Duration(seconds: 3)});

  static const MethodChannel _channel = MethodChannel('com.easytier.client/vpn');

  final Duration pollInterval;

  Timer? _poll;
  NetworkConfig? _activeConfig;
  NetworkStatus _status = NetworkStatus.disconnected;
  List<PeerInfo> _peers = const [];
  List<RouteInfo> _routes = const [];
  String _lastError = '';
  bool _starting = false;

  /// Whether the real native core libraries are bundled in this APK.
  static Future<bool> isCoreAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  void Function(NetworkStatus status)? listener;

  @override
  String get backendName => 'Service (Android)';

  @override
  NetworkStatus get status => _status;

  @override
  List<PeerInfo> get peers => List.unmodifiable(_peers);

  @override
  List<RouteInfo> get routes => List.unmodifiable(_routes);

  @override
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_onNativeEvent);
    await _refreshOnce();
    _poll ??= Timer.periodic(pollInterval, (_) => _refreshOnce());
  }

  Future<dynamic> _onNativeEvent(MethodCall call) async {
    if (call.method == 'serviceStateChanged') {
      final payload = call.arguments;
      if (payload is String) {
        try {
          final map = jsonDecode(payload) as Map<String, dynamic>;
          final infos = map['infos'];
          if (infos is String && infos.isNotEmpty) {
            _applyInfosJson(infos);
          } else {
            final running = map['running'] == true;
            _applyRunning(running);
          }
        } catch (_) {
          // Ignore malformed events; the poll will correct state.
        }
      }
    }
  }

  @override
  Future<void> start(NetworkConfig config) async {
    if (_starting) return;
    _starting = true;
    _activeConfig = config;
    _lastError = '';
    _setStatus(NetworkStatus(
      state: TunnelState.connecting,
      instanceName: config.instanceName,
      running: true,
    ));
    try {
      // Ask for VPN consent first (triggers the Android dialog on first use).
      final prepared = await _channel.invokeMethod<bool>('prepareVpn');
      if (!(prepared ?? false)) {
        _lastError = '未授予 VPN 权限';
        _setStatus(NetworkStatus(
          state: TunnelState.disconnected,
          instanceName: config.instanceName,
          running: false,
          lastError: _lastError,
        ));
        return;
      }

      final args = <String, dynamic>{
        'config': config.toToml(),
        'ipv4': _tunIpv4(config),
        'routes': _tunRoutes(config),
        'dns': _dnsEnabled(config) ? '100.100.100.101' : null,
      };
      final started = await _channel.invokeMethod<bool>('startVpn', args);
      if (!(started ?? false)) {
        _lastError = '启动 VPN 服务失败';
        _setStatus(NetworkStatus(
          state: TunnelState.disconnected,
          instanceName: config.instanceName,
          running: false,
          lastError: _lastError,
        ));
        return;
      }
      // The service reports authoritative state through events/polling.
      await _refreshOnce();
    } on PlatformException catch (e) {
      _lastError = e.message ?? '启动失败';
      _setStatus(NetworkStatus(
        state: TunnelState.error,
        instanceName: config.instanceName,
        running: false,
        lastError: _lastError,
      ));
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopVpn');
    } catch (_) {
      // Ignore: the service may already be gone.
    }
    _status = NetworkStatus.disconnected;
    _peers = const [];
    _routes = const [];
    _activeConfig = null;
    _lastError = '';
    listener?.call(_status);
  }

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    _poll = null;
    _channel.setMethodCallHandler(null);
  }

  @override
  Future<bool> setTunFd(int fd) async => false;

  @override
  Future<void> refresh() async => _refreshOnce();

  Future<void> _refreshOnce() async {
    if (_starting) return;
    try {
      final running = await _channel.invokeMethod<bool>('isRunning') ?? false;
      if (!running) {
        _applyRunning(false);
        return;
      }
      final infos = await _channel.invokeMethod<String>('collectInfos');
      if (infos != null && infos.isNotEmpty) {
        _applyInfosJson(infos);
        return;
      }
      _applyRunning(true);
    } catch (_) {
      // Channel may be unavailable while the engine is restarting.
    }
  }

  void _applyRunning(bool running) {
    if (!running) {
      if (_status.running || _status.state != TunnelState.disconnected) {
        _setStatus(NetworkStatus.disconnected);
      }
      return;
    }
    if (!_status.running) {
      _setStatus(NetworkStatus(
        state: TunnelState.connecting,
        instanceName: _activeConfig?.instanceName ?? 'easytier',
        running: true,
      ));
    }
  }

  void _applyInfosJson(String infosJson) {
    try {
      final decoded = jsonDecode(infosJson) as Map<String, dynamic>;
      // The JNI layer serializes a protobuf `NetworkInstanceRunningInfoMap`,
      // which prost encodes as {"map": {"<instance>": {...}}}. Accept both
      // that shape and a bare map for robustness.
      final raw = decoded['map'] is Map
          ? (decoded['map'] as Map).cast<String, dynamic>()
          : decoded;

      final name =
          _activeConfig?.instanceName ?? NetworkConfig.defaultInstanceName;
      var snapshot = raw[name];
      if (snapshot is! Map) {
        // Single-instance mode: take the only entry.
        if (raw.length == 1) snapshot = raw.values.first;
      }
      if (snapshot is! Map) return;

      final map = snapshot.cast<String, dynamic>();
      final status =
          EasyTierStatusJson.parseStatus(map, instanceName: name);
      _peers = EasyTierStatusJson.parsePeers(map['routes'], map['peers']);
      _routes = EasyTierStatusJson.parseRoutes(map['routes']);
      _lastError = map['error_msg'] is String ? map['error_msg'] as String : '';
      _setStatus(status.copyWith(lastError: _lastError.isEmpty ? null : _lastError));
    } catch (_) {
      // Keep the last known state rather than flapping.
    }
  }

  void _setStatus(NetworkStatus s) {
    _status = s;
    listener?.call(s);
  }

  String _tunIpv4(NetworkConfig config) {
    if (!config.dhcp && (config.ipv4?.isNotEmpty ?? false)) {
      return config.ipv4!;
    }
    // DHCP mode: the core assigns the IP; use the EasyTier default pool so
    // the VPN interface is up even before the first DHCP offer arrives.
    return '10.144.144.100';
  }

  List<String> _tunRoutes(NetworkConfig config) {
    final routes = <String>{
      // Keep the mesh subnet routed through the VPN interface.
      '10.144.144.0/24',
      ...config.routes.where((r) => r.isNotEmpty),
      // Magic DNS endpoint.
      if (_dnsEnabled(config)) '100.100.100.101/32',
      // Remote subnet proxies announced by peers.
      ..._routes.map((r) => r.network),
    };
    return routes.toList();
  }

  bool _dnsEnabled(NetworkConfig config) =>
      config.extraFlags['accept_dns'] == true;
}
