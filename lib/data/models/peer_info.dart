import 'package:flutter/foundation.dart';

/// A peer node visible in the current mesh, as surfaced by the backend.
///
/// In the real core this is populated from the `PeerInfo` / `Route` protobuf
/// messages inside `collect_network_infos`; the mock backend fills equivalent
/// values so the UI renders identically.
@immutable
class PeerInfo {
  final String hostname;
  final String ipv4;
  final int latencyMs;

  /// Whether this peer is currently directly connected (P2P) vs via a relay.
  final bool direct;

  /// Human-readable NAT/connection type, e.g. `FullCone`, `Symmetric`.
  final String natType;

  const PeerInfo({
    required this.hostname,
    required this.ipv4,
    this.latencyMs = 0,
    this.direct = false,
    this.natType = '',
  });
}

/// A single exported route announced by a peer (subnet proxy / route).
@immutable
class RouteInfo {
  /// The announced network, e.g. `192.168.1.0/24`.
  final String network;

  /// Hostname of the node announcing the route ("" when unknown).
  final String nextHop;

  /// Route cost as reported by the core.
  final int cost;

  /// Best-path latency for this route in ms (null when unknown).
  final int? latencyMs;

  const RouteInfo({
    required this.network,
    this.nextHop = '',
    this.cost = 0,
    this.latencyMs,
  });
}
