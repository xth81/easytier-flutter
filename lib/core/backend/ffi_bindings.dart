import 'dart:ffi';

/// The C `struct KeyValuePair { const char *key; const char *value; }`
/// returned by `easytier-ffi`'s `list_instance` / `collect_network_infos`.
///
/// The actual C function signatures and calls live in [EasyTierFfiBackend]
/// (see `ffi_backend.dart`), which resolves each symbol via
/// `DynamicLibrary.lookup`. This file only holds the shared FFI struct types.
final class KeyValuePair extends Struct {
  external Pointer<Int8> key;

  external Pointer<Int8> value;
}
