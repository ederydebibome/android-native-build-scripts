# android-native-build-scripts

Two bash scripts that cross-compile C/C++ libraries for Android. They run on Windows, inside MSYS2, and use the NDK from Android Studio.

- `build-imagemagick-android.sh` builds [ImageMagick](https://imagemagick.org) with PNG, JPEG, WebP, TIFF, FreeType and LCMS support.
- `build-core-deps-android.sh` builds [curl](https://curl.se) with OpenSSL, HTTP/2, HTTP/3, SSH and compression, plus SQLite and nlohmann/json.

Both give you static libraries for `arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`, ready to link into a native app through the NDK or JNI.

## Why I wrote these

I built a desktop app for Windows, and I wrote all of its core myself as C/C++ DLLs. When I started the mobile version, I wanted that same native code to run on Android and behave exactly like it does on desktop. Not almost like it. Exactly. A few implementations that each behave a little differently will look alike, but put them together in one app and the small differences add up into differences you can actually notice.

That meant the libraries my code relies on had to be the same ones on Android too. This is where I got stuck: I couldn't find ready-made Android builds of them, so I compiled them myself.

For image processing, I built ImageMagick for Android instead of using what Android already ships with, `android.graphics`. It does similar things, but it isn't the same code, so I couldn't expect the same results. For downloads I needed curl, for the same reason, so I built that too, along with everything it depends on.

These scripts are what came out of it. I'm sharing them so that anyone in the same situation doesn't have to start from zero, or settle for alternatives that don't do exactly what they need.

## What you need

- Windows with [MSYS2](https://www.msys2.org) in `C:\msys64` (UCRT64 environment)
- The Android NDK, installed from Android Studio (SDK Manager > SDK Tools > NDK)
- `powershell.exe` and an internet connection, to download the sources
- These tools from MSYS2: `cmake`, `make`, `pkg-config`, `tar`, `sed`, `find`
- For the ImageMagick script, also `python` and the UCRT64 `gcc` (it builds a few small helper tools that run on your machine)
- For the curl script, also `perl`, which OpenSSL's `Configure` needs

Sources are downloaded from the official locations on the first run and reused after that. Every version is pinned at the top of each script.

## Usage

```bat
C:\msys64\usr\bin\bash.exe path\to\build-imagemagick-android.sh
C:\msys64\usr\bin\bash.exe path\to\build-core-deps-android.sh
```

The scripts look for the Android SDK in `%ANDROID_SDK_ROOT%`, then `%ANDROID_HOME%`, then `%LOCALAPPDATA%\Android\Sdk`, and take the newest NDK from its `ndk` folder. You can override that, and a few other things, with environment variables (both scripts):

| Variable | Meaning | Default |
| --- | --- | --- |
| `ANDROID_SDK_WIN` | Android SDK folder | see above |
| `ANDROID_NDK_WIN` | NDK folder | newest NDK in `<SDK>\ndk` |
| `API` | Android API level | `23` (ImageMagick), `24` (curl script) |
| `ABIS` | ABIs to build | `arm64-v8a armeabi-v7a x86 x86_64` |
| `JOBS` | parallel jobs | `4` |

For example, building only `arm64-v8a` with a specific NDK:

```bat
set ABIS=arm64-v8a
set ANDROID_NDK_WIN=C:/Users/you/AppData/Local/Android/Sdk/ndk/<version>
C:\msys64\usr\bin\bash.exe build-imagemagick-android.sh
```

---

## ImageMagick

Output, for each ABI:

```
C:\Tmp\imagemagick-android\out-static\<abi>\lib
C:\Tmp\imagemagick-android\out-static\<abi>\include
```

The main library is `libMagickCore-7.Q16HDRI.a`, next to `MagickWand` and the C++ `Magick++` API.

How it's built:

- ImageMagick 7.1.2-21, quantum depth 16, HDRI on
- Static only (`--disable-shared --enable-static`), no runtime modules
- Delegates: zlib, libpng, libjpeg-turbo, libwebp, FreeType, Little CMS 2, libtiff
- Left out: fontconfig, pango, raqm, OpenMP, Perl bindings, command-line tools, docs

After each ABI, the script checks that the PNG and JPEG coders are really inside the library and stops with an error if they aren't.

Extra variable:

| Variable | Meaning | Default |
| --- | --- | --- |
| `ONLY_IMAGEMAGICK` | `1` = rebuild only ImageMagick and keep the dependencies already built | off |

---

## curl and friends

Output, for each ABI:

```
C:\Tmp\android-core-deps\core-static\<abi>\lib
C:\Tmp\android-core-deps\core-static\<abi>\include
```

What gets built:

| Library | Version | Used for |
| --- | --- | --- |
| OpenSSL | 3.3.2 | TLS, and QUIC for HTTP/3 |
| curl | 8.10.1 | `libcurl` itself |
| zlib | 1.3.1 | gzip / deflate |
| brotli | 1.1.0 | brotli compression |
| zstd | 1.5.6 | zstd compression |
| c-ares | 1.34.3 | async DNS |
| nghttp2 | 1.64.0 | HTTP/2 |
| nghttp3 | 1.6.0 | HTTP/3 |
| libssh2 | 1.11.1 | SCP and SFTP |
| libunistring | 1.3 | needed by libidn2 |
| libidn2 | 2.3.7 | internationalized domain names |
| libpsl | 0.21.5 | public suffix list (built in, no file at runtime) |
| SQLite | 3.45.3 | built from the amalgamation, with FTS5 and JSON1 |
| nlohmann/json | 3.11.3 | header only, copied to `include/nlohmann/json.hpp` |

How it's built:

- Static only
- curl uses OpenSSL and has HTTP/2, HTTP/3, WebSockets, SCP/SFTP, brotli, zstd, c-ares (threaded resolver), libidn2 and libpsl. LDAP is off and the `curl` command-line tool isn't built.
- OpenSSL is built without apps and tests, and without assembly on `armeabi-v7a`
- The installed binaries and the `share` folder are deleted at the end, so only libraries and headers remain

After each ABI, the script reads `libcurl.pc` and checks that curl really has SSL, libz, brotli, zstd, AsynchDNS, HTTP2, HTTP3, IDN and PSL, and supports SCP, SFTP, WS and WSS. If anything is missing it stops with an error, so you don't end up with a stripped-down curl without noticing.

Extra variables:

| Variable | Meaning | Default |
| --- | --- | --- |
| `KEEP_PREFIX` | `1` = keep what's already in `core-static` and skip libraries that exist | off |
| `FORCE_CURL` | `1` = rebuild curl even if it already exists | off |

By default the script wipes an ABI's existing output before building it. To tweak the curl options and rebuild only curl:

```bat
set KEEP_PREFIX=1
set FORCE_CURL=1
C:\msys64\usr\bin\bash.exe build-core-deps-android.sh
```

curl is static, so your app has to link everything it depends on too. The exact list for your build is in `lib\pkgconfig\libcurl.pc`, under `Libs.private`.

---

## Notes

- **Spaces in paths.** Autotools can't deal with spaces in compiler paths, so the scripts convert the NDK path to its Windows 8.3 short form. That only works if 8.3 names are enabled on the drive (`fsutil 8dot3name query C:`). If they're not, install the NDK somewhere without spaces and set `ANDROID_NDK_WIN`.
- **Work folders.** Each script keeps its sources, builds and output in its own folder, `C:\Tmp\imagemagick-android` and `C:\Tmp\android-core-deps`. You can change them with `WORK_ROOT_WIN` at the top of each script.
- **One machine only.** I wrote and used these on a single Windows setup. If one fails on yours, open an issue with the error message and your NDK version.
