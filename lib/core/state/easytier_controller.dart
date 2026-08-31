import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend_factory.dart';
import '../backend/easytier_backend.dart';
import '../../data/models/network_config.dart';
import '../../data/models/network_status.dart';
import '../../data/models/peer_info.dart';
import '../../data/models/tunnel_state.dart';

/// Central controller owning the [EasyTierBackend] instance and publishing
/// reactive status/peers/routes to the UI via [ChangeNotifier].
///
/// This is the single source of truth for `what is the network doing`, keeping
/// the widgets dumb and the logic testable.
class EasyTierController extends ChangeNotifier {
  EasyTierController(this._backend) {
    _backend.listener = _onBackendStatus;
    _lastStatusFromBackend = _backend.status;
  }

  final EasyTierBackend _backend;

  NetworkStatus _status = NetworkStatus.disconnected;
  List<PeerInfo> _peers = const [];
  List<RouteInfo> _routes = const [];
  NetworkConfig? _activeConfig;

  /// Backend implementations don't always re-emit the current snapshot after
  /// a start, so [start] snapshots it here and [status] prefers live values.
  NetworkStatus _lastStatusFromBackend = NetworkStatus.disconnected;

  NetworkStatus get status {
    // While the service reports "running" but hasn't delivered a snapshot
    // yet, keep the connecting state published at start() time.
    final live = _lastStatusFromBackend;
    if (live.state != TunnelState.connected &&
        _status.state == TunnelState.connecting &&
        live.running &&
        _activeConfig != null) {
      return _status;
    }
    return live;
  }
  List<PeerInfo> get peers => _peers;
  List<RouteInfo> get routes => _routes;
  NetworkConfig? get activeConfig => _activeConfig;
  EasyTierBackend get backend => _backend;
  bool get isConnected => status.state == TunnelState.connected;
  bool get isConnecting => status.state == TunnelState.connecting;
  bool get isRunning => status.running || isConnecting;
  String? get lastError => status.lastError;

  /// Create a controller, auto-selecting mock vs FFI/service backend.
  static Future<EasyTierController> create({bool forceMock = false}) async {
    final backend = await EasyTierBackendFactory.create(forceMock: forceMock);
    return EasyTierController(backend);
  }

  void _onBackendStatus(NetworkStatus status) {
    _status = status;
    _lastStatusFromBackend = status;
    _peers = _backend.peers;
    _routes = _backend.routes;
    notifyListeners();
  }

  /// Start the network described by [config].
  ///
  /// Failures from the real core are converted into an error status instead of
  /// escaping as unhandled exceptions, so the UI always has a state to show.
  Future<bool> start(NetworkConfig config) async {
    _activeConfig = config;
    _status = NetworkStatus(
      state: TunnelState.connecting,
      instanceName: config.instanceName,
      running: true,
    );
    notifyListeners();
    try {
      await _backend.start(config);
    } on BackendException catch (e) {
      _status = NetworkStatus(
        state: TunnelState.error,
        instanceName: config.instanceName,
        running: false,
        lastError: e.message,
      );
      _lastStatusFromBackend = _status;
      notifyListeners();
      return false;
    } catch (e) {
      _status = NetworkStatus(
        state: TunnelState.error,
        instanceName: config.instanceName,
        running: false,
        lastError: e.toString(),
      );
      _lastStatusFromBackend = _status;
      notifyListeners();
      return false;
    }
    _lastStatusFromBackend = _backend.status;
    _peers = _backend.peers;
    _routes = _backend.routes;
    notifyListeners();
    return _lastStatusFromBackend.running ||
        _lastStatusFromBackend.state == TunnelState.connecting;
  }

  /// Stop the running network.
  Future<void> stop() async {
    await _backend.stop();
    _status = _backend.status;
    _lastStatusFromBackend = _status;
    _peers = const [];
    _routes = const [];
    _activeConfig = null;
    notifyListeners();
  }

  /// Toggle connect/disconnect based on current state.
  Future<void> toggle() async {
    if (isRunning || isConnecting) {
      await stop();
    } else {
      final config = _activeConfig ?? NetworkConfig.defaults();
      await start(config);
    }
  }
  /// Refresh status/peers (pull-to-refresh).
  Future<void> refresh() async {
    await _backend.refresh();
    _status = _backend.status;
    _lastStatusFromBackend = _status;
    _peers = _backend.peers;
    _routes = _backend.routes;
    notifyListeners();
  }

  @override
  void dispose() {
    _backend.listener = null;
    unawaited(_backend.dispose());
    super.dispose();
  }
}
