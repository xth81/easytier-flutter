/// High-level connection lifecycle states exposed to the UI.
///
/// These mirror the states the EasyTier core can report through the
/// backend, normalized so the UI never has to reason about core internals.
enum ConnectionState {
  /// No network instance is running.
  disconnected,

  /// A network instance is starting up / connecting to peers.
  connecting,

  /// The instance is running and at least one peer is reachable.
  connected,

  /// The instance failed to start or dropped unexpectedly.
  error,

  /// The instance is running but no peer is currently reachable
  /// (still a valid, routable node, just not meshed yet).
  waiting;

  bool get isActive => this == connected || this == connecting;

  bool get isRunning => this != disconnected && this != error;
}
