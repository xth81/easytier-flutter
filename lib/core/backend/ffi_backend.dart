import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../../data/models/network_config.dart';
import '../../data/models/network_status.dart';
import '../../data/models/peer_info.dart';
import '../../data/models/status_json.dart';
import '../../data/models/tunnel_state.dart';
import 'easytier_backend.dart';
import 'ffi_bindings.dart';

/// An [EasyTierBackend] backed by the real embeddable EasyTier Rust core,
/// loaded via the `easytier-ffi` C ABI (desktop/emulator use; on Android the
/// [AndroidServiceBackend] drives the `:vpn` process instead).
class EasyTierFfiBackend implements EasyTierBackend {
  EasyTierFfiBackend({
    required this.libraryName,
    this.pollInterval = const Duration(seconds: 2),
  });

  /// Native library name, e.g. `libeasytier_ffi.so` (Android/Linux)
  /// or `libeasytier_ffi.dylib` (macOS).
  final String libraryName;
  final Duration pollInterval;

  ffi.DynamicLibrary? _lib;
  Timer? _poll;
  bool _running = false;
  String _currentInstance = NetworkConfig.defaultInstanceName;

  NetworkStatus _status = NetworkStatus.disconnected;
  List<PeerInfo> _peers = [];
  final List<RouteInfo> _routes = [];

  @override
  void Function(NetworkStatus status)? listener;

  @override
  String get backendName => 'FFI ($libraryName)';

  @override
  NetworkStatus get status => _status;

  @override
  List<PeerInfo> get peers => List.unmodifiable(_peers);

  @override
  List<RouteInfo> get routes => List.unmodifiable(_routes);

  @override
  Future<void> initialize() async {
    _lib = ffi.DynamicLibrary.open(libraryName);
    _setStatus(NetworkStatus.disconnected);
  }

  void _setStatus(NetworkStatus s) {
    _status = s;
    listener?.call(s);
  }

  // ---- FFI call helpers ----

  /// `int parse_config(const char *cfg)`.
  late final int Function(ffi.Pointer<Utf8>) _parseConfig = _requireLib()
      .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<Utf8>)>>(
          'parse_config')
      .asFunction();

  /// `int run_network_instance(const char *cfg)`.
  late final int Function(ffi.Pointer<Utf8>) _runNetworkInstance = _requireLib()
      .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<Utf8>)>>(
          'run_network_instance')
      .asFunction();

  /// `int set_tun_fd(const char *name, int fd)`.
  late final int Function(ffi.Pointer<Utf8>, int) _setTunFd = _requireLib()
      .lookup<ffi.NativeFunction<
          ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32)>>('set_tun_fd')
      .asFunction();

  /// `int retain_network_instance(const char **names, size_t len)`.
  late final int Function(ffi.Pointer<ffi.Pointer<Utf8>>, int)
      _retainNetworkInstance = _requireLib()
          .lookup<ffi.NativeFunction<
              ffi.Int32 Function(
                  ffi.Pointer<ffi.Pointer<Utf8>>, ffi.Size)>>(
              'retain_network_instance')
          .asFunction();

  /// `void get_error_msg(char **out)`.
  late final void Function(ffi.Pointer<ffi.Pointer<Utf8>>) _getErrorMsg =
      _requireLib()
          .lookup<ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.Pointer<Utf8>>)>>(
              'get_error_msg')
          .asFunction();

  /// `void free_string(const char *s)`.
  late final void Function(ffi.Pointer<Utf8>) _freeString = _requireLib()
      .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<Utf8>)>>(
          'free_string')
      .asFunction();

  /// `int collect_network_infos(KeyValuePair *infos, size_t max)`.
  late final int Function(ffi.Pointer<KeyValuePair>, int) _collectNetworkInfos =
      _requireLib()
          .lookup<ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<KeyValuePair>, ffi.Size)>>(
              'collect_network_infos')
          .asFunction();

  @override
  Future<void> start(NetworkConfig config) async {
    await stop();

    final cfg = config.toToml();

    final cfgPtr = cfg.toNativeUtf8();
    try {
      final rc = _parseConfig(cfgPtr);
      if (rc != 0) {
        throw BackendException('parse_config failed: ${_lastError()}');
      }
    } finally {
      malloc.free(cfgPtr);
    }

    final runPtr = cfg.toNativeUtf8();
    try {
      final rc = _runNetworkInstance(runPtr);
      if (rc != 0) {
        throw BackendException('run_network_instance failed: ${_lastError()}');
      }
    } finally {
      malloc.free(runPtr);
    }

    _running = true;
    _currentInstance = config.instanceName;
    _setStatus(NetworkStatus(
      state: TunnelState.connecting,
      instanceName: config.instanceName,
      running: true,
    ));

    await _refreshOnce();
    _poll ??= Timer.periodic(pollInterval, (_) => _refreshOnce());
  }

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    if (!_running) return;

    // retain_network_instance with length 0 stops all instances.
    _retainNetworkInstance(ffi.nullptr, 0);
    _running = false;
    _setStatus(NetworkStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    await stop();
    _lib = null;
  }

  @override
  Future<bool> setTunFd(int fd) async {
    final namePtr = _currentInstance.toNativeUtf8();
    try {
      return _setTunFd(namePtr, fd) == 0;
    } finally {
      malloc.free(namePtr);
    }
  }

  @override
  Future<void> refresh() async => _refreshOnce();

  ffi.DynamicLibrary _requireLib() {
    final lib = _lib;
    if (lib == null) {
      throw BackendException('FFI library not initialized');
    }
    return lib;
  }

  Future<void> _refreshOnce() async {
    if (!_running) return;
    try {
      final infos = _collectInfos();
      if (infos != null) {
        // `collect_network_infos` returns, per instance, a JSON string of
        // the instance's running info.
        final snapshot =
            (jsonDecode(infos) as Map).cast<String, dynamic>();
        _peers = EasyTierStatusJson.parsePeers(
            snapshot['routes'], snapshot['peers']);
        _routes
          ..clear()
          ..addAll(EasyTierStatusJson.parseRoutes(snapshot['routes']));
        _setStatus(EasyTierStatusJson.parseStatus(snapshot,
            instanceName: _currentInstance));
      }
    } catch (_) {
      // If a poll fails we keep the last known status rather than flapping.
    }
  }

  String _lastError() {
    final outPtr = calloc<ffi.Pointer<Utf8>>();
    try {
      _getErrorMsg(outPtr);
      final msg = outPtr.value;
      if (msg == ffi.nullptr) return '';
      final s = msg.toDartString();
      _freeString(msg);
      return s;
    } finally {
      calloc.free(outPtr);
    }
  }

  /// Returns the JSON value for the current instance, if any.
  String? _collectInfos() {
    const max = 8;
    final infos = calloc<KeyValuePair>(max);
    try {
      final count = _collectNetworkInfos(infos, max);
      if (count <= 0) return null;
      for (var i = 0; i < count; i++) {
        final key = infos[i].key.toDartString();
        final value = infos[i].value.toDartString();
        if (key == _currentInstance) {
          return value;
        }
      }
      return null;
    } finally {
      calloc.free(infos);
    }
  }
}
