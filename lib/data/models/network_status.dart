import 'tunnel_state.dart';

/// Aggregate, normalized status snapshot the backend publishes to the UI.
class NetworkStatus {
  /// Derived high-level state.
  final TunnelState state;

  /// The name of the running network instance, if any.
  final String instanceName;

  /// This node's virtual IPv4, if assigned.
  final String? ipv4;

  /// Number of peers currently reachable through the mesh.
  final int peerCount;

  /// Human-readable latency of the best path, in ms (or null if unknown).
  final int? latencyMs;

  /// Bytes/sec received over the mesh during the last sampling window.
  final int rxBytesPerSec;

  /// Bytes/sec transmitted over the mesh during the last sampling window.
  final int txBytesPerSec;

  /// Whether the core reports the instance as running.
  final bool running;

  /// Free-form detail string (e.g. the core's raw status JSON or error).
  final String? detail;

  const NetworkStatus({
    required this.state,
    this.instanceName = '',
    this.ipv4,
    this.peerCount = 0,
    this.latencyMs,
    this.rxBytesPerSec = 0,
    this.txBytesPerSec = 0,
    this.running = false,
    this.detail,
  });

  static const NetworkStatus disconnected = NetworkStatus(
    state: TunnelState.disconnected,
    running: false,
  );

  /// Convenience: whether the instance is actually running (not disconnected
  /// or errored). Equates to the `running` flag the core reports.
  bool get isRunning => running;

  NetworkStatus copyWith({
    TunnelState? state,
    String? instanceName,
    String? ipv4,
    int? peerCount,
    int? latencyMs,
    int? rxBytesPerSec,
    int? txBytesPerSec,
    bool? running,
    String? detail,
  }) {
    return NetworkStatus(
      state: state ?? this.state,
      instanceName: instanceName ?? this.instanceName,
      ipv4: ipv4 ?? this.ipv4,
      peerCount: peerCount ?? this.peerCount,
      latencyMs: latencyMs ?? this.latencyMs,
      rxBytesPerSec: rxBytesPerSec ?? this.rxBytesPerSec,
      txBytesPerSec: txBytesPerSec ?? this.txBytesPerSec,
      running: running ?? this.running,
      detail: detail ?? this.detail,
    );
  }
}
