# Zoom and Follow Mouse EG

> **Note**: This is a third-party script for OBS Studio. It is not developed, maintained, or endorsed by the OBS Project. This script is provided as-is by the community.

## Description

This third-party script for OBS Studio creates a dynamic zoom effect and follows the mouse movement on a selected video source. It is particularly useful for highlighting specific parts of the screen during recordings or live streaming, with support for multi-monitor setups.

**Version 2.0.0 (Refactored 2025)** - Completely rewritten with modern best practices, improved performance, and extensive configurability.

## Features

- Dynamic zoom on any valid video source
- Smooth mouse-follow movement with anti-flickering technology
- Cross-platform support (Windows, Linux, macOS)
- Multi-monitor support
- Customizable zoom and tracking speeds
- Activation via hotkeys
- Automatic scene switching management
- Smooth transitions during scene changes
- **NEW**: Fully configurable advanced parameters
- **NEW**: Optimized performance with FFI caching
- **NEW**: Enhanced error handling and validation
- **NEW**: Anti-flickering system for edges and stationary mouse
- **NEW**: Comprehensive debug logging system

## Requirements

- OBS Studio (version 30.0.0 or higher)
- Lua 5.1 or higher

## Installation

1. Download the `zoom-follow-mouse-and-more-eg.lua` file (or the latest version from the repository)
2. In OBS Studio, go to Tools > Scripts
3. Click the "+" button and select the downloaded file
4. Configure the script settings according to your preferences

> **Tip**: For visual demonstrations of this script's functionality, check the repository for screenshots or video examples showing the zoom and follow effects in action.

## Configuration

### Main Settings

The script offers several main configuration options:

- **Zoom Value**: Sets the maximum zoom level (from 1.1 to 5.0)
  - Default: 2.0
  - Higher values create more pronounced zoom effect
- **Zoom Speed**: Adjusts the speed of the zoom animation (from 0.01 to 1.0)
  - Default: 0.1
  - Lower values = slower, smoother zoom
  - Higher values = faster, more immediate zoom
- **Follow Speed**: Adjusts the speed of the mouse tracking effect (from 0.01 to 1.0)

  - Default: 0.1
  - Lower values = smoother, more gradual following
  - Higher values = faster, more responsive following

- **Enable Debug Mode**: Toggles detailed logging for troubleshooting
  - Default: false
  - Enable to see detailed information about script operations

### Advanced Settings

The script includes an "Advanced Settings" group with fine-tuning options:

#### Performance Settings

- **Update Interval (ms)**: How often the script updates (8-100ms)

  - Default: 16ms (approximately 60 FPS)
  - Lower values = smoother but more CPU intensive
  - Higher values = less CPU usage but potentially less smooth
  - Recommended: 16ms for 60fps, 8ms for 120fps

- **Mouse Cache Duration (ms)**: How long to cache mouse position (4-32ms)
  - Default: 8ms
  - Reduces FFI calls for better performance
  - Lower values = more accurate but more CPU usage
  - Higher values = less CPU usage but slightly less responsive

#### Anti-Flickering Settings

- **Mouse Deadzone (pixels)**: Minimum mouse movement to trigger crop update (1-10 pixels)

  - Default: 3 pixels
  - Prevents flickering when mouse is stationary
  - Higher values = more stable but less responsive to small movements
  - Lower values = more responsive but may cause flickering

- **Crop Update Threshold (pixels)**: Minimum crop change to trigger update (1-10 pixels)

  - Default: 2 pixels
  - Prevents micro-updates that cause flickering
  - Higher values = more stable but less precise
  - Lower values = more precise but may cause flickering

- **Crop Edge Threshold (pixels)**: Increased threshold when crop is at edges (1-20 pixels)
  - Default: 5 pixels
  - Prevents flickering when mouse is at screen edges/corners
  - Higher values = more stable at edges but less responsive
  - Lower values = more responsive but may flicker at edges

#### Animation Settings

- **Zoom In Duration (ms)**: Duration of zoom-in animation (100-1000ms)

  - Default: 300ms
  - Controls how long it takes to reach full zoom
  - Lower values = faster zoom
  - Higher values = slower, more gradual zoom

- **Zoom Out Duration (ms)**: Duration of zoom-out animation (100-1000ms)

  - Default: 500ms
  - Controls how long it takes to return to normal view
  - Lower values = faster zoom out
  - Higher values = slower, more gradual zoom out

- **Scene Transition Duration (ms)**: Duration of transition when changing scenes (100-1000ms)
  - Default: 300ms
  - Controls smoothness of crop transitions during scene changes
  - Lower values = faster transitions
  - Higher values = slower, smoother transitions

#### Fallback Settings

- **Default Monitor Width**: Fallback width if monitor detection fails (640-7680 pixels)

  - Default: 1920 pixels
  - Used when script cannot detect monitor dimensions
  - Set to your primary monitor width

- **Default Monitor Height**: Fallback height if monitor detection fails (480-4320 pixels)
  - Default: 1080 pixels
  - Used when script cannot detect monitor dimensions
  - Set to your primary monitor height

