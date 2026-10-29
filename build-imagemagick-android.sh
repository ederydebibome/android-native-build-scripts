#!/usr/bin/env bash
set -euo pipefail

# Build ImageMagick Android with native delegates.
# Needs lib/common.sh (shared code) from the same repository.
# Run with:
#   C:\msys64\usr\bin\bash.exe path\to\build-imagemagick-android.sh
#
# Optional environment variables:
#   ANDROID_SDK_WIN   Android SDK folder
#                     (default: %ANDROID_SDK_ROOT%, %ANDROID_HOME%, or
#                     %LOCALAPPDATA%\Android\Sdk)
#   ANDROID_NDK_WIN   NDK folder (default: the newest one in <SDK>\ndk)
#   API               Android API level (default: 23)
#   ABIS              ABIs to build (default: arm64-v8a armeabi-v7a x86 x86_64)
#   JOBS              parallel jobs (default: 4)
#   ONLY_IMAGEMAGICK  set to 1 to rebuild only ImageMagick and keep the
#                     dependencies that are already built
#   *_VERSION         skip the online lookup for one dependency and use this
#                     version, for example ZLIB_VERSION=1.3.1

# Settings for this project, read by lib/common.sh.
DEFAULT_API=23
WORK_ROOT_WIN="C:/Tmp/imagemagick-android"
BUILD_NAME="build-static"
OUT_NAME="out-static"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Dependency versions. The numbers below are the defaults: the versions this
# script was last tested with. At the start, the script looks for newer
# releases online and uses them when it finds one. To skip the lookup for one
# dependency, set its variable before running, for example ZLIB_VERSION=1.3.1.
echo "==> Checking for newer versions of the dependencies (about a minute)"
resolve_version ZLIB 1.3.1 github_version madler/zlib v
resolve_version LIBPNG 1.6.58 github_version pnggroup/libpng v
resolve_version JPEG_TURBO 3.1.4 github_version libjpeg-turbo/libjpeg-turbo ''
resolve_version WEBP 1.6.0 github_version webmproject/libwebp v
resolve_version FREETYPE 2.14.3 listing_version https://download.savannah.gnu.org/releases/freetype/ freetype- '\.tar\.xz'
resolve_version LCMS2 2.17 github_version mm2/Little-CMS lcms
resolve_version TIFF 4.7.1 listing_version https://download.osgeo.org/libtiff/ tiff- '\.tar\.xz'
resolve_version OPENJPEG 2.5.4 github_version uclouvain/openjpeg v
resolve_version IMAGEMAGICK 7.1.2-21 github_version ImageMagick/ImageMagick ''
resolve_version LIBANDROID_SUPPORT 29 github_version termux/libandroid-support v
resolve_version WCWIDTH 4 github_version termux/wcwidth v
resolve_version UTIL_MACROS 1.20.2 listing_version https://xorg.freedesktop.org/archive/individual/util/ util-macros- '\.tar\.gz'
resolve_version XORGPROTO 2024.1 listing_version https://xorg.freedesktop.org/archive/individual/proto/ xorgproto- '\.tar\.gz'
resolve_version XTRANS 1.5.0 listing_version https://xorg.freedesktop.org/archive/individual/lib/ xtrans- '\.tar\.gz'
resolve_version LIBXAU 1.0.11 listing_version https://xorg.freedesktop.org/archive/individual/lib/ libXau- '\.tar\.gz'
resolve_version LIBXDMCP 1.1.5 listing_version https://xorg.freedesktop.org/archive/individual/lib/ libXdmcp- '\.tar\.gz'
resolve_version XCBPROTO 1.17.0 listing_version https://xorg.freedesktop.org/archive/individual/xcb/ xcb-proto- '\.tar\.gz'
resolve_version PTHREAD_STUBS 0.5 listing_version https://xcb.freedesktop.org/dist/ libpthread-stubs- '\.tar\.gz'
resolve_version LIBXCB 1.17.0 listing_version https://xorg.freedesktop.org/archive/individual/xcb/ libxcb- '\.tar\.gz'
resolve_version LIBX11 1.8.10 listing_version https://xorg.freedesktop.org/archive/individual/lib/ libX11- '\.tar\.gz'
echo "==> Version check done"

