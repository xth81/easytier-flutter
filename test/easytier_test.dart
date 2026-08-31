import 'package:flutter_test/flutter_test.dart';

import 'package:easytier_flutter/core/state/easytier_controller.dart';
import 'package:easytier_flutter/data/models/network_config.dart';

void main() {
  group('NetworkConfig', () {
    test('generates valid TOML for a DHCP config', () {
      final cfg = NetworkConfig.defaults(dhcp: true, ipv4: null);
      final toml = cfg.toToml();
      expect(toml, contains('instance_name = "easytier"'));
      expect(toml, contains('dhcp = true'));
      expect(toml, contains('[network_identity]'));
      expect(toml, contains('network_name = "easytier"'));
      expect(toml, contains('network_secret = "easytier"'));
    });

    test('includes static ipv4 when not DHCP', () {
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
    });

    test('emits listeners and peers arrays', () {
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
      expect(toml, contains('tcp://1.2.3.4:11010'));
    });
  });

  group('EasyTierController with mock backend', () {
    test('disconnects then connects through the state machine', () async {
      final controller = await EasyTierController.create(forceMock: true);
      expect(controller.isConnected, isFalse);

      final cfg = NetworkConfig.defaults();
      await controller.start(cfg);
      // The mock backend moves to connecting then connected asynchronously.
      expect(controller.activeConfig, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(controller.isConnected, isTrue);
      expect(controller.status.peerCount, greaterThan(0));

      await controller.stop();
      expect(controller.isConnected, isFalse);
      controller.dispose();
    });
  });
}
