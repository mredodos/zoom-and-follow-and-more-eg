<div align="center">

# Zoom, Follow Mouse & More - By Edoardo Guzzi

**Dynamic zoom and mouse tracking for any video source in OBS.**

![Version](https://img.shields.io/badge/version-2.2.0-blue?style=flat-square)
![OBS](https://img.shields.io/badge/OBS_Studio-30.0%2B-purple?style=flat-square)
![Lua](https://img.shields.io/badge/Lua-5.1%2B-blue?style=flat-square&logo=lua)
![License](https://img.shields.io/github/license/mredodos/zoom-and-follow-and-more-eg?style=flat-square&color=green)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey?style=flat-square)
![GitHub stars](https://img.shields.io/github/stars/mredodos/zoom-and-follow-and-more-eg?style=flat-square)
![GitHub issues](https://img.shields.io/github/issues/mredodos/zoom-and-follow-and-more-eg?style=flat-square)

[![Changelog](https://img.shields.io/badge/changelog-view-blue?style=flat-square)](CHANGELOG.md)

*Zoom into any part of your screen during recordings or live streams — with smooth animations, mouse follow, and multi-monitor support.*

</div>

---

> **Note** — This is a third-party community script. It is not developed, maintained, or endorsed by the OBS Project.

## Features

| Feature | Description |
|---|---|
| **Smooth Zoom** | Animated zoom-in/out with configurable duration (instant to cinematic) |
| **Mouse Follow** | Viewport tracks the mouse with adjustable smoothing — via the Follow hotkey or the optional **Auto-follow** mode |
| **Works with any source** | Capability-based detection: any video source is supported (screen/display/window/game capture, browser, media…) on every OS and OBS version |
| **Nested scenes & groups** | Drills down to the original capture source inside nested scenes and groups; optional **Preferred Source** picker |
| **HiDPI / Retina aware** | Correct tracking on high-DPI displays and scaled desktops, not just 1:1 monitors |
| **Multi-Monitor** | Automatic monitor detection and correct coordinate mapping |
| **Anti-Flicker** | Deadzone and threshold system eliminates visual jitter |
| **Hotkey Driven** | Toggle zoom and follow independently via OBS hotkeys |
| **Scene Aware** | Smooth transitions when switching scenes while zoomed |
| **Debug Mode** | Detailed logging for troubleshooting |

## Quick Start

### 1. Install

1. Download **`zoom-follow-mouse-and-more-eg.lua`**. Use one of these so you get the *script*, not a web page:
   - **Releases** (recommended): grab the `.lua` asset from the [latest release](https://github.com/mredodos/zoom-and-follow-and-more-eg/releases), **or**
   - **Raw link**: open [the raw file](https://raw.githubusercontent.com/mredodos/zoom-and-follow-and-more-eg/main/zoom-follow-mouse-and-more-eg.lua) → right-click → **Save As…** (keep the `.lua` extension).
2. In OBS: **Tools > Scripts > "+"** and select the file

> ⚠️ **Don't** use *File → Save Page As* on the GitHub code viewer — that saves an HTML page and OBS will report `Error loading file: ... unexpected symbol near '<'`. Always use the Releases asset or the Raw link above.

### 2. Set Hotkeys

Go to **File > Settings > Hotkeys** and assign keys for:
- **Toggle Zoom** — activates/deactivates zoom
- **Toggle Follow** — the viewport follows the mouse while zoomed in

### 3. Prepare Your Source

> **Important** — Select your source and press **Ctrl+F** (Fit to Screen) before activating zoom. This ensures accurate mouse-to-crop mapping.

### 4. Use It

Press your zoom hotkey to zoom in at the mouse position. Press again to zoom out. Toggle follow to have the viewport track the mouse while zoomed.

---

## Settings

### Main

| Setting | Range | Default | What it does |
|---|---|---|---|
| **Zoom Value** | 1.1 – 100 | 2.0 | Zoom multiplier. Quality depends on source resolution. |
| **Zoom In Duration** | 1 – 60 000 ms | 300 ms | Animation length for zooming in. Set to `1` for instant. |
| **Zoom Out Duration** | 1 – 60 000 ms | 500 ms | Animation length for zooming out. Set to `1` for instant. |
| **Follow Speed** | 0.01 – 1.0 | 1.0 | How fast the viewport tracks the mouse. `1.0` = instant, `0.1` = smooth glide. |
| **Auto-follow while zoomed** | on/off | **off** | When on, the viewport follows the mouse as soon as you zoom in — no separate hotkey needed. The Follow hotkey still works as a freeze/unfreeze toggle. |
| **Preferred Source (optional)** | source name | *(automatic)* | Pin which source to zoom by name. Leave empty to auto-pick the first capture found (drilling into nested scenes and groups). |
| **Debug Mode** | on/off | off | Enables detailed logging in OBS Script Logs. |

> **Tip** — If you just want "zoom and it follows", turn on **Auto-follow while zoomed** and you can ignore the Follow hotkey entirely.

> **Tip** — For tutorials and coding, use Follow Speed `1.0` (instant tracking). For presentations and gameplay, try `0.1–0.3` for a smooth camera feel.

### Advanced

<details>
<summary>Click to expand advanced settings</summary>

#### Performance

| Setting | Range | Default | What it does |
|---|---|---|---|
| Update Interval | 8 – 100 ms | 16 ms | Tick rate. 16 ms ≈ 60 fps, 8 ms ≈ 120 fps. |
| Mouse Cache Duration | 4 – 32 ms | 8 ms | How long to cache mouse position (reduces FFI calls). |

#### Anti-Flickering

| Setting | Range | Default | What it does |
|---|---|---|---|
| Mouse Deadzone | 1 – 10 px | 3 px | Minimum mouse movement to trigger a viewport update. |
| Crop Update Threshold | 1 – 10 px | 2 px | Minimum crop change to apply. Prevents micro-jitter. |
| Crop Edge Threshold | 1 – 20 px | 5 px | Increased threshold at screen edges/corners. |

#### Other

| Setting | Range | Default | What it does |
|---|---|---|---|
| Scene Transition Duration | 100 – 1000 ms | 300 ms | Smoothness of crop transitions during scene changes. |
| Default Monitor Width | 640 – 7680 | 1920 | Fallback if monitor detection fails. |
| Default Monitor Height | 480 – 4320 | 1080 | Fallback if monitor detection fails. |

</details>

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `Error loading file: ... unexpected symbol near '<'` | You saved the GitHub **HTML page** instead of the script. Re-download from **Releases** or the **Raw** link (see [Install](#1-install)). |
| Zoom doesn't activate | Check source has valid dimensions. Press **Ctrl+F** on source first. |
| Zoom centers but doesn't follow the mouse | Follow is a separate action: press the **Toggle Follow** hotkey, or enable **Auto-follow while zoomed** in settings. (On high-DPI/Retina displays tracking is fixed in 2.2.0.) |
| Flickering at edges | Increase **Crop Edge Threshold** or **Mouse Deadzone** in Advanced Settings. |
| Follow feels laggy | Lower **Update Interval** (e.g. 8 ms) and/or lower **Mouse Deadzone**. |
| Mouse escapes viewport at high zoom | Normal at extreme zoom levels (tiny viewport). Lower Update Interval helps. |
| Source appears to resize | Press **Ctrl+F** to fit source to screen before activating zoom. |
| No valid video source | Ensure the active scene contains a video source. Captures inside **nested scenes and groups** are supported; if several captures exist, set a **Preferred Source**. |
| Wrong source gets zoomed | Set **Preferred Source** to the exact source name you want. |

> **Still stuck?** Enable **Debug Mode**, reproduce the issue, then check **Tools > Scripts > Script Logs**.

---

## Supported Sources

Since **v2.2.0** the script detects sources by **capability** — *any* source that produces video can be zoomed, regardless of its internal type ID. It also drills into **nested scenes and groups** to find the original capture. The table below lists common, tested capture types per platform; it is not exhaustive.

| Platform | Common capture types |
|---|---|
| **Windows** | Display Capture, Window Capture, Game Capture |
| **macOS** | Display Capture, macOS Screen Capture (ScreenCaptureKit) |
| **Linux** | Screen/Window Capture (PipeWire / Wayland), XSHM, Xcomposite |
| **Any** | Browser, Media/VLC, Image, and other video sources |

> If a scene contains several video sources (e.g. a webcam overlay plus a screen capture), the script prefers a known *capture* source. Use **Preferred Source** to override the choice.

---

## Testing Help Needed

We need volunteers to test on **Linux** and **macOS**. If you can help:

- Test with different OBS versions
- Report platform-specific bugs
- Share your OS, OBS version, and script logs

Open an issue or contact the author — any feedback is appreciated.

---

## Requirements

- **OBS Studio** 30.0.0 or higher
- **Lua** 5.1 or higher (bundled with OBS)

---

## Support

Found a bug or have a feature idea? [Open an issue](https://github.com/mredodos/zoom-and-follow-and-more-eg/issues) with:
- Steps to reproduce
- OBS version and OS
- Script logs (Debug Mode enabled)

---

## License

[GNU General Public License v3.0](LICENSE)

## Author

**Edoardo Guzzi** — [@mredodos](https://github.com/mredodos)

<div align="center">

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-orange?style=flat-square&logo=buy-me-a-coffee)](https://www.buymeacoffee.com/mredodos)
[![Sponsor](https://img.shields.io/badge/GitHub-Sponsor-pink?style=flat-square&logo=github-sponsors)](https://github.com/sponsors/mredodos)

*Inspired by the OBS community's zoom and follow scripts, with multi-monitor support and smooth animations built from the ground up.*

</div>
