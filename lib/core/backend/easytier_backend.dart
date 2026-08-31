import '../../data/models/network_config.dart';
import '../../data/models/network_status.dart';
import '../../data/models/peer_info.dart';

/// Abstract interface that any EasyTier engine can implement to back the UI.
///
/// The app is written against this interface so it can run against:
///  * the real embeddable Rust core (via the `easytier-ffi` C ABI) on a device;
///  * a simulated in-memory backend for the emulator, tests and previews.
///
/// Implementations are expected to be the single source of truth for the
/// running network and to notify [listener] whenever their [status] changes,
/// so the UI can rebuild reactively without polling.
abstract class EasyTierBackend {
  /// Called by the UI when the backend's [status] or [peers] change.
  void Function(NetworkStatus status)? listener;

  /// Current status snapshot.
  NetworkStatus get status;

  /// Currently known peers in the running mesh.
  List<PeerInfo> get peers;

  /// Currently known exported routes.
  List<RouteInfo> get routes;

  /// Human-readable backend name, e.g. `FfiBackend`, `MockBackend`.
  String get backendName;

  /// Initialize the backend (load native library, start runtime, etc.).
  Future<void> initialize();

  /// Start a network from [config]. Idempotent: starting an already-running
  /// instance is a no-op, while starting a different config replaces it.
  Future<void> start(NetworkConfig config);

  /// Stop the running network, if any.
  Future<void> stop();

  /// Stop everything and release resources.
  Future<void> dispose();

  /// Attach a TUN file descriptor (Android VPN use only) to the running
  /// instance. Implementations that don't need a TUN (e.g. no-tun mode) may
  /// ignore this.
  Future<bool> setTunFd(int fd);

  /// Manually refresh status/peers/routes (e.g. on a pull-to-refresh).
  Future<void> refresh();
}

/// Marker for a lightweight status that also carries a raw error message.
class BackendException implements Exception {
  final String message;
  BackendException(this.message);
  @override
  String toString() => message;
}
