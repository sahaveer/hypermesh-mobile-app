# Requirements — Hypermesh Mobile App

## 1. End-User Device Requirements (Running the App)

| Platform | Minimum | Recommended |
| :--- | :--- | :--- |
| **Android** | Android 7.0+ (API 24+), 2 GB RAM, ~80 MB free storage | Android 10+, 4 GB+ RAM, Wi-Fi 5/6 |
| **iOS** *(build from source)* | iOS 13.0+ | iOS 15.0+ |
| **Web / Desktop** | Chrome, Edge, Windows, macOS, or Linux | Chrome / Desktop Flutter runner |

> **No Server Yet?** You can test the app immediately using the built-in **Demo Hub** (`http://demo.hub`) or run your own free Media Hub server on hardware you already have.

---

## 2. Companion Media Hub Server (What You Connect To)

To stream your own library and use the `yt-dlp` downloader, run [`sahaveer/hypermesh-media-hub`](https://github.com/sahaveer/hypermesh-media-hub) on **any** of these:

1. **Old PC or Spare Laptop** (Windows 10/11, Ubuntu/Linux, macOS — 1–2 GB RAM, dual-core CPU, Python 3.10+, Node.js 22+).
2. **Raspberry Pi** (Pi 3B+, 4, 5, or Zero 2 W running 64-bit Raspberry Pi OS + external USB HDD/SSD).
3. **Spare Android Phone / Tablet** (via **Termux** running Python + Node.js + FFmpeg as a pocket Wi-Fi server).

Full server hardware & setup instructions: [`hypermesh-media-hub/REQUIREMENTS.md`](https://github.com/sahaveer/hypermesh-media-hub/blob/main/REQUIREMENTS.md).

---

## 3. Developer Build Requirements (Compiling the App)

If you want to modify the code or build APKs yourself:

| Tool | Requirement |
| :--- | :--- |
| **Flutter SDK** | Flutter stable with Dart SDK `^3.14.0` (matching `pubspec.yaml`) |
| **Java JDK** | **JDK 17** (`compileOptions` and Kotlin `JVM_17` in `android/app/build.gradle.kts`) |
| **Android SDK & Build Tools** | Android Studio / Android SDK command-line tools + Android SDK Platform & NDK matching Flutter |
| **iOS / macOS Builds** *(optional)* | macOS with Xcode & CocoaPods |

### Release APK Signing (Optional)
Debug builds work out of the box (`flutter run` / `flutter build apk --debug`).  
For signed release builds:
1. Copy `android/key.properties.example` to `android/key.properties`.
2. Generate or reference your `.jks` keystore and set `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`.
3. Run `flutter build apk --release`.
4. Never commit `android/key.properties` or `.jks` files (both are in `.gitignore`).
