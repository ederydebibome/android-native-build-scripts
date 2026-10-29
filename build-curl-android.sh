#!/usr/bin/env bash
set -euo pipefail

# Cross-compile curl for Android (static libraries), with HTTP/2, HTTP/3,
# SCP/SFTP, brotli, zstd, async DNS, IDN and the libraries it needs:
# OpenSSL, zlib, brotli, zstd, c-ares, nghttp2, nghttp3, libssh2,
# libunistring, libidn2 and libpsl.
# Needs lib/common.sh (shared code) from the same repository.
# Run with:
#   C:\msys64\usr\bin\bash.exe path\to\build-curl-android.sh
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
#   FORCE_CURL        set to 1 to rebuild curl even if it already exists
#   *_VERSION         skip the online lookup for one dependency and use this
#                     version, for example ZLIB_VERSION=1.3.1

# Settings for this project, read by lib/common.sh.
DEFAULT_API=24
WORK_ROOT_WIN="C:/Tmp/curl-android"
BUILD_NAME="build-static"
OUT_NAME="out-static"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Dependency versions. The numbers below are the defaults: the versions this
# script was last tested with. At the start, the script looks for newer
# releases online and uses them when it finds one. To skip the lookup for one
# dependency, set its variable before running, for example ZLIB_VERSION=1.3.1.
echo "==> Checking for newer versions of the dependencies (about a minute)"
resolve_version OPENSSL 3.3.2 github_version openssl/openssl openssl-
resolve_version CURL 8.10.1 listing_version https://curl.se/download/ curl- '\.tar\.xz'
resolve_version ZLIB 1.3.1 github_version madler/zlib v
resolve_version BROTLI 1.1.0 github_version google/brotli v
resolve_version ZSTD 1.5.6 github_version facebook/zstd v
resolve_version CARES 1.34.3 github_version c-ares/c-ares v
resolve_version NGHTTP2 1.64.0 github_version nghttp2/nghttp2 v
resolve_version NGHTTP3 1.6.0 github_version ngtcp2/nghttp3 v
resolve_version LIBSSH2 1.11.1 github_version libssh2/libssh2 libssh2-
resolve_version LIBUNISTRING 1.3 listing_version https://ftp.gnu.org/gnu/libunistring/ libunistring- '\.tar\.xz'
resolve_version LIBIDN2 2.3.7 listing_version https://ftp.gnu.org/gnu/libidn/ libidn2- '\.tar\.gz'
resolve_version LIBPSL 0.21.5 github_version rockdaboot/libpsl ''
echo "==> Version check done"

abi_vars() {
  select_abi "$1"
  case "$ABI" in
    arm64-v8a) OPENSSL_TARGET="android-arm64" ;;
    armeabi-v7a) OPENSSL_TARGET="android-arm" ;;
    x86) OPENSSL_TARGET="android-x86" ;;
    x86_64) OPENSSL_TARGET="android-x86_64" ;;
  esac

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
  download "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}.tar.gz"
  download "https://curl.se/download/curl-${CURL_VERSION}.tar.xz" "curl-${CURL_VERSION}.tar.xz"
  download "https://github.com/madler/zlib/archive/refs/tags/v${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}.tar.gz"
  download "https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz" "brotli-${BROTLI_VERSION}.tar.gz"
  download "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" "zstd-${ZSTD_VERSION}.tar.gz"
  download "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz" "c-ares-${CARES_VERSION}.tar.gz"
  download "https://github.com/nghttp2/nghttp2/releases/download/v${NGHTTP2_VERSION}/nghttp2-${NGHTTP2_VERSION}.tar.xz" "nghttp2-${NGHTTP2_VERSION}.tar.xz"
  download "https://github.com/ngtcp2/nghttp3/releases/download/v${NGHTTP3_VERSION}/nghttp3-${NGHTTP3_VERSION}.tar.xz" "nghttp3-${NGHTTP3_VERSION}.tar.xz"
  download "https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/libssh2-${LIBSSH2_VERSION}.tar.gz" "libssh2-${LIBSSH2_VERSION}.tar.gz"
  download "https://ftp.gnu.org/gnu/libunistring/libunistring-${LIBUNISTRING_VERSION}.tar.xz" "libunistring-${LIBUNISTRING_VERSION}.tar.xz"
  download "https://ftp.gnu.org/gnu/libidn/libidn2-${LIBIDN2_VERSION}.tar.gz" "libidn2-${LIBIDN2_VERSION}.tar.gz"
  download "https://github.com/rockdaboot/libpsl/releases/download/${LIBPSL_VERSION}/libpsl-${LIBPSL_VERSION}.tar.gz" "libpsl-${LIBPSL_VERSION}.tar.gz"

  extract "openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}"
  extract "curl-${CURL_VERSION}.tar.xz" "curl-${CURL_VERSION}"
  extract "zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}"
  extract "brotli-${BROTLI_VERSION}.tar.gz" "brotli-${BROTLI_VERSION}"
  extract "zstd-${ZSTD_VERSION}.tar.gz" "zstd-${ZSTD_VERSION}" --exclude='zstd-*/tests'
  extract "c-ares-${CARES_VERSION}.tar.gz" "c-ares-${CARES_VERSION}"
  extract "nghttp2-${NGHTTP2_VERSION}.tar.xz" "nghttp2-${NGHTTP2_VERSION}"
  extract "nghttp3-${NGHTTP3_VERSION}.tar.xz" "nghttp3-${NGHTTP3_VERSION}"
  extract "libssh2-${LIBSSH2_VERSION}.tar.gz" "libssh2-${LIBSSH2_VERSION}"
  extract "libunistring-${LIBUNISTRING_VERSION}.tar.xz" "libunistring-${LIBUNISTRING_VERSION}"
  extract "libidn2-${LIBIDN2_VERSION}.tar.gz" "libidn2-${LIBIDN2_VERSION}"
  extract "libpsl-${LIBPSL_VERSION}.tar.gz" "libpsl-${LIBPSL_VERSION}"
}

