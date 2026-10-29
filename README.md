# android-native-build-scripts

Bash scripts that cross-compile C/C++ libraries for Android. They run on Windows, inside MSYS2, and use the NDK from Android Studio. There is one script per project, and each one builds only that project and what it depends on:

- `build-imagemagick-android.sh` builds [ImageMagick](https://imagemagick.org) with PNG, JPEG, WebP, TIFF, FreeType and LCMS support.
- `build-curl-android.sh` builds [curl](https://curl.se) with OpenSSL, HTTP/2, HTTP/3, SSH and compression, together with every library it needs.
- `build-sqlite-android.sh` builds [SQLite](https://sqlite.org) from the amalgamation, with FTS5 and JSON1.
- `build-taglib-android.sh` builds [TagLib](https://taglib.org) 2.x, the audio tag library, together with zlib and the utf8cpp library it needs.

Both give you static libraries for `arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`, ready to link into a native app through the NDK or JNI.

The code they share (finding the NDK, setting up each ABI, downloading sources, looking up the newest versions) lives in `lib/common.sh`. The scripts need that folder next to them, so clone or download the whole repository, not a single file. Adding a project means adding one new `build-<name>-android.sh` that loads it.

## Why I wrote these

This started with a Windows desktop app. I wrote its whole core in C and C++, as DLLs, so when it was time to build the mobile version, the obvious plan was to take that same code and run it on Android. The point was to get exactly the same behavior on every platform, because two libraries that do the same job rarely do it the same way. One rounds a bit differently, another decodes a bit differently, a third has different defaults. Each difference is tiny, but stack enough of them in one app and you get an Android version that looks a lot like the desktop one without really being the same, which is a pain to track down.

That's why I didn't want to swap my libraries for whatever Android offers. My native code was already built around ImageMagick, so using `android.graphics` instead would have meant rewriting all that logic, just to end up with a result that's roughly what Windows gives me. No thanks. The catch was that I couldn't find ready-made Android builds of ImageMagick, or of curl, which I also needed for downloads. So I built them myself, and that's what these scripts do.

I'm sharing them in case you're stuck at the same point. If you need a library to behave on Android the way it does everywhere else, you shouldn't have to start from zero, or settle for an alternative that does almost what you want.

## What you need

- Windows with [MSYS2](https://www.msys2.org) in `C:\msys64` (UCRT64 environment)
- The Android NDK, installed from Android Studio (SDK Manager > SDK Tools > NDK)
- `powershell.exe` and an internet connection, to download the sources and look up versions
- These tools from MSYS2: `cmake`, `make`, `pkg-config`, `tar`, `sed`, `find`
- For the ImageMagick script, also `python` and the UCRT64 `gcc` (it builds a few small helper tools that run on your machine)
- For the curl script, also `perl`, which OpenSSL's `Configure` needs

Sources are downloaded from the official locations on the first run and reused after that.

## Usage

```bat
C:\msys64\usr\bin\bash.exe path\to\build-imagemagick-android.sh
C:\msys64\usr\bin\bash.exe path\to\build-curl-android.sh
C:\msys64\usr\bin\bash.exe path\to\build-sqlite-android.sh
C:\msys64\usr\bin\bash.exe path\to\build-taglib-android.sh
```

The scripts look for the Android SDK in `%ANDROID_SDK_ROOT%`, then `%ANDROID_HOME%`, then `%LOCALAPPDATA%\Android\Sdk`, and take the newest NDK from its `ndk` folder. You can override that, and a few other things, with environment variables (both scripts):

| Variable | Meaning | Default |
| --- | --- | --- |
| `ANDROID_SDK_WIN` | Android SDK folder | see above |
| `ANDROID_NDK_WIN` | NDK folder | newest NDK in `<SDK>\ndk` |
| `API` | Android API level | `23` (ImageMagick), `24` (curl, SQLite and TagLib) |
| `ABIS` | ABIs to build | `arm64-v8a armeabi-v7a x86 x86_64` |
| `JOBS` | parallel jobs | `4` |

For example, building only `arm64-v8a` with a specific NDK:

```bat
set ABIS=arm64-v8a
set ANDROID_NDK_WIN=C:/Users/you/AppData/Local/Android/Sdk/ndk/<version>
C:\msys64\usr\bin\bash.exe build-imagemagick-android.sh
```

### Versions

Each script has a default version for every library it builds. At the start it looks online for newer releases, prints what it finds, and uses a newer version when there is one. If a lookup fails, it keeps the default and says so. To skip the lookup for one library, set its variable before running, for example `IMAGEMAGICK_VERSION=7.1.2-21`, `CURL_VERSION=8.10.1` or `ZLIB_VERSION=1.3.1` (the names are at the top of each script). SQLite's download address also contains the release year, so to pin a version that isn't the current one, set `SQLITE_YEAR` too, for example `SQLITE_VERSION=3.45.3 SQLITE_YEAR=2024`. A brand-new release can break a build, so pin the versions if you need a reproducible result.

---

## ImageMagick

Output, for each ABI:

```
C:\Tmp\imagemagick-android\out-static\<abi>\lib
C:\Tmp\imagemagick-android\out-static\<abi>\include
```

The main library is `libMagickCore-7.Q16HDRI.a`, next to `MagickWand` and the C++ `Magick++` API.

How it's built:

- ImageMagick (the newest release found online, or the one you pin), quantum depth 16, HDRI on
- Static only (`--disable-shared --enable-static`), no runtime modules
- Delegates: zlib, libpng, libjpeg-turbo, libwebp, FreeType, Little CMS 2, libtiff
- Left out: fontconfig, pango, raqm, OpenMP, Perl bindings, command-line tools, docs

After each ABI, the script checks that the PNG and JPEG coders are really inside the library and stops with an error if they aren't.


Extra variable:

| Variable | Meaning | Default |
| --- | --- | --- |
| `ONLY_IMAGEMAGICK` | `1` = rebuild only ImageMagick and keep the dependencies already built | off |

---

## curl

Output, for each ABI:

```
C:\Tmp\curl-android\out-static\<abi>\lib
C:\Tmp\curl-android\out-static\<abi>\include
```

What gets built:

| Library | Used for |
| --- | --- |
| OpenSSL | TLS, and QUIC for HTTP/3 |
| curl | `libcurl` itself |
| zlib | gzip / deflate |
| brotli | brotli compression |
| zstd | zstd compression |
| c-ares | async DNS |
| nghttp2 | HTTP/2 |
| nghttp3 | HTTP/3 |
| libssh2 | SCP and SFTP |
| libunistring | needed by libidn2 |
| libidn2 | internationalized domain names |
| libpsl | public suffix list (built in, no file at runtime) |

How it's built:

- Static only
- curl uses OpenSSL and has HTTP/2, HTTP/3, WebSockets, SCP/SFTP, brotli, zstd, c-ares (threaded resolver), libidn2 and libpsl. LDAP is off and the `curl` command-line tool isn't built.
- OpenSSL is built without apps and tests, and without assembly on `armeabi-v7a`
- The installed binaries and the `share` folder are deleted at the end, so only libraries and headers remain

After each ABI, the script reads `libcurl.pc` and checks that curl really has SSL, libz, brotli, zstd, AsynchDNS, HTTP2, HTTP3, IDN and PSL, and supports SCP, SFTP, WS and WSS. If anything is missing it stops with an error, so you don't end up with a stripped-down curl without noticing.

Extra variables:

| Variable | Meaning | Default |
| --- | --- | --- |
| `KEEP_PREFIX` | `1` = keep what's already in the output folder and skip libraries that exist | off |
| `FORCE_CURL` | `1` = rebuild curl even if it already exists | off |

By default the script wipes an ABI's existing output before building it. To tweak the curl options and rebuild only curl:

```bat
set KEEP_PREFIX=1
set FORCE_CURL=1
C:\msys64\usr\bin\bash.exe build-curl-android.sh
```

curl is static, so your app has to link everything it depends on too. The exact list for your build is in `lib\pkgconfig\libcurl.pc`, under `Libs.private`.

---

## SQLite

Output, for each ABI:

```
C:\Tmp\sqlite-android\out-static\<abi>\lib
C:\Tmp\sqlite-android\out-static\<abi>\include
```

The library is `libsqlite3.a`, with `sqlite3.h` in `include`. It is compiled straight from SQLite's amalgamation (one `.c` file) with `SQLITE_THREADSAFE=1`, FTS5 and JSON1 turned on.

The script reads the SQLite download page to find the newest version. Its download address contains the release year and the version packed into one number (3.45.3 becomes 3450300), and the script works both out for you.

Extra variable:

| Variable | Meaning | Default |
| --- | --- | --- |
| `KEEP_PREFIX` | `1` = keep the library that is already built | off |

---

## TagLib

Output, for each ABI:

```
C:\Tmp\taglib-android\out-static\<abi>\lib
C:\Tmp\taglib-android\out-static\<abi>\include
```

This is TagLib 2.x, the generation that needs a C++17 compiler and uses the header-only [utf8cpp](https://github.com/nemtrif/utfcpp) library for its UTF-8 handling. The script downloads utf8cpp itself and points TagLib's CMake at it, because TagLib's GitHub archive doesn't include it (it is a Git submodule there).

What gets built: zlib (TagLib uses it for compressed ID3v2 frames) and TagLib as a static library (`libtag.a`, plus the C bindings `libtag_c.a`). Tests and examples are off.

Extra variable:

| Variable | Meaning | Default |
| --- | --- | --- |
| `KEEP_PREFIX` | `1` = keep the libraries that are already built | off |

---

## Notes

- **Spaces in paths.** Autotools can't deal with spaces in compiler paths, so the scripts convert the NDK path to its Windows 8.3 short form. That only works if 8.3 names are enabled on the drive (`fsutil 8dot3name query C:`). If they're not, install the NDK somewhere without spaces and set `ANDROID_NDK_WIN`.
- **Work folders.** Each script keeps its sources, builds and output in its own folder, `C:\Tmp\imagemagick-android`, `C:\Tmp\curl-android`, `C:\Tmp\sqlite-android` and `C:\Tmp\taglib-android`. You can change them with `WORK_ROOT_WIN` at the top of each script.
- **One machine only.** I wrote and used these on a single Windows setup. If one fails on yours, open an issue with the error message and your NDK version.
