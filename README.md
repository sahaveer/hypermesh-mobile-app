# Hypermesh Media Player (Open-Source Mesh Player & Mobile Client)

[![Download Android APK](https://img.shields.io/badge/Download_APK-Latest-00E5FF?style=for-the-badge&logo=android&logoColor=black)](https://github.com/sahaveer/hypermesh-mobile-app/releases/latest/download/hypermeshmediaplayer.apk)

A sleek, open-source **Peer-to-Peer Mesh Media Player** built with **Flutter** for Android (plus iOS, Web, and Desktop).

---

## Install Directly on Android (No Build Needed)

You can download and run the app directly on any Android phone using the GitHub Release:

1. **Direct APK Download:** [`hypermeshmediaplayer.apk` (Latest Release)](https://github.com/sahaveer/hypermesh-mobile-app/releases/latest/download/hypermeshmediaplayer.apk)
   *(Or open the latest release page: https://github.com/sahaveer/hypermesh-mobile-app/releases/latest)*
2. Tap the downloaded `hypermeshmediaplayer.apk` file on your Android phone.
3. Allow **"Install unknown apps"** when prompted by Android, then open **Hypermesh Media Player**.

---

## How Hypermesh Works: Mesh Sharing + Optional Personal Server & YouTube Downloader

1. **Peer-to-Peer Mesh Player (Phone-to-Phone Over Wi-Fi / Hotspot)**
   - **Share videos and audio across anyone connected to your network** with **0 MB internet data used**.
   - Every phone running the app can turn on its built-in local mesh server and automatically appear on nearby devices' **Mesh Radar**, pooling everyone's songs and videos into one shared library.
   - Tap the pin icon on any peer's track or video to save an offline copy on your device.

2. **Add Your Own Personal Server + YouTube (`yt-dlp`) Downloader (Optional)**
   - Want to keep all your music & movies offline on a dedicated machine **and** download YouTube songs/videos directly into your local server library?
   - **Copy this server repo to your computer:**
     ```text
     https://github.com/sahaveer/hypermesh-media-hub
     ```
   - Run it on an **Old PC, Spare Laptop, Raspberry Pi, or spare Android phone (Termux)** to unlock 24/7 offline storage, Smart TV DLNA streaming, and server-side **`yt-dlp` + FFmpeg** downloading.

---

## Step-by-Step: Create Your Own Server, Connect Local Music & Download YouTube

### Step 1: Create Your Server on Any PC, Laptop, or Raspberry Pi
Paste these commands on your computer (requires Python 3.10+, Node.js 22+ or Deno 2.3+, and FFmpeg):
```bash
git clone https://github.com/sahaveer/hypermesh-media-hub.git
cd hypermesh-media-hub
pip install -r requirements.txt
python run_server.py
```
*(On Windows, you can also double-click `start_player.bat` or `start_global_player.bat`.)*

### Step 2: Connect Your Local Music & Video Folders
1. Open the server dashboard in your browser (`http://localhost:8000`).
2. Go to **Privacy & Folders** and add any folders on your PC/external drive containing your offline Music, Movies, Videos, or Photos.
3. Your entire library is indexed locally and shared across your network.

### Step 3: Connect the Android App to Your Server
1. Open **Hypermesh Media Player** on your phone → go to **Hub Settings / Hub Connect**.
2. Enter your server URL printed in the terminal:
   - **Same Wi-Fi:** `http://192.168.x.x:8000`
   - **Tailscale (from anywhere):** `http://100.x.y.z:8000`
   - **Cloudflare Tunnel (4G/5G):** `https://....trycloudflare.com`

### Step 4: Download YouTube Songs & Videos Later On
1. In **Hub Settings**, enable **Load GitHub Patch** → **Apply Patch** (activates the Web Media Importer using `/api/download` on your server).
2. Open the **Downloader** sheet in the app, paste any YouTube / Spotify / media link (or search query), pick **Audio (MP3)** or **Video (MP4)**, and choose **Server** (saves to your offline library for everyone on your mesh) or **Phone** (saves straight to your phone).

---

## Build From Source (Developers)

```bash
git clone https://github.com/sahaveer/hypermesh-mobile-app.git
cd hypermesh-mobile-app
flutter pub get
flutter test
flutter run
flutter build apk --release
```

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
