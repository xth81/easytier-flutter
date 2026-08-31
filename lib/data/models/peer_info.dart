/// A peer node visible in the current mesh, as surfaced by the backend.
///
/// In the real core this is populated from `ListPeer`/`ShowNodeInfo` RPCs; the
/// mock backend fills equivalent values so the UI renders identically.
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
class RouteInfo {
  final String network;
  final String nextHop;
  final int cost;

  const RouteInfo({
    required this.network,
    required this.nextHop,
    this.cost = 0,
  });
}
