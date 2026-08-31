import 'dart:async';
import 'dart:math';

import '../../data/models/network_config.dart';
import '../../data/models/network_status.dart';
import '../../data/models/peer_info.dart';
import '../../data/models/tunnel_state.dart';
import 'easytier_backend.dart';

/// A fully-functional, in-memory [EasyTierBackend] used for the emulator,
/// tests, and desktop previews where no real EasyTier core is available.
///
/// It exercises the exact same lifecycle (connect -> mesh -> traffic) so the
/// UI behaves realistically even without a device:
///  * `start` transitions [TunnelState.connecting] then `connected`.
///  * A timer simulates peers joining, latency jitter, and traffic counters.
///  * `stop` tears everything down and returns to `disconnected`.
class MockEasyTierBackend implements EasyTierBackend {
  MockEasyTierBackend({Random? random}) : _random = random ?? Random();

  final Random _random;
  Timer? _tick;
  int _startedAt = 0;

  NetworkConfig? _config;
  List<PeerInfo> _peers = [];
  final List<RouteInfo> _routes = [];

  NetworkStatus _status = NetworkStatus.disconnected;
  int _rx = 0;
  int _tx = 0;
  bool _running = false;

  @override
  void Function(NetworkStatus status)? listener;

  @override
  String get backendName => 'Mock';

  @override
  NetworkStatus get status => _status;

  @override
  List<PeerInfo> get peers => List.unmodifiable(_peers);

  @override
  List<RouteInfo> get routes => List.unmodifiable(_routes);

  @override
  Future<void> initialize() async {
    _setStatus(NetworkStatus.disconnected);
  }

  void _setStatus(NetworkStatus s) {
    _status = s;
    listener?.call(s);
  }

  @override
  Future<void> start(NetworkConfig config) async {
    // Already running the same instance -> no-op.
    if (_running && _config?.instanceName == config.instanceName) {
      return;
    }
    await stop();

    _config = config;
    _peers = [];
    _routes.clear();
    _running = true;
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _rx = 0;
    _tx = 0;

    _setStatus(NetworkStatus(
      state: TunnelState.connecting,
      instanceName: config.instanceName,
      running: true,
    ));

    // Simulate connection establishment time.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!_running) return;

    _meshUp();

    _tick ??= Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void _meshUp() {
    // Bring up a handful of virtual peers with jittered latency.
    final baseLatency = 8 + _random.nextInt(40);
    final peers = List.generate(
      3 + _random.nextInt(3),
      (i) => PeerInfo(
        hostname: 'node-${i + 1}',
        ipv4: '10.144.144.${101 + i}',
        latencyMs: baseLatency + _random.nextInt(30),
        direct: i % 3 != 0,
        natType: i.isEven ? 'FullCone' : 'Symmetric',
      ),
    );
    _peers = peers;
    _routes
      ..clear()
      ..add(RouteInfo(
        network: '192.168.${_random.nextInt(200)}.0/24',
        nextHop: peers.first.hostname,
        cost: 1,
        latencyMs: peers.first.latencyMs,
      ));
    _setStatus(NetworkStatus(
      state: TunnelState.connected,
      instanceName: _config?.instanceName ?? '',
      ipv4: _config?.dhcp == true
          ? '10.144.144.${100 + _random.nextInt(50)}'
          : (_config?.ipv4 ?? '10.0.0.1'),
      peerCount: _peers.length,
      latencyMs: _peers.first.latencyMs,
      running: true,
    ));
  }

  void _onTick(Timer _) {
    if (!_running) return;

    // Simulate fluctuating traffic (delta bytes/sec).
    _rx = _random.nextInt(600 * 1024);
    _tx = _random.nextInt(300 * 1024);

    // Small chance a peer disconnects / reconnects to exercise the UI.
    if (_peers.isNotEmpty && _random.nextInt(40) == 0) {
      _peers = List.of(_peers)..removeAt(_random.nextInt(_peers.length));
    } else if (_peers.length < 6 && _random.nextInt(60) == 0) {
      _peers = [
        ..._peers,
        PeerInfo(
          hostname: 'node-${_peers.length + 1}',
          ipv4: '10.144.144.${120 + _peers.length}',
          latencyMs: 10 + _random.nextInt(50),
          direct: _random.nextBool(),
          natType: 'FullCone',
        ),
      ];
    }

    _setStatus(_status.copyWith(
      state: _peers.isEmpty ? TunnelState.waiting : TunnelState.connected,
      peerCount: _peers.length,
      latencyMs: _peers.isEmpty ? null : _peers.first.latencyMs,
      rxBytesPerSec: _rx,
      txBytesPerSec: _tx,
    ));
  }

  @override
  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    _running = false;
    _peers = [];
    _routes.clear();
    _setStatus(NetworkStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  @override
  Future<bool> setTunFd(int fd) async => true;

  @override
  Future<void> refresh() async {
    if (_running) _meshUp();
  }

  /// Total running time in seconds, for the dashboard timer.
  int get uptimeSeconds =>
      _running ? (DateTime.now().millisecondsSinceEpoch - _startedAt) ~/ 1000 : 0;
}
