# TODO: Advanced Source Transformation Mapping

## Current Problem

When a source in OBS is not fitted to the screen (CTRL+F not applied), the zoom and mouse follow behavior can be inaccurate or cause unexpected source resizing.

### Technical Description

The problem stems from a limitation in the current mouse-to-crop mapping approach:

1. **The crop filter works on native source dimensions** (e.g., 2560x1440)
2. **The mouse moves in screen space** (e.g., 1920x1080)
3. **If the source is not fitted**, the displayed dimensions in the scene differ from native dimensions
4. **The mouse → crop mapping becomes complex** because we need to consider:
   - Scene item scale (`obs_sceneitem_get_scale()`)
   - Scene item crop (`obs_sceneitem_get_crop()`)
   - Scene item position in the scene (`obs_sceneitem_get_pos()`)
   - Scene item bounds (`obs_sceneitem_get_bounds()`)
   - How the source is displayed relative to the OBS screen/canvas

### Current Behavior

- **With CTRL+F (source fitted)**: Works perfectly because `displayed_width ≈ screen_width`
- **Without CTRL+F (source not fitted)**: 
  - The script shows a warning
  - Zoom works but with reduced accuracy
  - Mapping can be inaccurate when the source is manually scaled/cropped

## Proposed Solution (Option 3)

Implement an advanced mapping logic that considers all scene item transformations and correctly calculates mouse-to-source mapping even when the source is not fitted to the screen.

### Technical Approach

#### 1. Get all scene item transformations

```lua
-- Get scene item transformations
local scale = obs.obs_sceneitem_get_scale(scene_item)  -- {x, y}
local crop = obs.obs_sceneitem_get_crop(scene_item)     -- {left, top, right, bottom}
local pos = obs.obs_sceneitem_get_pos(scene_item)       -- {x, y}
local bounds = obs.obs_sceneitem_get_bounds(scene_item) -- {type, alignment, x, y}
local rotation = obs.obs_sceneitem_get_rot(scene_item)  -- rotation in degrees
local alignment = obs.obs_sceneitem_get_alignment(scene_item) -- alignment flags
```

#### 2. Calculate effective displayed dimensions

```lua
-- Calculate effective displayed dimensions
local displayed_width = (source_width - crop.left - crop.right) * scale.x
local displayed_height = (source_height - crop.top - crop.bottom) * scale.y
```

#### 3. Get canvas/scene dimensions

```lua
-- Get canvas dimensions (scene output size)
local canvas_width = obs.obs_video_info().base_width
local canvas_height = obs.obs_video_info().base_height
```

#### 4. Calculate scene item position and dimensions in canvas

```lua
-- Calculate scene item position and size in canvas space
-- This requires understanding:
-- - How OBS positions scene items (pos, bounds, alignment)
-- - How the scene item is displayed relative to the canvas
-- - Whether the scene item is cropped/scaled within the canvas
```

#### 5. Map mouse coordinates from canvas to source

```lua
-- Map mouse coordinates from canvas space to source native space
-- This is the critical step that needs to account for:
-- 1. Mouse position relative to canvas
-- 2. Scene item position in canvas
-- 3. Scene item scale and crop
-- 4. Scene item rotation (if applicable)
-- 5. Canvas-to-source coordinate transformation
```

### Proposed Algorithm

```
1. Get mouse position in screen coordinates (already done)
2. Convert screen coordinates to canvas coordinates
   - Consider monitor layout and OBS canvas position
3. Check if mouse is within the scene item's displayed area in canvas
4. If yes, calculate relative position within scene item (0.0 to 1.0)
5. Map relative position to source native coordinates:
   - account for scene item crop
   - account for scene item scale
   - account for scene item position/alignment
6. Use mapped coordinates for crop calculation
```

### Functions to Implement

1. **`get_canvas_dimensions()`**
   - Gets OBS canvas dimensions
   - Returns `{width, height}`

2. **`get_scene_item_canvas_bounds(scene_item)`**
   - Calculates scene item bounds in canvas space
   - Considers pos, scale, crop, bounds, alignment
   - Returns `{x, y, width, height}` in canvas coordinates

3. **`map_mouse_to_canvas(mouse_x, mouse_y, monitor)`**
   - Maps mouse coordinates from screen to OBS canvas
   - Considers canvas position relative to monitor
   - Returns `{x, y}` in canvas coordinates

4. **`map_canvas_to_source(canvas_x, canvas_y, scene_item, source_width, source_height)`**
   - Maps coordinates from canvas to source native coordinates
   - Considers all scene item transformations
   - Returns `{x, y}` in source native coordinates

5. **`get_target_crop_advanced(mouse_x, mouse_y, current_zoom)`**
   - Advanced version of `get_target_crop()` using the new mapping system
   - Replaces current logic with the new algorithm

### Important Considerations

#### OBS API Limitations

- OBS Lua API might not directly expose canvas information
- May need to calculate canvas position based on monitor information
- Scene item rotation further complicates the mapping

#### Performance

- Advanced calculation might be more performance-intensive
- Consider caching values that change rarely (canvas dimensions, scene item bounds)
- Evaluate if the calculation can be optimized

#### Edge Cases

- Scene item partially outside canvas
- Scene item with different bounds type (stretch, scale, crop)
- Rotated scene item
- Multi-monitor with canvas on secondary monitor
- Scene item in nested scenes

### Testing

When implemented, test:

1. **Fitted source (CTRL+F)**: Must work as before (backward compatibility)
2. **Non-fitted source, manually scaled**: Zoom must correctly follow mouse
3. **Non-fitted source, manually cropped**: Crop must be calculated correctly
4. **Non-fitted source, scaled AND cropped**: Combination of both
5. **Rotated source**: If supported, must work correctly
6. **Multi-monitor**: Must work on all monitors
7. **Nested scenes**: Must correctly handle scenes within other scenes

### Documentation to Consult

- OBS Studio Lua API Documentation
- `obs_sceneitem_get_*` functions
- `obs_video_info()` structure
- Scene item transformation matrix (if available)
- Canvas coordinate system in OBS

### Priority

**Low** - The current solution (Option 1 + 2) is sufficient for most users. This implementation is for advanced users who want to use zoom without having to fit the source to the screen.

### Notes

- This is an advanced feature requiring deep understanding of OBS coordinate system
- May require extensive testing on different configurations
- Consider making it optional (setting "Advanced Mapping Mode") to not impact users who use CTRL+F

