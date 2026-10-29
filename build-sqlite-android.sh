#!/usr/bin/env bash
set -euo pipefail

# Cross-compile SQLite for Android (static library), from the amalgamation
# (a single .c file), with FTS5 and JSON1 enabled.
# Needs lib/common.sh (shared code) from the same repository.
# Run with:
#   C:\msys64\usr\bin\bash.exe path\to\build-sqlite-android.sh
#
# Optional environment variables:
#   ANDROID_SDK_WIN   Android SDK folder
#                     (default: %ANDROID_SDK_ROOT%, %ANDROID_HOME%, or
#                     %LOCALAPPDATA%\Android\Sdk)
#   ANDROID_NDK_WIN   NDK folder (default: the newest one in <SDK>\ndk)
#   API               Android API level (default: 24)
#   ABIS              ABIs to build (default: arm64-v8a armeabi-v7a x86 x86_64)
#   JOBS              parallel jobs (default: 4)
#   KEEP_PREFIX       set to 1 to keep the library that is already built
#   SQLITE_VERSION    skip the online lookup and use this version, for example
#                     3.45.3 (for a version that is not the current one, also
#                     set SQLITE_YEAR, see below)
#   SQLITE_YEAR       release year of that version, as it appears in the
#                     download address (for example 2024)

# Settings for this project, read by lib/common.sh.
DEFAULT_API=24
WORK_ROOT_WIN="C:/Tmp/sqlite-android"
BUILD_NAME="build-static"
OUT_NAME="out-static"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# The newest SQLite version listed on the download page.
sqlite_latest_version() {
  http_get "https://www.sqlite.org/download.html" \
    | grep -o 'PRODUCT,[0-9.]*,[0-9]*/sqlite-amalgamation-[0-9]*\.zip' \
    | cut -d, -f2 \
    | sort -V | tail -n 1
}

# The release year of a version, from the same page.
sqlite_release_year() {
  http_get "https://www.sqlite.org/download.html" \
    | grep -o "PRODUCT,$1,[0-9]*/" \
    | head -n 1 \
    | cut -d, -f3 | tr -d '/'
}

# Default version (the one this script was last tested with) and its year.
# At the start, the script looks for a newer release online and uses it when
# it finds one.
SQLITE_DEFAULT_VERSION="3.45.3"
SQLITE_DEFAULT_YEAR="2024"
echo "==> Checking for a newer version of SQLite (a few seconds)"
resolve_version SQLITE "$SQLITE_DEFAULT_VERSION" sqlite_latest_version

# The download address contains the release year, and the version packed into
# one number (3.45.3 becomes 3450300).
if [[ -z "${SQLITE_YEAR:-}" ]]; then
  SQLITE_YEAR="$(sqlite_release_year "$SQLITE_VERSION" || true)"
  if [[ -z "$SQLITE_YEAR" && "$SQLITE_VERSION" == "$SQLITE_DEFAULT_VERSION" ]]; then
    SQLITE_YEAR="$SQLITE_DEFAULT_YEAR"
  fi
  if [[ -z "$SQLITE_YEAR" ]]; then
    echo "ERROR: could not find the release year of SQLite $SQLITE_VERSION." >&2
    echo "Set it yourself with SQLITE_YEAR=<year>." >&2
    exit 1
  fi
fi
IFS=. read -r sqlite_major sqlite_minor sqlite_patch <<< "$SQLITE_VERSION"
SQLITE_AMALGAMATION="sqlite-amalgamation-$(printf '%d%02d%02d00' "$sqlite_major" "$sqlite_minor" "${sqlite_patch:-0}")"
echo "==> Using SQLite $SQLITE_VERSION ($SQLITE_YEAR)"
echo "==> Version check done"

abi_vars() {
  select_abi "$1"
  PREFIX="$OUT/$ABI"
  export PATH="$TOOLCHAIN/bin:/ucrt64/bin:/usr/bin:/bin:$PATH"
  export CC="$TOOLCHAIN/bin/${CLANG_PREFIX}${API}-clang"
  export AR="$TOOLCHAIN/bin/llvm-ar"
  export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
  export CFLAGS="-O2 -fPIC -DANDROID"
}

prepare_sources() {
  download "https://www.sqlite.org/${SQLITE_YEAR}/${SQLITE_AMALGAMATION}.zip" "${SQLITE_AMALGAMATION}.zip"
  extract "${SQLITE_AMALGAMATION}.zip" "${SQLITE_AMALGAMATION}"
}

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
  echo "Building SQLite for $ABI"
  echo "PREFIX=$PREFIX"
  echo "============================================================"

  build_sqlite

  find "$PREFIX/lib" -maxdepth 1 -type f -name "*.a" -printf "%f\n" | sort
done

echo
echo "Done. SQLite is in:"
echo "$OUT"
