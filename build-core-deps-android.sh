#!/usr/bin/env bash
set -euo pipefail

# Cross-compile the networking and storage libraries for Android (static):
# OpenSSL, curl (with HTTP/2, HTTP/3, SSH, brotli, zstd, c-ares, libidn2,
# libpsl), SQLite and nlohmann/json.
# Run with:
#   C:\msys64\usr\bin\bash.exe path\to\build-core-deps-android.sh
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

export PATH="/ucrt64/bin:/usr/bin:/bin:$PATH"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/usr/ssl/certs/ca-bundle.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-$SSL_CERT_FILE}"
unset CONFIG_SITE

ANDROID_SDK_WIN="${ANDROID_SDK_WIN:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${LOCALAPPDATA:-}/Android/Sdk}}}"
ANDROID_SDK="$(cygpath -u "$ANDROID_SDK_WIN")"
if [[ -z "${ANDROID_NDK_WIN:-}" ]]; then
  ndk_latest="$(ls -d "$ANDROID_SDK"/ndk/*/ 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -z "$ndk_latest" ]]; then
    echo "ERROR: no NDK found in $ANDROID_SDK/ndk. Install one, or set ANDROID_NDK_WIN." >&2
    exit 1
  fi
  ANDROID_NDK_WIN="$(cygpath -m "${ndk_latest%/}")"
fi
# Autotools cannot reliably handle spaces in compiler paths. Use the Windows
# 8.3 short path for the NDK directory (needs 8.3 names enabled on the drive,
# otherwise install the NDK in a path without spaces).
ANDROID_NDK="$(cygpath -u "$(cygpath -d "$ANDROID_NDK_WIN")")"
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/windows-x86_64"
API="${API:-24}"
JOBS="${JOBS:-4}"

WORK_ROOT_WIN="C:/Tmp/android-core-deps"
WORK_ROOT="$(cygpath -u "$WORK_ROOT_WIN")"
SRC="$WORK_ROOT/src"
BUILD="$WORK_ROOT/build-core"
OUT="$WORK_ROOT/core-static"

OPENSSL_VERSION="3.3.2"
CURL_VERSION="8.10.1"
ZLIB_VERSION="1.3.1"
BROTLI_VERSION="1.1.0"
ZSTD_VERSION="1.5.6"
CARES_VERSION="1.34.3"
NGHTTP2_VERSION="1.64.0"
NGHTTP3_VERSION="1.6.0"
LIBSSH2_VERSION="1.11.1"
LIBUNISTRING_VERSION="1.3"
LIBIDN2_VERSION="2.3.7"
LIBPSL_VERSION="0.21.5"
SQLITE_YEAR="2024"
SQLITE_AMALGAMATION="sqlite-amalgamation-3450300"
NLOHMANN_JSON_VERSION="3.11.3"

mkdir -p "$SRC" "$BUILD" "$OUT"

download() {
  local url="$1"
  local file="$2"
  if [[ ! -f "$SRC/$file" ]]; then
    echo "==> Download $file"
    local out_win
    out_win="$(cygpath -w "$SRC/$file")"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
      "\$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '$url' -OutFile '$out_win'"
  fi
}

extract() {
  local file="$1"
  local dir="$2"
  if [[ ! -d "$SRC/$dir" ]]; then
    echo "==> Extract $file"
    case "$file" in
      *.zip)
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
          "Expand-Archive -LiteralPath '$(cygpath -w "$SRC/$file")' -DestinationPath '$(cygpath -w "$SRC")' -Force"
        ;;
      zstd-*.tar.gz)
        tar --exclude='zstd-*/tests' -xf "$SRC/$file" -C "$SRC"
        ;;
      *)
        tar -xf "$SRC/$file" -C "$SRC"
        ;;
    esac
  fi
}

abi_vars() {
  ABI="$1"
  case "$ABI" in
    arm64-v8a)
      ANDROID_ABI="arm64-v8a"
      HOST="aarch64-linux-android"
      CLANG_PREFIX="aarch64-linux-android"
      OPENSSL_TARGET="android-arm64"
      ;;
    armeabi-v7a)
      ANDROID_ABI="armeabi-v7a"
      HOST="arm-linux-androideabi"
      CLANG_PREFIX="armv7a-linux-androideabi"
      OPENSSL_TARGET="android-arm"
      ;;
    x86)
      ANDROID_ABI="x86"
      HOST="i686-linux-android"
      CLANG_PREFIX="i686-linux-android"
      OPENSSL_TARGET="android-x86"
      ;;
    x86_64)
      ANDROID_ABI="x86_64"
      HOST="x86_64-linux-android"
      CLANG_PREFIX="x86_64-linux-android"
      OPENSSL_TARGET="android-x86_64"
      ;;
    *)
      echo "Unknown ABI: $ABI" >&2
      exit 1
      ;;
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

