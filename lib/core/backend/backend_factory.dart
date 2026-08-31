import 'dart:ffi' as ffi;
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
///    Rust core. Core availability is detected by directly probing the
///    bundled `libeasytier_ffi.so` — NOT through the MethodChannel, because
///    the controller is created before `runApp`/the Flutter engine exists.
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
      if (_isCoreBundled()) {
        final service = AndroidServiceBackend();
        await service.initialize();
        return service;
      }
      // Emulator preview without the bundled libs: fall through to mock.
    }

    final ffiBackend = EasyTierFfiBackend(
      libraryName: _defaultLibraryName(),
    );
    try {
      await ffiBackend.initialize();
      return ffiBackend;
    } catch (_) {
      // Fall back to the simulator if the native lib is not present.
      final mock = MockEasyTierBackend();
      await mock.initialize();
      return mock;
    }
  }

  /// Whether the vendored core `.so` is packaged in the APK. Works before the
  /// Flutter engine / platform channels exist.
  static bool _isCoreBundled() {
    try {
      // Loading in the app process is harmless (the :vpn process loads its
      // own copy) and proves the libraries survived packaging.
      ffi.DynamicLibrary.open('libeasytier_ffi.so');
      ffi.DynamicLibrary.open('libeasytier_android_jni.so');
      return true;
    } catch (_) {
      return false;
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
