import 'dart:io' show Platform;

import '../../data/config/app_settings.dart';
import 'easytier_backend.dart';
import 'ffi_backend.dart';
import 'mock_backend.dart';

/// Builds the appropriate [EasyTierBackend] for the current runtime.
///
/// The decision logic:
///  * If the user has force-selected the mock backend (developer toggle), use
///    the in-memory engine everywhere.
///  * On Android/iOS, prefer the real FFI core (bundled `.so`). If that fails
///    to load (e.g. running in an emulator without the lib), fall back to mock.
///  * On desktop, also try FFI; the mock is a reliable fallback for previews.
class EasyTierBackendFactory {
  /// Create and initialize a backend.
  static Future<EasyTierBackend> create({
    bool forceMock = false,
  }) async {
    final wantMock = forceMock ||
        AppSettings.instance.developerMockBackend ||
        _isUnsupportedPlatform();

    if (wantMock) {
      final mock = MockEasyTierBackend();
      await mock.initialize();
      return mock;
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

  static bool _isUnsupportedPlatform() => false;
}
