import 'dart:convert';

import 'network_status.dart';
import 'peer_info.dart';
import 'tunnel_state.dart';

/// Parser for the JSON snapshot produced by the official EasyTier FFI /
/// Android-JNI layer (`collect_network_infos`).
///
/// Shape (per instance key in the map):
/// ```json
/// {
///   "running": true,
///   "error_msg": null,
///   "my_node_info": {
///      "virtual_ipv4": {"address": {"addr": [10,144,144,100]}, "network_length": 24},
///      "hostname": "node-1",
///      "ips": {"ipv4_addrs": [...], "ipv6_addrs": [...], "stun_udp_ip_addrs": [...]},
///      "stun_info": {"udp_nat_type": "FullCone", "tcp_nat_type": "..."}
///   },
///   "peers": [
///      {"peer_id": 1, "default_conn_id": "...", "directly_connected_conns": ["..."],
///       "conns": [{"conn_id": "...", "is_closed": false,
///                  "stats": {"rx_bytes": 0, "tx_bytes": 0, "latency_us": 3000},
///                  "tunnel": {"tunnel_type": "p2p_udp"},
///                  "network_name": "..."}]}
///   ],
///   "routes": [
///      {"ipv4_addr": {"address": {"addr": [...]}, "network_length": 24},
///       "next_hop_peer_id": 2, "cost": 1, "path_latency": 12,
///       "hostname": "node-2", "proxy_cidrs": ["192.168.1.0/24"]}
///   ]
/// }
/// ```
class EasyTierStatusJson {
  EasyTierStatusJson._();

  /// Parse one instance snapshot into a normalized [NetworkStatus].
  static NetworkStatus parseStatus(
    Map<String, dynamic> map, {
    required String instanceName,
  }) {
    final running = map['running'] == true;
    final errorMsg = map['error_msg'] is String ? map['error_msg'] as String : null;

    final myNode = map['my_node_info'];
    String? ipv4;
    String? hostname = instanceName;
    if (myNode is Map) {
      hostname = myNode['hostname'] as String? ?? instanceName;
      ipv4 = _ipv4InetToString(myNode['virtual_ipv4']);
      if (ipv4 == null) {
        ipv4 = _firstIpv4(myNode['ips']);
      }
    }

    final peers = parsePeers(map['routes'], map['peers']);
    final routes = parseRoutes(map['routes']);

    TunnelState state;
    if (!running) {
      state = TunnelState.disconnected;
    } else if (errorMsg != null && errorMsg.isNotEmpty) {
      state = TunnelState.error;
    } else if (peers.isNotEmpty) {
      state = TunnelState.connected;
    } else {
      state = TunnelState.waiting;
    }

    var bestLatencyMs = 0;
    for (final peer in peers) {
      if (peer.latencyMs > 0 && (bestLatencyMs == 0 || peer.latencyMs < bestLatencyMs)) {
        bestLatencyMs = peer.latencyMs;
      }
    }
    final bestLatency = bestLatencyMs > 0 ? bestLatencyMs : null;

    return NetworkStatus(
      state: state,
      instanceName: instanceName,
      ipv4: ipv4,
      peerCount: peers.length,
      latencyMs: bestLatency,
      // Core counters are cumulative; the backend UI shows per-second
      // deltas from the poller, so leave these at zero here.
      rxBytesPerSec: 0,
      txBytesPerSec: 0,
      running: running,
      detail: jsonEncode(map),
      lastError: errorMsg,
    );
  }

  /// Peers are derived by merging the `routes` table (hostname / IP / NAT /
  /// path latency, one entry per peer plus the local node) with the `peers`
  /// table (connection list -> direct/relay flag, per-connection stats).
  static List<PeerInfo> parsePeers(Object? routesRaw, Object? peersRaw) {
    final result = <PeerInfo>[];

    // Index connection info by peer_id.
    final connsByPeer = <int, Map<String, dynamic>>{};
    if (peersRaw is List) {
      for (final p in peersRaw.whereType<Map>()) {
        final id = p['peer_id'];
        if (id is num) {
          connsByPeer[id.toInt()] = p.cast<String, dynamic>();
        }
      }
    }

    if (routesRaw is! List) return result;
    for (final r in routesRaw.whereType<Map>()) {
      final entry = r.cast<String, dynamic>();
      final nextHop = entry['next_hop_peer_id'] is num
          ? (entry['next_hop_peer_id'] as num).toInt()
          : -1;
      // Skip the local node's own route entry.
      if (nextHop <= 0) continue;

      String ipv4 = '';
      String hostname = 'peer$nextHop';
      String natType = '';
      final ipv4Inet = entry['ipv4_addr'];
      if (ipv4Inet is Map) {
        ipv4 = _ipv4AddrToString(ipv4Inet['address']) ?? '0.0.0.0';
      }
      if (entry['hostname'] is String && (entry['hostname'] as String).isNotEmpty) {
        hostname = entry['hostname'] as String;
      }
      natType = _natType(entry['stun_info']);

      final peerConns = connsByPeer[nextHop];
      final conns = _activeConns(peerConns?['conns']);
      final stats = _connStats(conns);
      final direct = peerConns != null && _isDirect(peerConns);

      result.add(PeerInfo(
        hostname: hostname,
        ipv4: ipv4,
        latencyMs: stats['latencyMs'] ?? 0,
        direct: direct,
        natType: natType,
      ));
    }
    return result;
  }