build_openssl() {
  if [[ -f "$PREFIX/lib/libssl.a" && -f "$PREFIX/lib/libcrypto.a" ]]; then
    echo "==> Skip OpenSSL for $ABI"
    return
  fi
  # OpenSSL builds inside its source tree, so work on a copy.
  local bdir="$BUILD/$ABI/openssl-$$"
  cp -R "$SRC/openssl-${OPENSSL_VERSION}" "$bdir"
  pushd "$bdir" >/dev/null
  local asm_option=()
  if [ "$ABI" = "armeabi-v7a" ]; then
    asm_option=(no-asm)
  fi
  ./Configure "$OPENSSL_TARGET" no-shared no-tests no-apps no-ui-console "${asm_option[@]}" \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
  make -j"$JOBS"
  make install_dev
  popd >/dev/null
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

build_brotli() {
  if [[ -f "$PREFIX/lib/libbrotlidec.a" && -f "$PREFIX/lib/libbrotlicommon.a" ]]; then
    echo "==> Skip brotli for $ABI"
    return
  fi
  cmake_build "brotli" "$SRC/brotli-${BROTLI_VERSION}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBROTLI_DISABLE_TESTS=ON
}

build_zstd() {
  if [[ -f "$PREFIX/lib/libzstd.a" ]]; then
    echo "==> Skip zstd for $ABI"
    return
  fi
  cmake_build "zstd" "$SRC/zstd-${ZSTD_VERSION}/build/cmake" \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_CONTRIB=OFF \
    -DZSTD_BUILD_TESTS=OFF
}

build_cares() {
  if [[ -f "$PREFIX/lib/libcares.a" ]]; then
    echo "==> Skip c-ares for $ABI"
    return
  fi
  configure_build "c-ares" "$SRC/c-ares-${CARES_VERSION}" \
    --disable-dependency-tracking \
    --disable-shared \
    --enable-static \
    --disable-tests
}

build_nghttp2() {
  if [[ -f "$PREFIX/lib/libnghttp2.a" ]]; then
    echo "==> Skip nghttp2 for $ABI"
    return
  fi
  configure_build "nghttp2" "$SRC/nghttp2-${NGHTTP2_VERSION}" \
    --disable-dependency-tracking \
    --disable-shared \
    --enable-static \
    --enable-lib-only \
    --disable-app \
    --disable-examples \
    --disable-hpack-tools \
    --disable-python-bindings \
    --disable-threads \
    --without-jemalloc \
    --without-libxml2 \
    --without-systemd
}

build_nghttp3() {
  if [[ -f "$PREFIX/lib/libnghttp3.a" ]]; then
    echo "==> Skip nghttp3 for $ABI"
    return
  fi
  cmake_build "nghttp3" "$SRC/nghttp3-${NGHTTP3_VERSION}" \
    -DENABLE_LIB_ONLY=ON \
    -DENABLE_STATIC_LIB=ON \
    -DENABLE_SHARED_LIB=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_TESTS=OFF
}

build_libunistring() {
  if [[ -f "$PREFIX/lib/libunistring.a" ]]; then
    echo "==> Skip libunistring for $ABI"
    return
  fi
  configure_build "libunistring" "$SRC/libunistring-${LIBUNISTRING_VERSION}" \
    --disable-shared \
    --enable-static \
    --disable-rpath
}

build_libidn2() {
  if [[ -f "$PREFIX/lib/libidn2.a" ]]; then
    echo "==> Skip libidn2 for $ABI"
    return
  fi
  configure_build "libidn2" "$SRC/libidn2-${LIBIDN2_VERSION}" \
    --disable-shared \
    --enable-static \
    --disable-doc \
    --disable-nls \
    --with-libunistring-prefix="$PREFIX"
}

build_libpsl() {
  if [[ -f "$PREFIX/lib/libpsl.a" ]]; then
    echo "==> Skip libpsl for $ABI"
    return
  fi
  export LIBIDN2_CFLAGS="-I$PREFIX/include"
  export LIBIDN2_LIBS="-L$PREFIX/lib -lidn2 -lunistring"
  configure_build "libpsl" "$SRC/libpsl-${LIBPSL_VERSION}" \
    --disable-dependency-tracking \
    --disable-shared \
    --enable-static \
    --disable-gtk-doc \
    --disable-gtk-doc-html \
    --disable-gtk-doc-pdf \
    --disable-man \
    --enable-builtin \
    --disable-runtime
  unset LIBIDN2_CFLAGS LIBIDN2_LIBS
}

build_libssh2() {
  if [[ -f "$PREFIX/lib/libssh2.a" ]]; then
    echo "==> Skip libssh2 for $ABI"
    return
  fi
  cmake_build "libssh2" "$SRC/libssh2-${LIBSSH2_VERSION}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_TESTS=OFF \
    -DCRYPTO_BACKEND=OpenSSL \
    -DENABLE_ZLIB_COMPRESSION=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.a"
}

build_curl() {
  if [[ "${FORCE_CURL:-0}" != "1" && -f "$PREFIX/lib/libcurl.a" ]]; then
    echo "==> Skip curl for $ABI"
    return
  fi
  cmake_build "curl" "$SRC/curl-${CURL_VERSION}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_CURL_EXE=OFF \
    -DBUILD_TESTING=OFF \
    -DCURL_DISABLE_LDAP=ON \
    -DCURL_DISABLE_LDAPS=ON \
    -DCURL_USE_OPENSSL=ON \
    -DCURL_USE_LIBSSH2=ON \
    -DCURL_USE_LIBPSL=ON \
    -DCURL_BROTLI=ON \
    -DCURL_ZSTD=ON \
    -DCURL_ZLIB=ON \
    -DENABLE_ARES=ON \
    -DENABLE_THREADED_RESOLVER=ON \
    -DUSE_LIBIDN2=ON \
    -DUSE_NGHTTP2=ON \
    -DUSE_OPENSSL_QUIC=ON \
    -DENABLE_WEBSOCKETS=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
    -DBROTLI_INCLUDE_DIR="$PREFIX/include" \
    -DBROTLICOMMON_LIBRARY="$PREFIX/lib/libbrotlicommon.a" \
    -DBROTLIDEC_LIBRARY="$PREFIX/lib/libbrotlidec.a" \
    -DBROTLIENC_LIBRARY="$PREFIX/lib/libbrotlienc.a" \
    -DZSTD_INCLUDE_DIR="$PREFIX/include" \
    -DZSTD_LIBRARY="$PREFIX/lib/libzstd.a" \
    -DCARES_INCLUDE_DIR="$PREFIX/include" \
    -DCARES_LIBRARY="$PREFIX/lib/libcares.a" \
    -DNGHTTP2_INCLUDE_DIR="$PREFIX/include" \
    -DNGHTTP2_LIBRARY="$PREFIX/lib/libnghttp2.a" \
    -DNGHTTP3_INCLUDE_DIR="$PREFIX/include" \
    -DNGHTTP3_LIBRARY="$PREFIX/lib/libnghttp3.a" \
    -DLIBSSH2_INCLUDE_DIR="$PREFIX/include" \
    -DLIBSSH2_LIBRARY="$PREFIX/lib/libssh2.a" \
    -DLIBIDN2_INCLUDE_DIR="$PREFIX/include" \
    -DLIBIDN2_LIBRARY="$PREFIX/lib/libidn2.a" \
    -DLIBPSL_INCLUDE_DIR="$PREFIX/include" \
    -DLIBPSL_LIBRARY="$PREFIX/lib/libpsl.a"
}

# curl's CMake build silently drops a feature when its dependency is not
# found, so check the result and fail instead of shipping a reduced build.
verify_curl_features() {
  local pc="$PREFIX/lib/pkgconfig/libcurl.pc"
  local missing=0
  for feature in SSL libz brotli zstd AsynchDNS HTTP2 HTTP3 IDN PSL; do
    if ! grep -q "supported_features=.*$feature" "$pc"; then
      echo "ERROR: libcurl was built without $feature." >&2
      missing=1
    fi
  done
  for protocol in SCP SFTP WS WSS; do
    if ! grep -q "supported_protocols=.*$protocol" "$pc"; then
      echo "ERROR: libcurl was built without $protocol." >&2
      missing=1
    fi
  done
  if [[ "$missing" != "0" ]]; then
    echo "Refusing to accept a minimal curl build." >&2
    exit 1
  fi
}

# Only static libraries and headers are needed; remove the installed
# binaries and shared data.
clean_runtime_tools() {
  rm -rf "$PREFIX/bin" "$PREFIX/share"
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
  echo "Building curl and its dependencies for $ABI"
  echo "PREFIX=$PREFIX"
  echo "============================================================"

  build_openssl
  build_zlib
  build_brotli
  build_zstd
  build_cares
  build_nghttp2
  build_nghttp3
  build_libunistring
  build_libidn2
  build_libpsl
  build_libssh2
  build_curl
  verify_curl_features
  clean_runtime_tools

  find "$PREFIX/lib" -maxdepth 1 -type f -name "*.a" -printf "%f\n" | sort
done

echo
echo "Done. curl and its dependencies are in:"
echo "$OUT"
