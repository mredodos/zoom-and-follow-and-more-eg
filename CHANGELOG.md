# Changelog

All notable changes to this project will be documented in this file.

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
