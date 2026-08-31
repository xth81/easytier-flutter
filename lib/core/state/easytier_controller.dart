import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend_factory.dart';
import '../backend/easytier_backend.dart';
import '../../data/models/tunnel_state.dart';
import '../../data/models/network_config.dart';
import '../../data/models/network_status.dart';
import '../../data/models/peer_info.dart';

/// Central controller owning the [EasyTierBackend] instance and publishing
/// reactive status/peers/routes to the UI via [ChangeNotifier].
///
/// This is the single source of truth for `what is the network doing`, keeping
/// the widgets dumb and the logic testable. It is constructed lazily by the
/// app (see `AppControllerScope`) and disposed on app teardown.
class EasyTierController extends ChangeNotifier {
  EasyTierController(this._backend) {
    _backend.listener = _onBackendStatus;
  }

  final EasyTierBackend _backend;

  NetworkStatus _status = NetworkStatus.disconnected;
  List<PeerInfo> _peers = const [];
  List<RouteInfo> _routes = const [];
  NetworkConfig? _activeConfig;

  NetworkStatus get status => _status;
  List<PeerInfo> get peers => _peers;
  List<RouteInfo> get routes => _routes;
  NetworkConfig? get activeConfig => _activeConfig;
  EasyTierBackend get backend => _backend;
  bool get isConnected => _status.state == TunnelState.connected;
  bool get isConnecting => _status.state == TunnelState.connecting;

  /// Create a controller, auto-selecting mock vs FFI backend.
  static Future<EasyTierController> create({bool forceMock = false}) async {
    final backend = await EasyTierBackendFactory.create(forceMock: forceMock);
    return EasyTierController(backend);
  }

  void _onBackendStatus(NetworkStatus status) {
    _status = status;
    _peers = _backend.peers;
    _routes = _backend.routes;
    notifyListeners();
  }

  /// Start the network described by [config].
  Future<void> start(NetworkConfig config) async {
    _activeConfig = config;
    notifyListeners();
    await _backend.start(config);
    _status = _backend.status;
    _peers = _backend.peers;
    notifyListeners();
  }

  /// Stop the running network.
  Future<void> stop() async {
    await _backend.stop();
    _status = _backend.status;
    _peers = const [];
    _routes = const [];
    _activeConfig = null;
    notifyListeners();
  }

  /// Toggle connect/disconnect based on current state.
  Future<void> toggle() async {
    if (isConnected || isConnecting) {
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
