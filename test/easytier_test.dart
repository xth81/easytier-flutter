import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:easytier_flutter/core/state/easytier_controller.dart';
import 'package:easytier_flutter/data/models/config_validators.dart';
import 'package:easytier_flutter/data/models/network_config.dart';
import 'package:easytier_flutter/data/models/network_status.dart';
import 'package:easytier_flutter/data/models/peer_info.dart';
import 'package:easytier_flutter/data/models/status_json.dart';
import 'package:easytier_flutter/data/models/tunnel_state.dart';

void main() {
  group('NetworkConfig', () {
    test('generates valid TOML for a DHCP config', () {
      final cfg = NetworkConfig.defaults(dhcp: true, ipv4: null);
      final toml = cfg.toToml();
      expect(toml, contains('instance_name = "easytier"'));
      expect(toml, contains('hostname = "easytier"'));
      expect(toml, contains('dhcp = true'));
      expect(toml, contains('[network_identity]'));
      expect(toml, contains('network_name = "easytier"'));
      expect(toml, contains('network_secret = "easytier"'));
      expect(toml, contains('listeners = ["tcp://0.0.0.0:11010"'));
    });

    test('includes static ipv4 as a top-level key when not DHCP', () {
      const cfg = NetworkConfig(
        instanceName: 'n',
        hostname: 'host',
        networkName: 'mynet',
        networkSecret: 'secret',
        ipv4: '10.144.144.100/24',
        dhcp: false,
      );
      final toml = cfg.toToml();
      expect(toml, contains('dhcp = false'));
      expect(toml, contains('ipv4 = "10.144.144.100/24"'));
      expect(toml, isNot(contains('[flags]\nipv4')));
    });

    test('emits listeners and [[peer]] entries', () {
      const cfg = NetworkConfig(
        instanceName: 'n',
        hostname: 'h',
        networkName: 'net',
        networkSecret: 'sec',
        listeners: ['tcp://0.0.0.0:11010', 'udp://0.0.0.0:11010'],
        peers: ['tcp://1.2.3.4:11010'],
      );
      final toml = cfg.toToml();
      expect(toml, contains('tcp://0.0.0.0:11010'));
      expect(toml, contains('udp://0.0.0.0:11010'));
      expect(toml, contains('[[peer]]'));
      expect(toml, contains('uri = "tcp://1.2.3.4:11010"'));
    });

    test('emits exit node / route / magic dns flags', () {
      const cfg = NetworkConfig(
        instanceName: 'n',
        hostname: 'h',
        networkName: 'net',
        networkSecret: 'sec',
        dhcp: true,
        enableExitNode: true,
        exitNodes: ['10.144.144.2'],
        routes: ['192.168.1.0/24'],
        extraFlags: {'accept_dns': true},
      );
      final toml = cfg.toToml();
      expect(toml, contains('exit_nodes = ["10.144.144.2"]'));
      expect(toml, contains('routes = ["192.168.1.0/24"]'));
      expect(toml, contains('[flags]'));
      expect(toml, contains('enable_exit_node = true'));
      expect(toml, contains('accept_dns = true'));
    });

    test('round-trips through JSON', () {
      final cfg = NetworkConfig.defaults().copyWith(
        networkName: 'mynet',
        routes: const ['192.168.1.0/24'],
        exitNodes: const ['10.144.144.2'],
      );
      final restored = NetworkConfig.fromJson(jsonDecode(jsonEncode(cfg.toJson()))
          as Map<String, dynamic>);
      expect(restored.toToml(), cfg.toToml());
    });
  });

  group('ConfigValidators', () {
    test('accepts a default config', () {
      expect(ConfigValidators.validate(NetworkConfig.defaults()), isEmpty);
    });

    test('rejects bad static ip and bad peer url', () {
      final cfg = NetworkConfig.defaults().copyWith(
        dhcp: false,
        ipv4: '999.1.1.1/24',
        peers: const ['1.2.3.4:11010'],
      );
      final problems = ConfigValidators.validate(cfg);
      expect(problems, isNotEmpty);
      expect(problems.any((p) => p.contains('静态 IP')), isTrue);
      expect(problems.any((p) => p.contains('种子节点')), isTrue);
    });
  });

  group('EasyTierStatusJson', () {
    final sample = jsonDecode('''
    {
      "running": true,
      "my_node_info": {
        "hostname": "node-a",
        "virtual_ipv4": {"address": {"addr": [10, 144, 144, 100]}, "network_length": 24}
      },
      "peers": [
        {
          "peer_id": 2,
          "default_conn_id": "conn-1",
          "directly_connected_conns": ["conn-1"],
          "conns": [
            {"conn_id": "conn-1", "is_closed": false,
             "stats": {"rx_bytes": 1024, "tx_bytes": 2048, "latency_us": 3300}}
          ]
        }
      ],
      "routes": [
        {"peer_id": 1, "next_hop_peer_id": 0, "ipv4_addr": {"address": {"addr": [10,144,144,100]}, "network_length": 24},
         "hostname": "node-a", "stun_info": {"udp_nat_type": "FullCone"}},
        {"peer_id": 2, "next_hop_peer_id": 2, "ipv4_addr": {"address": {"addr": [10,144,144,101]}, "network_length": 24},
         "hostname": "node-b", "stun_info": {"udp_nat_type": "Symmetric"},
         "proxy_cidrs": ["192.168.1.0/24"], "cost": 1, "path_latency": 4500}
      ]
    }
    ''') as Map<String, dynamic>;

    test('parses local status', () {
      final status =
          EasyTierStatusJson.parseStatus(sample, instanceName: 'easytier');
      expect(status.state, TunnelState.connected);
      expect(status.ipv4, '10.144.144.100/24');
      expect(status.peerCount, 1);
      expect(status.latencyMs, 3);
      expect(status.rxBytesPerSec, 0);
    });

    test('parses peers and routes from the snapshot', () {
      final peers = EasyTierStatusJson.parsePeers(
          sample['routes'], sample['peers']);
      expect(peers, hasLength(1));
      final peer = peers.first as PeerInfo;
      expect(peer.hostname, 'node-b');
      expect(peer.ipv4, '10.144.144.101');
      expect(peer.natType, 'Symmetric');
      expect(peer.direct, isTrue);
      expect(peer.latencyMs, 3);

      final routes = EasyTierStatusJson.parseRoutes(sample['routes']);
      expect(routes, hasLength(1));
      final route = routes.first as RouteInfo;
      expect(route.network, '192.168.1.0/24');
      expect(route.nextHop, 'node-b');
      expect(route.latencyMs, 5);
    });

    test('parses uint32 protobuf JSON addresses', () {
      // prost/pbjson serializes Ipv4Addr.addr as the raw uint32
      // (host byte order), not as an array.
      final snapshot = jsonDecode('''
      {
        "running": true,
        "my_node_info": {
          "hostname": "node-a",
          "virtual_ipv4": {"address": {"addr": 177246308}, "network_length": 24}
        },
        "peers": [],
        "routes": [
          {"peer_id": 1, "next_hop_peer_id": 0,
           "ipv4_addr": {"address": {"addr": 177246308}, "network_length": 24},
           "hostname": "node-a"}
        ]
      }
      ''') as Map<String, dynamic>;
      final status = EasyTierStatusJson.parseStatus(
          snapshot, instanceName: 'easytier');
      expect(status.ipv4, '10.144.144.100/24');
    });

    test('falls back to error state when core reports error', () {
      final status = EasyTierStatusJson.parseStatus(
        {'running': false, 'error_msg': 'failed to start'},
        instanceName: 'easytier',
      );
      expect(status.state, TunnelState.disconnected);
      expect(status.lastError, 'failed to start');
    });
  });

  group('EasyTierController with mock backend', () {
    test('disconnects then connects through the state machine', () async {
      final controller = await EasyTierController.create(forceMock: true);
      expect(controller.isConnected, isFalse);

      final cfg = NetworkConfig.defaults();
      final ok = await controller.start(cfg);
      expect(ok, isTrue);
      // The mock backend moves to connecting then connected asynchronously.
      expect(controller.activeConfig, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(controller.isConnected, isTrue);
      expect(controller.status.peerCount, greaterThan(0));

      await controller.stop();
      expect(controller.isConnected, isFalse);
      expect(controller.status.state, TunnelState.disconnected);
      controller.dispose();
    });

    test('NetworkStatus copyWith preserves fields', () {
      const status = NetworkStatus(
        state: TunnelState.connecting,
        instanceName: 'easytier',
        running: true,
      );
      final next = status.copyWith(peerCount: 4);
      expect(next.state, TunnelState.connecting);
      expect(next.peerCount, 4);
      expect(next.running, isTrue);
    });
  });
}