abi_vars() {
  select_abi "$1"

  PREFIX="$OUT/$ABI"
  mkdir -p "$BUILD/$ABI"
  export TMPDIR="$BUILD/$ABI/tmp"
  mkdir -p "$TMPDIR"
  export PATH="$TOOLCHAIN/bin:/ucrt64/bin:/usr/bin:/bin:$PATH"
  export CC="$TOOLCHAIN/bin/${CLANG_PREFIX}${API}-clang"
  export CXX="$TOOLCHAIN/bin/${CLANG_PREFIX}${API}-clang++"
  export CPP="$CC -E"
  RAWCPP_WRAPPER="$BUILD/$ABI/rawcpp.sh"
  cat > "$RAWCPP_WRAPPER" <<EOF
#!/usr/bin/env bash
traditional=()
rest=()
for arg in "\$@"; do
  case "\$arg" in
    -traditional) traditional=(-traditional-cpp) ;;
    -undef) ;;
    *) rest+=("\$arg") ;;
  esac
done
exec "$CC" -E -P "\${traditional[@]}" -Uunix -U__unix -U__unix__ "\${rest[@]}" -x c -
EOF
  chmod +x "$RAWCPP_WRAPPER"

  CC_FOR_BUILD_WRAPPER="$BUILD/$ABI/cc-for-build.sh"
  cat > "$CC_FOR_BUILD_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -e

quote_cmd_arg() {
  local arg="$1"
  arg="${arg//\\/\\\\}"
  arg="${arg//\"/\\\"}"
  printf '"%s"' "$arg"
}