  /// Routes announced by peers (subnet proxies). `proxy_cidrs` of the local
  /// node's route entry are skipped.
  static List<RouteInfo> parseRoutes(Object? raw) {
    final result = <RouteInfo>[];
    final routesJson = raw;
    if (routesJson is! List) return result;

    for (final r in routesJson.whereType<Map>()) {
      final nextHopPeer = r['next_hop_peer_id'] is num
          ? (r['next_hop_peer_id'] as num).toInt()
          : -1;
      final proxyCidrs = r['proxy_cidrs'];
      if (proxyCidrs is! List) continue;
      for (final cidr in proxyCidrs.whereType<String>()) {
        final host = r['hostname'] as String? ?? 'peer$nextHopPeer';
        final latency = r['path_latency'] is num
            ? ((r['path_latency'] as num).toDouble() / 1000).round()
            : null;
        final cost = r['cost'] is num ? (r['cost'] as num).toInt() : 0;
        result.add(RouteInfo(
          network: cidr.contains('/') ? cidr : '$cidr/32',
          nextHop: host,
          cost: cost,
          latencyMs: latency,
        ));
      }
    }
    return result;
  }

  // ---- helpers ----

  static List<Map<String, dynamic>> _activeConns(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .where((c) => c['is_closed'] != true)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  static Map<String, int?> _connStats(List<Map<String, dynamic>> conns) {
    var latencyUs = 0;
    for (final conn in conns) {
      final stats = conn['stats'];
      if (stats is Map) {
        final l = stats['latency_us'];
        if (l is num && l > 0 && (latencyUs == 0 || l < latencyUs)) {
          latencyUs = l.toInt();
        }
      }
    }
    return {
      'latencyMs': latencyUs > 0 ? (latencyUs / 1000).round() : null,
    };
  }

  static bool _isDirect(Map<String, dynamic> routeEntry) {
    final defaultConnId = routeEntry['default_conn_id'];
    if (defaultConnId is! String || defaultConnId.isEmpty) return false;
    final direct = routeEntry['directly_connected_conns'];
    return direct is List && direct.whereType<String>().contains(defaultConnId);
  }

  static String _natType(Object? stun) {
    if (stun is! Map) return '';
    final udp = stun['udp_nat_type'];
    if (udp is String && udp.isNotEmpty && udp != 'Unknown') return udp;
    final tcp = stun['tcp_nat_type'];
    if (tcp is String && tcp.isNotEmpty && tcp != 'Unknown') return tcp;
    return '';
  }

  static String? _ipv4InetToString(Object? inet) {
    if (inet is! Map) return null;
    final addr = _ipv4AddrToString(inet['address']);
    if (addr == null) return null;
    final prefix = inet['network_length'];
    if (prefix is num) return '$addr/$prefix';
    return addr;
  }

  static String? _ipv4AddrToString(Object? addrObj) {
    if (addrObj is! Map) return null;
    final addr = addrObj['addr'];
    if (addr is! List) return null;
    final octets = addr.whereType<num>().map((e) => e.toInt()).toList();
    if (octets.length != 4) return null;
    return octets.join('.');
  }

  static String? _firstIpv4(Object? ips) {
    if (ips is! Map) return null;
    final v4 = ips['ipv4_addrs'];
    if (v4 is List && v4.isNotEmpty) {
      return _ipv4AddrToString(v4.first);
    }
    final stun = ips['stun_udp_ip_addrs'];
    if (stun is List && stun.isNotEmpty) {
      return _ipv4AddrToString(stun.first);
    }
    return null;
  }
}
