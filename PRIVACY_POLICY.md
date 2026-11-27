# Privacy Policy — Hypermesh Media Player

**Effective Date:** 2026-11-28  
**Project:** Hypermesh Media Player (`sahaveer/hypermesh-mobile-app`)

Hypermesh Media Player is an open-source, self-hosted, peer-to-peer (P2P) media player. There is no central Hypermesh cloud server collecting or monetizing your listening or viewing history.

## 1. Data Stored Locally on Your Device
The app stores the following configuration and library state locally via `SharedPreferences` and app-private storage:
- Optional sign-in email (`auth_user_email`) and local session token (`auth_token`)
- Optional user-configured Google Apps Script URL (`auth_script_url`)
- Your personal Media Hub URL(s), paired LAN peer tokens, playlists, favorites, hidden item IDs, and locally indexed media paths
- Optional settings such as background mesh sharing and peer update preferences

You can clear this data at any time by signing out, disconnecting your hub, removing shared folders, or uninstalling/clearing app storage in Android/iOS settings.

## 2. Optional Email OTP Sign-In
- You can use Hypermesh completely offline or on your local network as a **Guest** without signing in.
- If you choose Email OTP Sign-In, the app sends your email address only to the Google Apps Script endpoint configured at build time or by you in the login settings.

## 3. Permissions & How They Are Used
- **Local Network / Wi-Fi / Multicast:** Used only to discover and stream audio/video between your devices and your self-hosted Hypermesh Media Hub on your local network or Tailscale.
- **Audio & Video Media Access (`READ_MEDIA_AUDIO` / `READ_MEDIA_VIDEO`):** Used to browse and play your local audio/video files. Scanned device media stays private on your device (`sharedWithMesh = false`) unless you explicitly share a file or folder with your local mesh.
- **Camera (`CAMERA`):** Used solely when you open the QR scanner to pair with a nearby device or personal hub. No photos or video frames are saved or uploaded.
- **Notifications / Foreground Service:** Used to keep local media playback and background mesh sharing running reliably when requested.

## 4. Third-Party Services & Analytics
- Hypermesh Media Player includes **no** third-party ad SDKs, behavioral analytics, or cross-app tracking.
- If you tap **Check for Updates**, the app queries GitHub Releases (`api.github.com/repos/sahaveer/hypermesh-mobile-app/releases/latest`) or your paired local mesh peers.

## 5. Contact & Source Code
Hypermesh Media Player is open-source under the MIT License:  
https://github.com/sahaveer/hypermesh-mobile-app