convert_arg() {
  local arg="$1"
  case "$arg" in
    /?/*)
      cygpath -w "$arg"
      ;;
    -I/?/*)
      local path="${arg:2}"
      printf -- "-I%s" "$(cygpath -w "$path")"
      ;;
    *)
      printf "%s" "$arg"
      ;;
  esac
}

bat="${TMPDIR:-/c/Tmp}/cc-for-build-$$.bat"
{
  printf '@echo off\r\n'
  printf 'set MSYSTEM=\r\n'
  printf 'set MINGW_PREFIX=\r\n'
  printf 'set MINGW_CHOST=\r\n'
  printf 'set MINGW_PACKAGE_PREFIX=\r\n'
  printf 'set CHERE_INVOKING=\r\n'
  printf 'set PATH=C:\\msys64\\ucrt64\\bin;C:\\Windows\\System32;C:\\Windows\r\n'
  printf 'cd /d %s\r\n' "$(quote_cmd_arg "$(cygpath -w "$PWD")")"
  printf 'C:\\msys64\\ucrt64\\bin\\gcc.exe'
  for arg in "$@"; do
    converted="$(convert_arg "$arg")"
    printf ' %s' "$(quote_cmd_arg "$converted")"
  done
  printf '\r\nexit /b %%ERRORLEVEL%%\r\n'
} > "$bat"

cmd.exe //C "$(cygpath -w "$bat")"
status=$?
rm -f "$bat"
exit "$status"
EOF
  chmod +x "$CC_FOR_BUILD_WRAPPER"
  export AR="$TOOLCHAIN/bin/llvm-ar"
  export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
  export STRIP="$TOOLCHAIN/bin/llvm-strip"
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
  export CPPFLAGS="-I$PREFIX/include"
  export CFLAGS="-O2 -fPIC -DANDROID"
  export CXXFLAGS="-O2 -fPIC -DANDROID -fexceptions -frtti"
  export LDFLAGS="-L$PREFIX/lib"
}

cmake_build() {
  local name="$1"
  local src_dir="$2"
  shift 2
  local bdir="$BUILD/$ABI/$name"
  rm -rf "$bdir"
  cmake -S "$src_dir" -B "$bdir" \
    -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    "$@"
  cmake --build "$bdir" --parallel "$JOBS"
  cmake --install "$bdir"
}

ensure_libpng_pkgconfig() {
  mkdir -p "$PREFIX/lib/pkgconfig"
  if [[ -f "$PREFIX/lib/pkgconfig/libpng16.pc" && ! -f "$PREFIX/lib/pkgconfig/libpng.pc" ]]; then
    cp -f "$PREFIX/lib/pkgconfig/libpng16.pc" "$PREFIX/lib/pkgconfig/libpng.pc"
  fi
  if [[ ! -f "$PREFIX/lib/pkgconfig/libpng.pc" ]]; then
    cat > "$PREFIX/lib/pkgconfig/libpng.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libpng
Description: Loads and saves PNG files
Version: $LIBPNG_VERSION
Libs: -L\${libdir} -lpng16
Libs.private: -lz -lm
Cflags: -I\${includedir} -I\${includedir}/libpng16
EOF
  fi
}

verify_static_symbol() {
  local archive="$1"
  local symbol="$2"
  local label="$3"
  if [[ ! -f "$archive" ]]; then
    echo "ERROR: missing $label archive: $archive" >&2
    exit 1
  fi
  if ! "$TOOLCHAIN/bin/llvm-nm" -g --defined-only "$archive" | grep -q "$symbol"; then
    echo "ERROR: $label is missing $symbol." >&2
    echo "ImageMagick was built without the required native coder." >&2
    exit 1
  fi
}

build_lcms2() {
  local src_dir="$SRC/Little-CMS-lcms${LCMS2_VERSION}"
  local bdir="$BUILD/$ABI/lcms2"
  rm -rf "$bdir"
  mkdir -p "$bdir"
  pushd "$bdir" >/dev/null
  CONFIG_SITE=/dev/null "$src_dir/configure" \
    --host="$HOST" \
    --prefix="$PREFIX" \
    --disable-shared \
    --enable-static \
    --without-jpeg \
    --without-tiff \
    --without-zlib

  # Cross-build only the Android library and headers. The default lcms2
  # Makefile also builds host utilities, which are not needed by ImageMagick.
  make -C src -j"$JOBS"

  mkdir -p "$PREFIX/lib" "$PREFIX/include"
  if [[ -f "$bdir/src/.libs/liblcms2.a" ]]; then
    cp -f "$bdir/src/.libs/liblcms2.a" "$PREFIX/lib/liblcms2.a"
  else
    "$AR" rcs "$PREFIX/lib/liblcms2.a" "$bdir"/src/.libs/*.o
    "$RANLIB" "$PREFIX/lib/liblcms2.a"
  fi
  cp -f "$src_dir/include/lcms2.h" "$PREFIX/include/lcms2.h"
  cp -f "$src_dir/include/lcms2_plugin.h" "$PREFIX/include/lcms2_plugin.h"
  mkdir -p "$PREFIX/lib/pkgconfig"
  cp -f lcms2.pc "$PREFIX/lib/pkgconfig/lcms2.pc"
  popd >/dev/null
}

write_android_support_compat_header() {
  mkdir -p "$PREFIX/include"
  cat > "$PREFIX/include/android-support-compat.h" <<'EOF'
#include <stddef.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

int mblen(const char *s, size_t n);
size_t mbsnrtowcs(wchar_t *dst, const char **src, size_t nms, size_t len, mbstate_t *ps);
size_t mbsrtowcs(wchar_t *dst, const char **src, size_t len, mbstate_t *ps);
int wcwidth(wchar_t wc);
int wcswidth(const wchar_t *s, size_t n);

#ifdef __cplusplus
}
#endif
EOF
}

build_android_support() {
  if [[ -f "$PREFIX/lib/libandroid-support.a" ]]; then
    write_android_support_compat_header
    return
  fi

  local src_dir="$SRC/libandroid-support-${LIBANDROID_SUPPORT_VERSION}"
  local obj_dir="$BUILD/$ABI/libandroid-support/objects"
  rm -rf "$BUILD/$ABI/libandroid-support"
  mkdir -p "$obj_dir" "$PREFIX/lib" "$PREFIX/include"

  cp -f "$SRC/wcwidth-${WCWIDTH_VERSION}/wcwidth.c" "$src_dir/src/wcwidth.c"

  local c_file
  while IFS= read -r -d '' c_file; do
    "$CC" $CPPFLAGS $CFLAGS -std=c99 -DNULL=0 -fPIC \
      -c "$c_file" -o "$obj_dir/$(basename "$c_file").o"
  done < <(find "$src_dir/src" -type f -iname "*.c" -print0)

  "$AR" rcs "$PREFIX/lib/libandroid-support.a" "$obj_dir"/*.o
  "$RANLIB" "$PREFIX/lib/libandroid-support.a"
  write_android_support_compat_header
}

build_x11_deps() {
  build_android_support

  if [[ ! -f "$PREFIX/share/pkgconfig/xorg-macros.pc" ]]; then
    configure_build "util-macros" "$SRC/util-macros-${UTIL_MACROS_VERSION}"
  fi

  if [[ ! -f "$PREFIX/share/pkgconfig/xproto.pc" ]]; then
    configure_build "xorgproto" "$SRC/xorgproto-${XORGPROTO_VERSION}" \
      --disable-shared \
      --enable-static
  fi

  if [[ ! -f "$PREFIX/share/pkgconfig/xtrans.pc" ]]; then
    configure_build "xtrans" "$SRC/xtrans-${XTRANS_VERSION}" \
      --disable-shared \
      --enable-static
  fi

  if [[ ! -f "$PREFIX/lib/libXau.a" ]]; then
    configure_build "libXau" "$SRC/libXau-${LIBXAU_VERSION}" \
      --disable-shared \
      --enable-static
  fi

  if [[ ! -f "$PREFIX/lib/libXdmcp.a" ]]; then
    configure_build "libXdmcp" "$SRC/libXdmcp-${LIBXDMCP_VERSION}" \
      --disable-shared \
      --enable-static
  fi

  if [[ ! -f "$PREFIX/share/pkgconfig/xcb-proto.pc" ]]; then
    configure_build "xcb-proto" "$SRC/xcb-proto-${XCBPROTO_VERSION}" \
      --disable-shared
  fi

  if [[ ! -f "$PREFIX/lib/pkgconfig/pthread-stubs.pc" ]]; then
    configure_build "pthread-stubs" "$SRC/libpthread-stubs-${PTHREAD_STUBS_VERSION}" \
      --disable-shared \
      --enable-static
  fi

  local xcb_python_dir
  xcb_python_dir="$(find "$PREFIX/lib" -type d -path "*/site-packages" | head -n 1)"
  if [[ ! -f "$PREFIX/lib/libxcb.a" ]]; then
    export XCBPROTO_XCBINCLUDEDIR="$PREFIX/share/xcb"
    export XCBPROTO_XCBPYTHONDIR="$xcb_python_dir"
    export NEEDED_CFLAGS="-I$PREFIX/include"
    export NEEDED_LIBS="-L$PREFIX/lib -lXau -lXdmcp"
    configure_build "libxcb" "$SRC/libxcb-${LIBXCB_VERSION}" \
      --disable-dependency-tracking \
      --disable-shared \
      --enable-static \
      --without-doxygen
    unset XCBPROTO_XCBINCLUDEDIR XCBPROTO_XCBPYTHONDIR NEEDED_CFLAGS NEEDED_LIBS
  fi

  if [[ ! -f "$PREFIX/lib/libX11.a" ]]; then
    local saved_cflags="$CFLAGS"
    export LIBS="-landroid-support"
    export CFLAGS="$CFLAGS -include $TOOLCHAIN/sysroot/usr/include/xlocale.h -include $PREFIX/include/android-support-compat.h"
    configure_build "libX11" "$SRC/libX11-${LIBX11_VERSION}" \
      ac_cv_path_RAWCPP="$RAWCPP_WRAPPER" \
      CC_FOR_BUILD="$CC_FOR_BUILD_WRAPPER" \
      --disable-dependency-tracking \
      --disable-shared \
      --enable-static \
      --enable-malloc0returnsnull
    unset LIBS
    export CFLAGS="$saved_cflags"
  fi
}

