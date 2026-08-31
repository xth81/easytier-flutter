/// A single running network configuration, mirroring the fields exposed by the
/// EasyTier core (`TomlConfigLoader`) through the FFI bridge.
///
/// This is the canonical model the app builds a TOML config from and hands to
/// the backend when the user starts a network.
class NetworkConfig {
  /// Unique, stable instance name on this device. Must be unique among
  /// instances started through the same backend.
  final String instanceName;

  /// Hostname of this node as seen by peers.
  final String hostname;

  /// EasyTier network name (group identity).
  final String networkName;

  /// Shared secret that authenticates this node to the network.
  final String networkSecret;

  /// Listeners this node exposes for inbound connections,
  /// e.g. `tcp://0.0.0.0:11010`, `udp://0.0.0.0:11010`, `ws://...`.
  final List<String> listeners;

  /// Peer nodes this node connects to on startup, e.g. `tcp://1.2.3.4:11010`.
  final List<String> peers;

  /// Static IPv4 (~with `/prefix`) assigned to this node,
  /// or `null` when the node runs in DHCP mode.
  final String? ipv4;

  /// When true the core auto-assigns an IPv4 from the network pool.
  final bool dhcp;

  /// When true this node is allowed to act as a subnet proxy for the network.
  final bool enableExitNode;

  /// Extra free-form flags merged into the generated TOML.
  final Map<String, dynamic> extraFlags;

  const NetworkConfig({
    required this.instanceName,
    required this.hostname,
    required this.networkName,
    required this.networkSecret,
    this.listeners = const [],
    this.peers = const [],
    this.ipv4,
    this.dhcp = false,
    this.enableExitNode = false,
    this.extraFlags = const {},
  });

  /// The default instance name the app uses for the primary network.
  static const String defaultInstanceName = 'easytier';

  /// Build a sensible default network config matching EasyTier's defaults.
  factory NetworkConfig.defaults({
    String instanceName = defaultInstanceName,
    String networkName = 'easytier',
    String networkSecret = 'easytier',
    String? ipv4,
    bool dhcp = true,
  }) {
    return NetworkConfig(
      instanceName: instanceName,
      hostname: 'easytier',
      networkName: networkName,
      networkSecret: networkSecret,
      listeners: const [
        'tcp://0.0.0.0:11010',
        'udp://0.0.0.0:11010',
        'ws://0.0.0.0:11011',
      ],
      peers: const [],
      ipv4: ipv4,
      dhcp: dhcp,
      enableExitNode: false,
    );
  }

  NetworkConfig copyWith({
    String? instanceName,
    String? hostname,
    String? networkName,
    String? networkSecret,
    List<String>? listeners,
    List<String>? peers,
    String? ipv4,
    bool? dhcp,
    bool? enableExitNode,
    Map<String, dynamic>? extraFlags,
  }) {
    return NetworkConfig(
      instanceName: instanceName ?? this.instanceName,
      hostname: hostname ?? this.hostname,
      networkName: networkName ?? this.networkName,
      networkSecret: networkSecret ?? this.networkSecret,
      listeners: listeners ?? this.listeners,
      peers: peers ?? this.peers,
      ipv4: ipv4 ?? this.ipv4,
      dhcp: dhcp ?? this.dhcp,
      enableExitNode: enableExitNode ?? this.enableExitNode,
      extraFlags: extraFlags ?? this.extraFlags,
    );
  }

  /// Serialize to a JSON-friendly map (used for persistence).
  Map<String, dynamic> toJson() => {
        'instanceName': instanceName,
        'hostname': hostname,
        'networkName': networkName,
        'networkSecret': networkSecret,
        'listeners': listeners,
        'peers': peers,
        'ipv4': ipv4,
        'dhcp': dhcp,
        'enableExitNode': enableExitNode,
        'extraFlags': extraFlags,
      };

  factory NetworkConfig.fromJson(Map<String, dynamic> json) {
    return NetworkConfig(
      instanceName:
          json['instanceName'] as String? ?? defaultInstanceName,
      hostname: json['hostname'] as String? ?? 'easytier',
      networkName: json['networkName'] as String? ?? 'easytier',
      networkSecret: json['networkSecret'] as String? ?? 'easytier',
      listeners: (json['listeners'] as List?)?.cast<String>() ?? const [],
      peers: (json['peers'] as List?)?.cast<String>() ?? const [],
      ipv4: json['ipv4'] as String?,
      dhcp: json['dhcp'] as bool? ?? false,
      enableExitNode: json['enableExitNode'] as bool? ?? false,
      extraFlags:
          (json['extraFlags'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// The TOML representation handed to the EasyTier core.
  ///
  /// Mirrors the field names EasyTier's `TomlConfigLoader` expects so the
  /// config is accepted verbatim by both the FFI and the CLI.
  String toToml() {
    final secret = TOML.escape(networkSecret);
    final buffer = StringBuffer()
      ..writeln('instance_name = "${TOML.escape(instanceName)}"')
      ..writeln('hostname = "${TOML.escape(hostname)}"')
      ..writeln('dhcp = $dhcp')
      ..writeln('enable_exit_node = $enableExitNode');

    if (listeners.isNotEmpty) {
      buffer.writeln(
          'listeners = [${listeners.map(TOML.escapeString).join(', ')}]');
    }
    if (peers.isNotEmpty) {
      buffer.writeln('peers = [${peers.map(TOML.escapeString).join(', ')}]');
    }

    buffer.writeln();
    buffer.writeln('[network_identity]');
    buffer.writeln('network_name = "${TOML.escape(networkName)}"');
    buffer.writeln('network_secret = "$secret"');

    if (ipv4 != null && !dhcp) {
      buffer.writeln();
      buffer.writeln('[flags]');
      buffer.writeln('ipv4 = "${TOML.escape(ipv4!)}"');
    }

    // Merge any free-form extra flags into the [flags] section.
    if (extraFlags.isNotEmpty) {
      if (ipv4 == null || dhcp) {
        buffer.writeln();
        buffer.writeln('[flags]');
      }
      extraFlags.forEach((key, value) {
        buffer.writeln('$key = ${TOML.encodeValue(value)}');
      });
    }

    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkConfig &&
          runtimeType == other.runtimeType &&
          instanceName == other.instanceName &&
          hostname == other.hostname &&
          networkName == other.networkName &&
          networkSecret == other.networkSecret &&
          dhcp == other.dhcp &&
          enableExitNode == other.enableExitNode &&
          ipv4 == other.ipv4;

  @override
  int get hashCode =>
      hostname.hashCode ^
      networkName.hashCode ^
      networkSecret.hashCode ^
      instanceName.hashCode;
}

/// Minimal TOML escaping/encoding helpers so [NetworkConfig] does not depend on
/// a third-party package for this trivial subset.
class TOML {
  static String escape(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  static String escapeString(String value) => '"${escape(value)}"';

  static String encodeValue(dynamic value) {
    if (value is bool) return '$value';
    if (value is num) return '$value';
    if (value is String) return escapeString(value);
    if (value is List) {
      return '[${value.map((e) => encodeValue(e)).join(', ')}]';
    }
    throw ArgumentError('Unsupported TOML value type: ${value.runtimeType}');
  }
}
