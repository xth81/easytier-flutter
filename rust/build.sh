#!/usr/bin/env bash
# Build the vendored EasyTier Rust core for Android and copy the produced
# .so files into the APK jniLibs directories.
#
# Usage:
#   ./build.sh [abi ...]        default: arm64-v8a armeabi-v7a x86_64
#
# Requirements (the GitHub Actions workflow provides all of them):
#   * Rust toolchain with the android targets installed
#   * cargo-ndk
#   * Android NDK (ANDROID_NDK_HOME or NDK_HOME)
#
# Cross-compile notes for the EasyTier stack:
#   * ZSTD_SYS_STATIC=1 makes zstd-sys build the C backend into a static lib
#     instead of looking for a system libzstd in the NDK.
#   * BINDGEN_EXTRA_CLANG_ARGS feeds the NDK sysroot + clang builtin headers
#     to bindgen (needed by kcp/zstd C bindings).
set -euo pipefail

cd "$(dirname "$0")"

ABIS=("${@:-arm64-v8a armeabi-v7a x86_64}")

# Map requested Android ABIs to Rust targets (cargo-ndk naming).
declare -A ABI_TO_TARGET=(
  [arm64-v8a]=aarch64-linux-android
  [armeabi-v7a]=armv7-linux-androideabi
  [x86]=i686-linux-android
  [x86_64]=x86_64-linux-android
)
RUST_TARGETS=()
for abi in "${ABIS[@]}"; do
  if [[ -n "${ABI_TO_TARGET[$abi]:-}" ]]; then
    RUST_TARGETS+=("${ABI_TO_TARGET[$abi]}")
  else
    echo "error: unsupported abi: $abi (supported: arm64-v8a armeabi-v7a x86 x86_64)" >&2
    exit 1
  fi
done
# Dedup, keep order.
RUST_TARGETS=($(printf '%s\n' "${RUST_TARGETS[@]}" | awk '!seen[$0]++'))

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found" >&2
  exit 1
fi
if ! cargo ndk --version >/dev/null 2>&1; then
  echo "cargo-ndk missing, installing..."
  cargo install cargo-ndk
fi

NDK_ROOT="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
if [[ -z "$NDK_ROOT" ]]; then
  echo "error: ANDROID_NDK_HOME / NDK_HOME is not set" >&2
  exit 1
fi

# Locate the prebuilt LLVM toolchain shipped with the NDK.
NDK_BIN="$NDK_ROOT/toolchains/llvm/prebuilt"
HOST_TAG=""
for tag in linux-x86_64 darwin-x86_64 darwin-aarch64; do
  if [[ -d "$NDK_BIN/$tag/bin" ]]; then
    HOST_TAG="$tag"
    break
  fi
done
if [[ -z "$HOST_TAG" ]]; then
  echo "error: cannot locate llvm prebuilt toolchain under $NDK_ROOT" >&2
  exit 1
fi
NDK_BIN="$NDK_BIN/$HOST_TAG/bin"

CLANG_SUB=""
if [[ -d "$NDK_BIN/../lib/clang" ]]; then
  CLANG_SUB=$(ls "$NDK_BIN/../lib/clang" | sort -V | tail -1)
fi
if [[ -z "$CLANG_SUB" ]]; then
  echo "error: cannot locate clang builtin headers in $NDK_ROOT" >&2
  exit 1
fi

NDK_SYSROOT="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"
CLANG_INCLUDE="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/lib/clang/$CLANG_SUB/include"

export ZSTD_SYS_STATIC=1
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$NDK_SYSROOT -I$CLANG_INCLUDE"

echo "==> NDK:    $NDK_ROOT"
echo "==> ABIs:   ${ABIS[*]}"
echo "==> Targets: ${RUST_TARGETS[*]}"

for rust_target in "${RUST_TARGETS[@]}"; do
  echo ""
  echo "==> building $rust_target (easytier-ffi, then easytier-android-jni)"

  cargo ndk \
    -t "$rust_target" \
    -p 23 \
    build --release -p easytier-ffi -p easytier-android-jni
done

# cargo-ndk writes into target/<rust-target>/release.
OUT_ROOT="../../android/app/src/main/jniLibs"
declare -A TARGET_TO_ABI=(
  [aarch64-linux-android]=arm64-v8a
  [armv7-linux-androideabi]=armeabi-v7a
  [i686-linux-android]=x86
  [x86_64-linux-android]=x86_64
)

for rust_target in "${RUST_TARGETS[@]}"; do
  abi="${TARGET_TO_ABI[$rust_target]}"
  src="target/$rust_target/release"
  dst="$OUT_ROOT/$abi"
  mkdir -p "$dst"
  for lib in libeasytier_android_jni.so libeasytier_ffi.so; do
    if [[ ! -f "$src/$lib" ]]; then
      echo "error: missing $src/$lib" >&2
      exit 1
    fi
    cp "$src/$lib" "$dst/"
  done
  echo "==> copied $abi -> android/app/src/main/jniLibs/$abi"
done

echo ""
echo "Rust core installed. Rebuild the Flutter APK to package it."
