# LivoCut

LivoCut is a Flutter Android app for browsing an import folder, previewing MP4 files, marking multiple clip ranges, and exporting those ranges with FFmpeg stream copy.

## Build

The repository includes fixed Android release signing and is limited to `arm64-v8a` native packaging.

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

GitHub Actions builds the signed arm64 release APK on every push.
