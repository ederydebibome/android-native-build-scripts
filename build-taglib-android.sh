#!/usr/bin/env bash
set -euo pipefail

# Cross-compile TagLib 2.x for Android (static libraries). TagLib 2 needs a
# C++17 compiler and the header-only utf8cpp library, which this script
# downloads too. zlib is built as well (TagLib uses it for compressed
# ID3v2 frames).
# Needs lib/common.sh (shared code) from the same repository.
# Run with:
#   C:\msys64\usr\bin\bash.exe path\to\build-taglib-android.sh
#
# Optional environment variables:
#   ANDROID_SDK_WIN   Android SDK folder
#                     (default: %ANDROID_SDK_ROOT%, %ANDROID_HOME%, or
#                     %LOCALAPPDATA%\Android\Sdk)
#   ANDROID_NDK_WIN   NDK folder (default: the newest one in <SDK>\ndk)
#   API               Android API level (default: 24)
#   ABIS              ABIs to build (default: arm64-v8a armeabi-v7a x86 x86_64)
#   JOBS              parallel jobs (default: 4)
#   KEEP_PREFIX       set to 1 to keep the libraries that are already built
#   *_VERSION         skip the online lookup for one dependency and use this
#                     version, for example TAGLIB_VERSION=2.2.1

# Settings for this project, read by lib/common.sh.
DEFAULT_API=24
WORK_ROOT_WIN="C:/Tmp/taglib-android"
BUILD_NAME="build-static"
OUT_NAME="out-static"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Dependency versions. The numbers below are the defaults: the versions this
# script was last tested with. At the start, the script looks for newer
# releases online and uses them when it finds one. To skip the lookup for one
# dependency, set its variable before running, for example ZLIB_VERSION=1.3.1.
echo "==> Checking for newer versions of the dependencies (a few seconds)"
resolve_version TAGLIB 2.2.1 github_version taglib/taglib v
resolve_version UTFCPP 4.0.8 github_version nemtrif/utfcpp v
resolve_version ZLIB 1.3.1 github_version madler/zlib v
echo "==> Version check done"

abi_vars() {
  select_abi "$1"
  PREFIX="$OUT/$ABI"
  export ANDROID_NDK_ROOT="$ANDROID_NDK"
  export ANDROID_NDK_HOME="$ANDROID_NDK"
  export ANDROID_API="$API"
  export PATH="$TOOLCHAIN/bin:/ucrt64/bin:/usr/bin:/bin:$PATH"
  export CC="$TOOLCHAIN/bin/${CLANG_PREFIX}${API}-clang"
  export CXX="$TOOLCHAIN/bin/${CLANG_PREFIX}${API}-clang++"
  export AR="$TOOLCHAIN/bin/llvm-ar"
  export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
  export STRIP="$TOOLCHAIN/bin/llvm-strip"
  export CFLAGS="-O2 -fPIC -DANDROID"
  export CXXFLAGS="-O2 -fPIC -DANDROID -fexceptions -frtti"
  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-L$PREFIX/lib"
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
  export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
}

cmake_build() {
  local name="$1"
  local src_dir="$2"
  shift 2
  local bdir="$BUILD/$ABI/$name"
  rm -rf "$bdir"
  /ucrt64/bin/cmake -S "$src_dir" -B "$bdir" \
    -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    "$@"
  /ucrt64/bin/cmake --build "$bdir" --parallel "$JOBS"
  /ucrt64/bin/cmake --install "$bdir"
}

prepare_sources() {
  download "https://github.com/taglib/taglib/archive/refs/tags/v${TAGLIB_VERSION}.tar.gz" "taglib-${TAGLIB_VERSION}.tar.gz"
  download "https://github.com/nemtrif/utfcpp/archive/refs/tags/v${UTFCPP_VERSION}.tar.gz" "utfcpp-${UTFCPP_VERSION}.tar.gz"
  download "https://github.com/madler/zlib/archive/refs/tags/v${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}.tar.gz"

  extract "taglib-${TAGLIB_VERSION}.tar.gz" "taglib-${TAGLIB_VERSION}"
  extract "utfcpp-${UTFCPP_VERSION}.tar.gz" "utfcpp-${UTFCPP_VERSION}"
  extract "zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}"
}

build_zlib() {
  if [[ -f "$PREFIX/lib/libz.a" ]]; then
    echo "==> Skip zlib for $ABI"
    return
  fi
  cmake_build "zlib" "$SRC/zlib-${ZLIB_VERSION}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DZLIB_BUILD_EXAMPLES=OFF
  rm -f "$PREFIX/lib/libz.so"
}

# The GitHub archive of TagLib does not contain utf8cpp (it is a Git
# submodule there), so point TagLib's CMake at the copy downloaded above.
build_taglib() {
  if [[ -f "$PREFIX/lib/libtag.a" ]]; then
    echo "==> Skip TagLib for $ABI"
    return
  fi
  cmake_build "taglib" "$SRC/taglib-${TAGLIB_VERSION}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DWITH_ZLIB=ON \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
    -Dutf8cpp_INCLUDE_DIR="$SRC/utfcpp-${UTFCPP_VERSION}/source"
}

prepare_sources

for abi in ${ABIS:-arm64-v8a armeabi-v7a x86 x86_64}; do
  abi_vars "$abi"
  if [[ "${KEEP_PREFIX:-0}" != "1" ]]; then
    case "$PREFIX" in
      "$OUT"/*) rm -rf "$PREFIX" ;;
      *) echo "Refusing to clean unexpected prefix: $PREFIX" >&2; exit 1 ;;
    esac
  fi
  mkdir -p "$PREFIX" "$BUILD/$ABI"

  echo
  echo "============================================================"
  echo "Building TagLib for $ABI"
  echo "PREFIX=$PREFIX"
  echo "============================================================"

  build_zlib
  build_taglib

  find "$PREFIX/lib" -maxdepth 1 -type f -name "*.a" -printf "%f\n" | sort
done

echo
echo "Done. TagLib is in:"
echo "$OUT"
