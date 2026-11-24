# Contributing to Hypermesh Mobile App

Contributions, UI improvements, bug fixes, and platform enhancements are welcome!

---

## Getting Started

```bash
git clone https://github.com/sahaveer/hypermesh-mobile-app.git
cd hypermesh-mobile-app
flutter pub get
flutter test
```

## Useful Commands

```bash
# Static analysis
flutter analyze

# Unit & widget tests
flutter test

# Run on Android / Emulator
flutter run

# Run in Chrome (web preview)
flutter run -d chrome

# Build release APK (unsigned unless android/key.properties is configured)
flutter build apk --release
```

---

## Optional Configuration Files

- **Email OTP Auth (`lib/services/auth_service.dart`):** Defaults to `YOUR_SCRIPT_ID`, which enables offline Demo Mode (`OTP: 123456`). Users can paste a custom Google Apps Script Web App URL directly in the app settings/login UI without modifying source code.
- **Release Signing (`android/key.properties`):** See `android/key.properties.example`. Keep keystores and `key.properties` out of git.

---

## Pull Request Guidelines

1. Keep server API compatibility aligned with [`sahaveer/hypermesh-media-hub`](https://github.com/sahaveer/hypermesh-media-hub).
2. Run `flutter analyze` and `flutter test` before submitting a PR.
3. Never commit API keys, personal URLs, `.apk`/`.aab` binaries, or signing keystores.