## Usage

1. Configure the script in OBS Studio settings
2. Set hotkeys to enable/disable zoom and tracking
3. **IMPORTANT**: Before activating zoom, ensure your source is fitted to the screen:
   - Select your source in OBS
   - Press **CTRL+F** (or right-click → "Adatta allo schermo" / "Fit to Screen")
   - This ensures optimal zoom behavior and accurate mouse tracking
4. During recording or live streaming, use the hotkeys to control the zoom and tracking effects

### Source Setup Requirements

**For best results, fit your source to screen before activating zoom:**

- **Recommended**: Press **CTRL+F** on your source before activating zoom
- The script will automatically detect if the source is fitted and show a warning if it's not
- If the source is not fitted, zoom may still work but with reduced accuracy
- After fitting (CTRL+F), you can still crop or resize the source - zoom will continue to work correctly

## Main Functions

- Dynamic zoom on the selected source with smooth animation
- Mouse movement tracking with customizable smoothing
- Automatic scene switching management and source removal
- Multi-monitor configuration support
- Smooth transitions during scene changes while in zoom mode
- Debug mode for easier troubleshooting

## Troubleshooting

If you encounter issues with the script, try:

1. **Enable Debug Mode**: Turn on "Enable Debug Mode" in script settings to see detailed logs
2. **Check Source Dimensions**: Ensure your video source has valid dimensions (not 0x0)
3. **Valid Video Source**: Make sure there is a valid video source in the current scene (monitor capture, window capture, etc.)
4. **Restart OBS Studio**: Sometimes a restart resolves initialization issues
5. **Check OBS Logs**: View Script Logs in OBS (Tools > Scripts > Log degli script) for error messages
6. **OBS Version**: Ensure you're using OBS Studio version 30.0.0 or higher
7. **Hotkey Conflicts**: Make sure your hotkeys don't conflict with other OBS shortcuts
8. **Performance Issues**:
   - Increase "Update Interval" if CPU usage is high
   - Increase "Mouse Deadzone" if experiencing flickering
   - Increase "Crop Update Threshold" if crop updates are too frequent

### Common Issues

**Flickering at screen edges:**

- Increase "Crop Edge Threshold" in Advanced Settings
- Increase "Mouse Deadzone" if mouse is stationary

**Zoom not activating:**

- Check that source has valid dimensions (not 0x0)
- Verify source is a valid video source type
- Check Script Logs for error messages

**Follow not working smoothly:**

- Adjust "Follow Speed" (lower = smoother)
- Increase "Mouse Deadzone" if too sensitive
- Check "Update Interval" is appropriate for your system

**Zoom behavior is incorrect or source appears to resize:**

- **Solution**: Press **CTRL+F** on your source before activating zoom
- This fits the source to the screen and ensures accurate mouse-to-crop mapping
- The script will show a warning in the logs if the source is not fitted
- After fitting, you can still crop or resize the source - zoom will work correctly

## Support

### Reporting Issues

If you encounter bugs or have feature requests, please:

1. **Check existing issues**: Search the GitHub repository to see if your issue has already been reported
2. **Create a new issue**: Open a new issue on GitHub with:
   - A clear description of the problem or feature request
   - Steps to reproduce the issue (if applicable)
   - OBS Studio version and operating system
   - Script logs (enable Debug Mode and include relevant log entries)
   - Screenshots or videos if the issue is visual
3. **Alternative contact**: You can also contact the script's author directly

### Getting Help

- Check the [Troubleshooting](#troubleshooting) section below for common issues
- Enable Debug Mode in script settings for detailed logging
- Review OBS Studio Script Logs (Tools > Scripts > Script Logs) for error messages

## License

This script is released under the GNU General Public License v3.0. See the LICENSE file for more details.

## Version History

### Version 2.0.0 (2025) - Major Refactoring

- **Complete code refactoring** with modern best practices
- **Performance optimizations**: FFI initialization caching, mouse position caching
- **Anti-flickering system**: Deadzone and threshold system to prevent flickering
- **Fully configurable parameters**: All thresholds, durations, and settings are now configurable
- **Enhanced error handling**: Robust validation and error recovery
- **Improved code organization**: Modular structure with reusable functions
- **Better resource management**: Proper cleanup and timer management
- **Comprehensive debug logging**: Detailed logs for troubleshooting
- **Edge case handling**: Special logic for screen edges and corners
- **OBS API compliance**: Following OBS Studio 32.0.0+ best practices

### Version 1.1

- Initial release with basic zoom and follow functionality

## Author

Edoardo Guzzi

## Acknowledgments

A special thanks to the OBS Studio community for their support and feedback. This script is developed independently and is not affiliated with the OBS Project.

## Inspiration

This script is inspired by various zoom and follow scripts in the OBS community, with additional features and improvements for multi-monitor support and smooth transitions.

---

**Disclaimer**: This script is a community-contributed resource. The OBS Project is not responsible for the functionality, support, or maintenance of this script.