prepare_sources() {
  download "https://github.com/madler/zlib/archive/refs/tags/v${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}.tar.gz"
  download "https://github.com/pnggroup/libpng/archive/refs/tags/v${LIBPNG_VERSION}.tar.gz" "libpng-${LIBPNG_VERSION}.tar.gz"
  download "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/${JPEG_TURBO_VERSION}.tar.gz" "libjpeg-turbo-${JPEG_TURBO_VERSION}.tar.gz"
  download "https://github.com/webmproject/libwebp/archive/refs/tags/v${WEBP_VERSION}.tar.gz" "libwebp-${WEBP_VERSION}.tar.gz"
  download "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz" "freetype-${FREETYPE_VERSION}.tar.xz"
  download "https://github.com/mm2/Little-CMS/archive/refs/tags/lcms${LCMS2_VERSION}.tar.gz" "lcms2-${LCMS2_VERSION}.tar.gz"
  download "https://download.osgeo.org/libtiff/tiff-${TIFF_VERSION}.tar.xz" "tiff-${TIFF_VERSION}.tar.xz"
  download "https://github.com/uclouvain/openjpeg/archive/refs/tags/v${OPENJPEG_VERSION}.tar.gz" "openjpeg-${OPENJPEG_VERSION}.tar.gz"
  download "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMAGEMAGICK_VERSION}.tar.gz" "ImageMagick-${IMAGEMAGICK_VERSION}.tar.gz"
  download "https://github.com/termux/libandroid-support/archive/refs/tags/v${LIBANDROID_SUPPORT_VERSION}.tar.gz" "libandroid-support-${LIBANDROID_SUPPORT_VERSION}.tar.gz"
  download "https://github.com/termux/wcwidth/archive/refs/tags/v${WCWIDTH_VERSION}.tar.gz" "wcwidth-${WCWIDTH_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/util/util-macros-${UTIL_MACROS_VERSION}.tar.gz" "util-macros-${UTIL_MACROS_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/proto/xorgproto-${XORGPROTO_VERSION}.tar.gz" "xorgproto-${XORGPROTO_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/lib/xtrans-${XTRANS_VERSION}.tar.gz" "xtrans-${XTRANS_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/lib/libXau-${LIBXAU_VERSION}.tar.gz" "libXau-${LIBXAU_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/lib/libXdmcp-${LIBXDMCP_VERSION}.tar.gz" "libXdmcp-${LIBXDMCP_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/xcb/xcb-proto-${XCBPROTO_VERSION}.tar.gz" "xcb-proto-${XCBPROTO_VERSION}.tar.gz"
  download "https://xcb.freedesktop.org/dist/libpthread-stubs-${PTHREAD_STUBS_VERSION}.tar.gz" "libpthread-stubs-${PTHREAD_STUBS_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/xcb/libxcb-${LIBXCB_VERSION}.tar.gz" "libxcb-${LIBXCB_VERSION}.tar.gz"
  download "https://xorg.freedesktop.org/archive/individual/lib/libX11-${LIBX11_VERSION}.tar.gz" "libX11-${LIBX11_VERSION}.tar.gz"

  extract "zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}"
  extract "libpng-${LIBPNG_VERSION}.tar.gz" "libpng-${LIBPNG_VERSION}"
  extract "libjpeg-turbo-${JPEG_TURBO_VERSION}.tar.gz" "libjpeg-turbo-${JPEG_TURBO_VERSION}"
  extract "libwebp-${WEBP_VERSION}.tar.gz" "libwebp-${WEBP_VERSION}"
  extract "freetype-${FREETYPE_VERSION}.tar.xz" "freetype-${FREETYPE_VERSION}"
  extract "lcms2-${LCMS2_VERSION}.tar.gz" "Little-CMS-lcms${LCMS2_VERSION}"
  extract "tiff-${TIFF_VERSION}.tar.xz" "tiff-${TIFF_VERSION}"
  extract "openjpeg-${OPENJPEG_VERSION}.tar.gz" "openjpeg-${OPENJPEG_VERSION}"
  extract "ImageMagick-${IMAGEMAGICK_VERSION}.tar.gz" "ImageMagick-${IMAGEMAGICK_VERSION}"
  extract "libandroid-support-${LIBANDROID_SUPPORT_VERSION}.tar.gz" "libandroid-support-${LIBANDROID_SUPPORT_VERSION}"
  extract "wcwidth-${WCWIDTH_VERSION}.tar.gz" "wcwidth-${WCWIDTH_VERSION}"
  extract "util-macros-${UTIL_MACROS_VERSION}.tar.gz" "util-macros-${UTIL_MACROS_VERSION}"
  extract "xorgproto-${XORGPROTO_VERSION}.tar.gz" "xorgproto-${XORGPROTO_VERSION}"
  extract "xtrans-${XTRANS_VERSION}.tar.gz" "xtrans-${XTRANS_VERSION}"
  extract "libXau-${LIBXAU_VERSION}.tar.gz" "libXau-${LIBXAU_VERSION}"
  extract "libXdmcp-${LIBXDMCP_VERSION}.tar.gz" "libXdmcp-${LIBXDMCP_VERSION}"
  extract "xcb-proto-${XCBPROTO_VERSION}.tar.gz" "xcb-proto-${XCBPROTO_VERSION}"
  extract "libpthread-stubs-${PTHREAD_STUBS_VERSION}.tar.gz" "libpthread-stubs-${PTHREAD_STUBS_VERSION}"
  extract "libxcb-${LIBXCB_VERSION}.tar.gz" "libxcb-${LIBXCB_VERSION}"
  extract "libX11-${LIBX11_VERSION}.tar.gz" "libX11-${LIBX11_VERSION}"

  if [[ -n "$(find "$SRC/libX11-${LIBX11_VERSION}/include/X11" -maxdepth 1 -name 'xlocale.h' -print -quit)" ]]; then
    mv "$SRC/libX11-${LIBX11_VERSION}/include/X11/xlocale.h" "$SRC/libX11-${LIBX11_VERSION}/include/X11/Xlocale.h.tmp"
    mv "$SRC/libX11-${LIBX11_VERSION}/include/X11/Xlocale.h.tmp" "$SRC/libX11-${LIBX11_VERSION}/include/X11/Xlocale.h"
  fi
}

