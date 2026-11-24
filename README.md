# Hypermesh Media Player (Open-Source Android & Flutter App)

A sleek, open-source cross-platform mobile client built with **Flutter** for the **Hypermesh Media Hub** ecosystem.

Connect your Android phone (or iOS / Web / Desktop client) to your personal Media Hub running on **an old PC, spare laptop, Raspberry Pi, or even another Android phone (Termux)** — and stream music, movies, and photos over Wi-Fi, Tailscale, or Cloudflare Tunnel with zero subscriptions.

> **Companion Server Repo:** Host your own personal media server & `yt-dlp` downloader using [`sahaveer/hypermesh-media-hub`](https://github.com/sahaveer/hypermesh-media-hub).

---

## Key Features

- **Unified Hypermesh Library**: Aggregates songs & videos across your personal Hub and nearby local mesh peers without duplicating files.
- **Multi-Mode Hub Connection**:
  - **Local Wi-Fi Mesh** (`http://192.168.x.x:8000`) — `0 MB` internet data used
  - **Tailscale Private Mesh** (`http://100.x.y.z:8000`) — encrypted WireGuard streaming anywhere
  - **Cloudflare Tunnel** (`https://*.trycloudflare.com`) — access over 4G/5G without router port forwarding
  - **Built-in Demo Hub** (`http://demo.hub`) — try the full player offline without running a server
- **Remote Server Downloader (`yt-dlp` Bridge)**: Send YouTube / Spotify / media links from your phone directly to your Hub's downloader queue or save locally.
- **Offline Pinning & Mobile-to-Mobile Mesh**: Pin peer tracks locally for offline playback and share your phone's local media over Wi-Fi using the built-in local mesh server.
- **Over-the-Air (OTA) & P2P APK Updates**: Pulls new Android APK builds from your Hub (`/hypermeshmediaplayer.apk`) or nearby mesh peers.
- **Obsidian / Neon UI**: Floating mini-player, expandable Now Playing sheet, Mesh Radar, Playlists, Video Player, and Host Admin tools.

---

## Quick Start

### Option 1: Install Prebuilt APK (End Users)
1. Check [GitHub Releases](https://github.com/sahaveer/hypermesh-mobile-app/releases) (or download directly from your running Hypermesh Media Hub at `http://<your-hub-ip>:8000/hypermeshmediaplayer.apk`).
2. Start a Hub on your PC, old laptop, Raspberry Pi, or spare phone using [`sahaveer/hypermesh-media-hub`](https://github.com/sahaveer/hypermesh-media-hub).
3. Open **Hypermesh Media Player**, enter your Hub URL (or tap **Localhost / Demo Hub**), and stream!

### Option 2: Build From Source (Developers)
```bash
git clone https://github.com/sahaveer/hypermesh-mobile-app.git
cd hypermesh-mobile-app
flutter pub get

# Run tests
flutter test

# Run on connected Android device / emulator
flutter run

# Build Android APK
flutter build apk --release
```

See [REQUIREMENTS.md](REQUIREMENTS.md) for Flutter SDK, Android SDK, Java, and host-server requirements, and [CONTRIBUTING.md](CONTRIBUTING.md) for architecture & release signing instructions.

---

## Project Structure

```
lib/
├── config/app_config.dart             # App version & build number
├── models/                            # Song, VideoItem, Playlist, PeerNode, PatchManifest
├── providers/                         # AuthProvider, HypermeshProvider, PlayerProvider
├── screens/                           # Home, Videos, VideoPlayer, MeshRadar, HubConnect, Login
├── services/                          # REST API, Local Mesh HTTP Server & UDP Discovery, OTA Updater
├── theme/app_theme.dart               # Obsidian / Cyan / Purple theme
└── widgets/                           # MiniPlayer, NowPlayingSheet, Downloader & Admin dialogs
```

---

## Documentation

- [REQUIREMENTS.md](REQUIREMENTS.md) — Android device requirements, developer build requirements, and companion server hardware options (Old PC, Laptop, Raspberry Pi, Termux)
- [CONTRIBUTING.md](CONTRIBUTING.md) — Developer setup, release APK signing (`android/key.properties.example`), and PR guidelines

---

## License

Released under the [MIT License](LICENSE). Fork, customize, build, and contribute freely!