configure_build() {
  local name="$1"
  local src_dir="$2"
  shift 2
  local bdir="$BUILD/$ABI/$name"
  rm -rf "$bdir"
  mkdir -p "$bdir"
  pushd "$bdir" >/dev/null
  CONFIG_SITE=/dev/null ac_cv_exeext= ac_cv_objext=o "$src_dir/configure" \
    --host="$HOST" \
    --prefix="$PREFIX" \
    "$@"
  # configure can write Windows-style paths (C:/...) into the Makefiles;
  # convert them to MSYS paths so make can read them.
  find . -name Makefile -type f -exec sed -i \
    -e 's#/C:/#/c/#g' \
    -e 's#C:/#/c/#g' {} +
  make -j"$JOBS"
  make install
  popd >/dev/null
}

prepare_sources() {
  download "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}.tar.gz"
  download "https://curl.se/download/curl-${CURL_VERSION}.tar.xz" "curl-${CURL_VERSION}.tar.xz"
  download "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}.tar.gz"
  download "https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz" "brotli-${BROTLI_VERSION}.tar.gz"
  download "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" "zstd-${ZSTD_VERSION}.tar.gz"
  download "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz" "c-ares-${CARES_VERSION}.tar.gz"
  download "https://github.com/nghttp2/nghttp2/releases/download/v${NGHTTP2_VERSION}/nghttp2-${NGHTTP2_VERSION}.tar.xz" "nghttp2-${NGHTTP2_VERSION}.tar.xz"
  download "https://github.com/ngtcp2/nghttp3/releases/download/v${NGHTTP3_VERSION}/nghttp3-${NGHTTP3_VERSION}.tar.xz" "nghttp3-${NGHTTP3_VERSION}.tar.xz"
  download "https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/libssh2-${LIBSSH2_VERSION}.tar.gz" "libssh2-${LIBSSH2_VERSION}.tar.gz"
  download "https://ftp.gnu.org/gnu/libunistring/libunistring-${LIBUNISTRING_VERSION}.tar.xz" "libunistring-${LIBUNISTRING_VERSION}.tar.xz"
  download "https://ftp.gnu.org/gnu/libidn/libidn2-${LIBIDN2_VERSION}.tar.gz" "libidn2-${LIBIDN2_VERSION}.tar.gz"
  download "https://github.com/rockdaboot/libpsl/releases/download/${LIBPSL_VERSION}/libpsl-${LIBPSL_VERSION}.tar.gz" "libpsl-${LIBPSL_VERSION}.tar.gz"
  download "https://www.sqlite.org/${SQLITE_YEAR}/${SQLITE_AMALGAMATION}.zip" "${SQLITE_AMALGAMATION}.zip"
  download "https://raw.githubusercontent.com/nlohmann/json/v${NLOHMANN_JSON_VERSION}/single_include/nlohmann/json.hpp" "json.hpp"

  extract "openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}"
  extract "curl-${CURL_VERSION}.tar.xz" "curl-${CURL_VERSION}"
  extract "zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}"
  extract "brotli-${BROTLI_VERSION}.tar.gz" "brotli-${BROTLI_VERSION}"
  extract "zstd-${ZSTD_VERSION}.tar.gz" "zstd-${ZSTD_VERSION}"
  extract "c-ares-${CARES_VERSION}.tar.gz" "c-ares-${CARES_VERSION}"
  extract "nghttp2-${NGHTTP2_VERSION}.tar.xz" "nghttp2-${NGHTTP2_VERSION}"
  extract "nghttp3-${NGHTTP3_VERSION}.tar.xz" "nghttp3-${NGHTTP3_VERSION}"
  extract "libssh2-${LIBSSH2_VERSION}.tar.gz" "libssh2-${LIBSSH2_VERSION}"
  extract "libunistring-${LIBUNISTRING_VERSION}.tar.xz" "libunistring-${LIBUNISTRING_VERSION}"
  extract "libidn2-${LIBIDN2_VERSION}.tar.gz" "libidn2-${LIBIDN2_VERSION}"
  extract "libpsl-${LIBPSL_VERSION}.tar.gz" "libpsl-${LIBPSL_VERSION}"
  extract "${SQLITE_AMALGAMATION}.zip" "${SQLITE_AMALGAMATION}"
}

# SQLite is built straight from the amalgamation (a single .c file).
build_sqlite() {
  if [[ -f "$PREFIX/lib/libsqlite3.a" ]]; then
    echo "==> Skip sqlite for $ABI"
    return
  fi
  mkdir -p "$PREFIX/lib" "$PREFIX/include"
  "$CC" $CFLAGS -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 \
    -c "$SRC/$SQLITE_AMALGAMATION/sqlite3.c" -o "$BUILD/$ABI-sqlite3.o"
  "$AR" rcs "$PREFIX/lib/libsqlite3.a" "$BUILD/$ABI-sqlite3.o"
  "$RANLIB" "$PREFIX/lib/libsqlite3.a"
  cp -f "$SRC/$SQLITE_AMALGAMATION/sqlite3.h" "$PREFIX/include/sqlite3.h"
}

# nlohmann/json is header-only, so it is just copied.
build_nlohmann() {
  mkdir -p "$PREFIX/include/nlohmann"
  cp -f "$SRC/json.hpp" "$PREFIX/include/nlohmann/json.hpp"
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
  echo "Building core deps for $ABI"
  echo "PREFIX=$PREFIX"
  echo "============================================================"

  build_sqlite
  build_nlohmann
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
echo "Done. Android core deps are in:"
echo "$OUT"