build_one_abi() {
  abi_vars "$1"
  if [[ "${ONLY_IMAGEMAGICK:-0}" == "1" ]]; then
    case "$BUILD/$ABI/imagemagick" in
      "$BUILD"/*) rm -rf "$BUILD/$ABI/imagemagick" ;;
      *) echo "Refusing to clean unexpected ImageMagick build dir: $BUILD/$ABI/imagemagick" >&2; exit 1 ;;
    esac
  else
    case "$PREFIX" in
      "$OUT"/*) rm -rf "$PREFIX" ;;
      *) echo "Refusing to clean unexpected prefix: $PREFIX" >&2; exit 1 ;;
    esac
    case "$BUILD/$ABI" in
      "$BUILD"/*) rm -rf "$BUILD/$ABI" ;;
      *) echo "Refusing to clean unexpected build dir: $BUILD/$ABI" >&2; exit 1 ;;
    esac
    # The cleanup above also deleted what abi_vars put in $BUILD/$ABI (the
    # compiler wrapper scripts and TMPDIR), so create them again.
    abi_vars "$ABI"
  fi
  mkdir -p "$PREFIX"

  echo
  echo "============================================================"
  echo "Building for $ABI"
  echo "PREFIX=$PREFIX"
  echo "============================================================"

  if [[ "${ONLY_IMAGEMAGICK:-0}" != "1" ]]; then
    cmake_build "zlib" "$SRC/zlib-${ZLIB_VERSION}" \
      -DZLIB_BUILD_EXAMPLES=OFF \
      -DBUILD_SHARED_LIBS=OFF
    rm -f "$PREFIX/lib/libz.so"

    cmake_build "libpng" "$SRC/libpng-${LIBPNG_VERSION}" \
      -DPNG_SHARED=OFF \
      -DPNG_STATIC=ON \
      -DPNG_TESTS=OFF \
      -DZLIB_ROOT="$PREFIX"
    ensure_libpng_pkgconfig

    cmake_build "jpeg-turbo" "$SRC/libjpeg-turbo-${JPEG_TURBO_VERSION}" \
      -DENABLE_SHARED=OFF \
      -DENABLE_STATIC=ON \
      -DWITH_JAVA=OFF \
      -DWITH_TURBOJPEG=ON

    cmake_build "libwebp" "$SRC/libwebp-${WEBP_VERSION}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DWEBP_BUILD_ANIM_UTILS=OFF \
      -DWEBP_BUILD_CWEBP=OFF \
      -DWEBP_BUILD_DWEBP=OFF \
      -DWEBP_BUILD_GIF2WEBP=OFF \
      -DWEBP_BUILD_IMG2WEBP=OFF \
      -DWEBP_BUILD_VWEBP=OFF \
      -DWEBP_BUILD_WEBPINFO=OFF \
      -DWEBP_BUILD_WEBPMUX=OFF \
      -DWEBP_BUILD_EXTRAS=OFF

    cmake_build "freetype" "$SRC/freetype-${FREETYPE_VERSION}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DFT_DISABLE_BZIP2=TRUE \
      -DFT_DISABLE_BROTLI=TRUE \
      -DFT_DISABLE_HARFBUZZ=TRUE \
      -DFT_DISABLE_PNG=FALSE \
      -DFT_REQUIRE_ZLIB=TRUE

    build_lcms2

    cmake_build "openjpeg" "$SRC/openjpeg-${OPENJPEG_VERSION}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_CODEC=OFF \
      -DBUILD_TESTING=OFF

    cmake_build "tiff" "$SRC/tiff-${TIFF_VERSION}" \
      -DBUILD_SHARED_LIBS=OFF \
      -Dtiff-tools=OFF \
      -Dtiff-tests=OFF \
      -Dtiff-contrib=OFF \
      -Dtiff-docs=OFF \
      -Dzlib=ON \
      -Djpeg=ON \
      -Dwebp=ON \
      -Djpeg12=OFF \
      -Dlzma=OFF \
      -Dzstd=OFF
  fi
  ensure_libpng_pkgconfig
  build_x11_deps

  export ZLIB_CFLAGS="-I$PREFIX/include"
  export ZLIB_LIBS="-L$PREFIX/lib -lz"
  export PNG_CFLAGS="-I$PREFIX/include -I$PREFIX/include/libpng16"
  export PNG_LIBS="-L$PREFIX/lib -lpng16 -lz -lm"
  export LIBPNG_CFLAGS="$PNG_CFLAGS"
  export LIBPNG_LIBS="$PNG_LIBS"
  export FREETYPE_CFLAGS="-I$PREFIX/include/freetype2"
  export FREETYPE_LIBS="-L$PREFIX/lib -lfreetype -lz -lm"
  export TIFF_CFLAGS="-I$PREFIX/include"
  export TIFF_LIBS="-L$PREFIX/lib -ltiff -ljpeg -lwebp -lz -lm"
  export X_CFLAGS="-I$PREFIX/include"
  export X_LIBS="-L$PREFIX/lib -lX11 -lxcb -lXau -lXdmcp -landroid-support"

  # ImageMagick uses autotools. Build without runtime modules for Android.
  configure_build "imagemagick" "$SRC/ImageMagick-${IMAGEMAGICK_VERSION}" \
    --disable-docs \
    --disable-dependency-tracking \
    --disable-openmp \
    --without-utilities \
    --without-perl \
    --with-x \
    --without-modules \
    --with-magick-plus-plus \
    --with-quantum-depth=16 \
    --enable-hdri \
    --with-zlib \
    --with-png \
    --with-jpeg \
    --with-webp \
    --with-freetype \
    --with-lcms \
    --with-tiff \
    --without-fontconfig \
    --without-pango \
    --without-raqm \
    --disable-shared \
    --enable-static

  verify_static_symbol "$PREFIX/lib/libMagickCore-7.Q16HDRI.a" "RegisterPNGImage" "ImageMagick PNG coder"
  verify_static_symbol "$PREFIX/lib/libMagickCore-7.Q16HDRI.a" "RegisterJPEGImage" "ImageMagick JPEG coder"

  unset ZLIB_CFLAGS ZLIB_LIBS PNG_CFLAGS PNG_LIBS LIBPNG_CFLAGS LIBPNG_LIBS FREETYPE_CFLAGS FREETYPE_LIBS TIFF_CFLAGS TIFF_LIBS X_CFLAGS X_LIBS

  echo "==> Built $ABI"
  find "$PREFIX/lib" -maxdepth 1 -type f \( -name "*.so" -o -name "*.a" \) -printf "%f\n" | sort
}

prepare_sources

for abi in ${ABIS:-arm64-v8a armeabi-v7a x86 x86_64}; do
  build_one_abi "$abi"
done

echo
echo "Done. Android libraries are in:"
echo "$OUT"
