import 'dart:io' show Platform;

import '../../data/config/app_settings.dart';
import 'easytier_backend.dart';
import 'ffi_backend.dart';
import 'mock_backend.dart';
import 'service_backend.dart';

/// Builds the appropriate [EasyTierBackend] for the current runtime.
///
/// The decision logic:
///  * If the user has force-selected the mock backend (developer toggle), use
///    the in-memory engine everywhere.
///  * On Android, drive the `:vpn` service process which runs the bundled
///    Rust core. If the native libraries are missing (pure emulator preview),
///    fall back to the in-process FFI backend, then to mock.
///  * On desktop, try the FFI core; the mock is a reliable fallback.
class EasyTierBackendFactory {
  /// Create and initialize a backend.
  static Future<EasyTierBackend> create({
    bool forceMock = false,
  }) async {
    final wantMock = forceMock || AppSettings.instance.developerMockBackend;
    if (wantMock) {
      final mock = MockEasyTierBackend();
      await mock.initialize();
      return mock;
    }

    if (Platform.isAndroid) {
      // Real device / APK with bundled core: service backend.
      if (await AndroidServiceBackend.isCoreAvailable()) {
        final service = AndroidServiceBackend();
        await service.initialize();
        return service;
      }

      // Emulator preview without the bundled libs: in-process FFI still
      // cannot load a .so, so mock is the effective fallback below.
    }

    final ffi = EasyTierFfiBackend(
      libraryName: _defaultLibraryName(),
    );
    try {
      await ffi.initialize();
      return ffi;
    } catch (_) {
      // Fall back to the simulator if the native lib is not present.
      final mock = MockEasyTierBackend();
      await mock.initialize();
      return mock;
    }
  }

  /// Default native library name for the current OS.
  static String _defaultLibraryName() {
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libeasytier_ffi.so';
    }
    if (Platform.isMacOS) {
      return 'libeasytier_ffi.dylib';
    }
    if (Platform.isWindows) {
      return 'easytier_ffi.dll';
    }
    return 'libeasytier_ffi.so';
  }
}
