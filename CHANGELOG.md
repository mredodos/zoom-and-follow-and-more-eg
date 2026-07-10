# Changelog

All notable changes to this project will be documented in this file.

## [2.2.1] - 2026

### Fixed — Linux mouse tracking (it had never actually worked)

- **`DefaultRootWindow` is an Xlib *macro*, not a symbol exported by `libX11`.** The FFI declared and called it, so LuaJIT failed to resolve the symbol, the whole Linux platform init aborted, and `get_mouse_pos()` returned a hardcoded `(0,0)` from then on. The visible result: zoom always jumped to the **top-left corner** and follow never moved. Now calls the real `XDefaultRootWindow`. This affected **every** Linux session — Xorg included, not just Wayland.
- **`XRRMonitorInfo` had the wrong struct layout** (it omitted `name`, `primary`, `automatic`, `noutput` before the geometry fields), which would have produced garbage monitor rectangles the moment the above was fixed. Corrected to the real `Xrandr.h` layout.
- **More robust library loading**: also tries `libX11.so.6` / `libXrandr.so.2`, since most distros ship only the versioned SONAME. `libXrandr` is now **optional** — if it is missing, monitor geometry falls back to the default X screen size instead of disabling mouse tracking entirely.

### Added — honest Wayland handling

- **Wayland is now detected reliably.** Environment variables (`XDG_SESSION_TYPE` / `WAYLAND_DISPLAY`) are only a hint — they can be missing inside a Flatpak sandbox — so the script also probes the X server at runtime for the **`XWAYLAND` extension** (via `XQueryExtension`, the officially recommended check), which a rootless XWayland server advertises and a classic Xorg server does not. Since that extension only exists from `xorgproto 2022.2`, the environment hint is consulted first and the probe is used to *confirm* a session the env vars failed to reveal.
- Monitor geometry needs `XRRGetMonitors` (libXrandr ≥ 1.5.0); on older systems the script now falls back to the default X screen size instead of failing.
- Wayland deliberately provides **no protocol for an application to read the global cursor position**, so on Wayland the script now **zooms to the centre of the source and disables follow**, stating so clearly in the Script Log and in the script properties — instead of silently zooming into a corner. For mouse-centred zoom and follow, use an Xorg session (e.g. *GNOME on Xorg*).

### Fixed — diagnostics

- **Platform init errors are no longer swallowed.** `debug_mode` is now read at the very start of `script_load`, before platform init, and fatal init failures print unconditionally. Previously these lines were emitted before `debug_mode` was applied, so they never appeared in bug reports — which is why this Linux bug went unnoticed for so long.

### Notes

- Global hotkeys firing **only when the OBS window has focus** is an **OBS core limitation on Wayland** (OBS does not use the XDG GlobalShortcuts portal), not a script issue. See the README for workarounds.

## [2.2.0] - 2026

### Robust source detection (fixes #9, #10, #14)

- **Capability-based detection**: the script now accepts **any source that produces video** (checked via `obs_source_get_output_flags` / `OBS_SOURCE_VIDEO`) instead of matching a hard-coded list of source-type IDs. This fixes "No valid video source found" across platforms and OBS versions — macOS Display/Screen Capture, Linux PipeWire (Wayland) including the current `pipewire-screen-capture-source` ID, XSHM, Xcomposite, and any future capture type. The old ID list is kept only as a ranking hint and as a fallback for very old OBS builds.

### Nested scenes & groups (fixes the nested-scene reports / forum request)

- **Group traversal**: detection now descends into OBS **groups** as well as nested scenes, drilling down to the original capture source in the lowest layer. Previously a capture inside a group was invisible and produced "No valid video source found".
- **Preferred Source (optional)**: a new setting lets you pin which source to zoom by name — useful when a scene contains several captures or deeply nested layers.

### Mouse tracking (fixes #8 "Not tracking")

- **HiDPI / Retina fix**: mouse-to-source mapping is now normalized to the monitor the cursor is on, then scaled to the source's pixel size. On high-DPI displays (e.g. macOS Retina 2×, Windows display scaling) the viewport now follows the cursor correctly instead of being confined to a corner. On native (non-scaled) setups the math is unchanged.
- **Auto-follow while zoomed (opt-in, default OFF)**: a new option makes the viewport track the mouse as soon as you zoom in, without a separate hotkey. The Follow hotkey still works as a live freeze/unfreeze toggle. Default OFF, so existing setups behave exactly as before.

### Reliability

- **Safer source dimensions**: when the rendered source size is momentarily unavailable (`0`, e.g. right after the crop filter is added) the script falls back to the source's native resolution instead of failing to zoom.

### Notes

- **Installation (#19)**: if OBS reports `unexpected symbol near '<'`, the `.lua` was saved as the GitHub HTML page. Download from **Releases** or the **Raw** link — see the README.

## [2.1.0] - 2025

### Rewritten zoom and follow engine

- **State-machine animation**: Single named timer with `idle` / `zooming_in` / `zoomed_in` / `zooming_out` states, fixing all timer-leak and double-fire bugs.
- **Fixed-endpoint lerp**: Zoom-in/out smoothly interpolates between pre-calculated start and end crops — no per-frame recalculation, no flickering.
- **First-click reliability**: Source dimensions are captured before the crop filter is applied, so the very first hotkey press always works.
- **Center-point follow**: Follow mode only moves the viewport center, keeping viewport size locked to the current zoom level. Eliminates zoom drift and flicker during tracking.
- **Simplified settings**: Removed the redundant "Zoom Speed" slider. Zoom animation timing is now controlled directly via **Zoom In Duration** and **Zoom Out Duration** (ms), moved from Advanced Settings to the main panel.
- **Expanded limits**: Zoom Value up to 100, durations up to 60 000 ms — no arbitrary caps.

## [2.0.2] - 2025

### Fix #7 — Zoom max and quality

- Maximum zoom increased from 5 to 10 (single constant `MAX_ZOOM_VALUE`).
- README note on Fit to screen (Ctrl+F) and high-resolution sources for best quality at high zoom levels.

## [2.0.1] - 2025

### Fix #9, #10, #14, #8 (partial) — macOS and Linux source types

- Added macOS and Linux source types so zoom and follow work with Display Capture, Screen Capture, PipeWire, XSHM, and Xcomposite without "No valid video source found" errors.

## [2.0.0] - 2025

### Major Refactoring

- Complete code refactoring with modern best practices.
- Performance optimizations: FFI initialization caching, mouse position caching.
- Anti-flickering system: deadzone and threshold system to prevent flickering.
- Fully configurable parameters: all thresholds, durations, and settings are now configurable.
- Enhanced error handling: robust validation and error recovery.
- Improved code organization: modular structure with reusable functions.
- Better resource management: proper cleanup and timer management.
- Comprehensive debug logging: detailed logs for troubleshooting.
- Edge case handling: special logic for screen edges and corners.
- OBS API compliance: following OBS Studio 32.0.0+ best practices.

## [1.1.0]

- Initial release with basic zoom and follow functionality.
