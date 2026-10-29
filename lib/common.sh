#!/usr/bin/env bash
# Shared code for the build-*-android.sh scripts. It is meant to be sourced,
# not run. The calling script must set these variables first:
#   DEFAULT_API    Android API level to use when API is not set
#   WORK_ROOT_WIN  work folder, for example C:/Tmp/imagemagick-android
#   BUILD_NAME     name of the build folder inside the work folder
#   OUT_NAME       name of the output folder inside the work folder
: "${DEFAULT_API:?lib/common.sh: DEFAULT_API is not set}"
: "${WORK_ROOT_WIN:?lib/common.sh: WORK_ROOT_WIN is not set}"
: "${BUILD_NAME:?lib/common.sh: BUILD_NAME is not set}"
: "${OUT_NAME:?lib/common.sh: OUT_NAME is not set}"

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
API="${API:-$DEFAULT_API}"

WORK_ROOT="$(cygpath -u "$WORK_ROOT_WIN")"
SRC="$WORK_ROOT/src"
BUILD="$WORK_ROOT/$BUILD_NAME"
OUT="$WORK_ROOT/$OUT_NAME"

JOBS="${JOBS:-4}"

mkdir -p "$SRC" "$BUILD" "$OUT"

# Version lookup helpers. Each one prints a version number, or nothing if the
# lookup fails.
http_get() {
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "\$ProgressPreference='SilentlyContinue'; (Invoke-WebRequest -UseBasicParsing -Uri '$1').Content" \
    2>/dev/null | tr -d '\r'
}

# Latest GitHub release of <owner/repo>, with <tag prefix> removed from the tag.
# If the repo has no releases, use its highest version tag instead.
github_version() {
  local version
  version="$(http_get "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1 \
    | sed "s/^$2//")" || true
  if [[ -z "$version" ]]; then
    version="$(http_get "https://api.github.com/repos/$1/tags?per_page=100" \
      | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | sed 's/.*"\([^"]*\)"$/\1/' \
      | grep "^$2[0-9][0-9.]*$" \
      | sed "s/^$2//" \
      | sort -V | tail -n 1)" || true
  fi
  printf '%s\n' "$version"
}

# Highest version in a directory listing, from file names like <prefix>1.2.3<suffix>.
listing_version() {
  http_get "$1" \
    | grep -o "$2[0-9][0-9.]*$3" \
    | sed "s/^$2//; s/$3\$//" \
    | sort -V | tail -n 1
}

# resolve_version <NAME> <default version> <lookup command...>
# Sets <NAME>_VERSION and prints what it did. A value you set yourself wins.
# Otherwise it looks for the newest upstream version and uses it if it is newer
# than the default. If the lookup fails, the default is kept.
resolve_version() {
  local name="$1" default="$2" var="${1}_VERSION" found
  shift 2
  if [[ -n "${!var:-}" ]]; then
    printf '    %-20s %s (set by you, no lookup)\n' "${name,,}" "${!var}"
    return
  fi
  printf '    %-20s default %s, looking for a newer one... ' "${name,,}" "$default"
  found="$("$@" 2>/dev/null || true)"
  if [[ -z "$found" ]]; then
    echo "lookup failed, keeping $default"
    printf -v "$var" '%s' "$default"
  elif [[ "$found" != "$default" && "$(printf '%s\n%s\n' "$default" "$found" | sort -V | tail -n 1)" == "$found" ]]; then
    echo "found $found, using it"
    printf -v "$var" '%s' "$found"
  else
    echo "already up to date"
    printf -v "$var" '%s' "$default"
  fi
}

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

# extract <archive> <folder it creates> [extra tar options]
# Handles .zip and tar archives.
extract() {
  local file="$1"
  local dir="$2"
  shift 2
  if [[ ! -d "$SRC/$dir" ]]; then
    echo "==> Extract $file"
    case "$file" in
      *.zip)
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
          "Expand-Archive -LiteralPath '$(cygpath -w "$SRC/$file")' -DestinationPath '$(cygpath -w "$SRC")' -Force"
        ;;
      *)
        tar "$@" -xf "$SRC/$file" -C "$SRC"
        ;;
    esac
  fi
}

# Set ABI, ANDROID_ABI, HOST and CLANG_PREFIX for one ABI name.
select_abi() {
  ABI="$1"
  case "$ABI" in
    arm64-v8a)
      ANDROID_ABI="arm64-v8a"
      HOST="aarch64-linux-android"
      CLANG_PREFIX="aarch64-linux-android"
      ;;
    armeabi-v7a)
      ANDROID_ABI="armeabi-v7a"
      HOST="arm-linux-androideabi"
      CLANG_PREFIX="armv7a-linux-androideabi"
      ;;
    x86)
      ANDROID_ABI="x86"
      HOST="i686-linux-android"
      CLANG_PREFIX="i686-linux-android"
      ;;
    x86_64)
      ANDROID_ABI="x86_64"
      HOST="x86_64-linux-android"
      CLANG_PREFIX="x86_64-linux-android"
      ;;
    *)
      echo "Unknown ABI: $ABI" >&2
      exit 1
      ;;
  esac
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
