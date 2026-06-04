# Build ImageMagick Android For Lukia

Les bibliotheques ImageMagick de MSYS2 sont compilees pour Windows. Elles ne peuvent pas etre envoyees dans une application Android.

Il faut recompiler depuis les sources avec le NDK Android. Le script `build-imagemagick-android.sh` prepare une build par ABI :

- `arm64-v8a`
- `armeabi-v7a`
- `x86`
- `x86_64`

Sortie attendue :

```text
C:/Tmp/lukia-android-native/out-static/
  arm64-v8a/
    include/
    lib/
  armeabi-v7a/
    include/
    lib/
  x86/
    include/
    lib/
  x86_64/
    include/
    lib/
```

Les `.so` Android a copier dans Android Studio seront dans :

```text
out-static/<ABI>/lib/
```

Commande depuis PowerShell :

```powershell
C:\msys64\usr\bin\bash.exe "C:\Users\Edery Eyi\Documents\Codex\2026-05-12\files-mentioned-by-the-user-img\android-imagemagick-build\build-imagemagick-android.sh"
```

Important : ce script construit ImageMagick avec `--without-modules`. Cela veut dire que les coders ImageMagick sont integres dans `libMagickCore`, au lieu de devoir gerer un dossier `coders/` au runtime Android.

Le script verifie maintenant explicitement que les coders natifs PNG et JPEG sont bien integres (`RegisterPNGImage`, `RegisterJPEGImage`). Si PNG n'est pas detecte par ImageMagick, la build s'arrete au lieu de produire une librairie Android incapable de lire/ecrire les fichiers PNG.
