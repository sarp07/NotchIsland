<p align="center">
  <img src="docs/expanded-notch.png" width="720" alt="NotchIsland">
</p>

<h1 align="center">NotchIsland</h1>

<p align="center">
  Dynamic Island for your Mac's notch: music, volume, brightness, notifications, battery.<br>
  Works on Macs without a notch too.
</p>

<p align="center">
  <a href="https://github.com/sarp07/NotchIsland/releases/latest/download/NotchIsland.zip"><img src="https://img.shields.io/badge/Download%20for%20macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download NotchIsland for macOS" height="44"></a>
</p>

<p align="center"><b>English</b> · <a href="README.tr.md">Türkçe</a></p>

---

## Features

- 🎵 **Music:** Spotify, Apple Music, YouTube Music, Spotify Web. Cover art and playback controls.
- 🔊 **Volume and brightness:** shown in the island instead of the system popup.
- 🔔 **Notifications:** new WhatsApp, Mail, Telegram… badges pop up in the island.
- 🔋 **Battery and AirPods:** charging, low battery, headphones connected.
- 💻 **No notch? No problem.** A virtual island appears at the top of the screen.

Hover the island to expand it. Click to open or close.

<p align="center">
  <img src="docs/music-notch.png" width="400">
  <img src="docs/volume-notch.png" width="400">
  <img src="docs/notification-notch.png" width="400">
  <img src="docs/charging-no-notch.png" width="400">
</p>

## Install

Requirements: a Mac with **Apple Silicon** (M1 or newer) and **macOS 14** or later.

### Option 1: Download (easiest)

1. [**Download NotchIsland.zip**](https://github.com/sarp07/NotchIsland/releases/latest/download/NotchIsland.zip) and unzip it.
2. Drag `NotchIsland.app` into **Applications** and open it.

The app is signed and notarized by Apple, so it opens like any other app.

### Option 2: Build from source

```bash
git clone https://github.com/sarp07/NotchIsland.git
cd NotchIsland
./scripts/install.sh
```

If you see "Command Line Tools are required", run `xcode-select --install` first.

## First launch

1. Look for the **capsule icon** in the menu bar → **Settings**.
2. Grant **Accessibility** permission. Volume/brightness keys and notifications need it.
3. The first time music plays, macOS asks to let NotchIsland control Spotify / Music / your browser. Click **OK**.
4. Optional: turn on **Launch at login**.

## Privacy

- Sends **no data** anywhere: no analytics, no tracking. The only network request is Spotify cover art.
- Uses only official macOS features. It does not inject code into other apps and does not bypass system security.
- In your browser it reads only the **title and URL** of YouTube Music / Spotify tabs. Nothing else.

## Good to know

- macOS doesn't let apps read other apps' notification text. The island shows the **new-notification count** instead, for example "WhatsApp · 3 new".
- For players in the browser, seeking is not available.
- Intel Macs are not supported.

## Uninstall

Quit from the menu bar icon, then delete `/Applications/NotchIsland.app`.

## License

[MIT](LICENSE) © solazan
