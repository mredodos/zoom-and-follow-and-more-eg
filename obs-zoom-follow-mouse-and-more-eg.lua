-- ============================================================================
-- Zoom, Follow Mouse and MORE for OBS Studio
-- Version 2.0.0 (Refactored 2025)
-- ============================================================================

local obs = obslua
local ffi = require("ffi")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local ZOOM_HOTKEY_NAME = "zoom_and_follow.zoom.toggle"
local FOLLOW_HOTKEY_NAME = "zoom_and_follow.follow.toggle"
local CROP_FILTER_NAME = "zoom_and_follow_crop"
local MAX_DISPLAYS = 32 -- Maximum displays for macOS

-- Default values (will be overridden by script settings)
local DEFAULT_UPDATE_INTERVAL = 16 -- milliseconds (approximately 60 FPS)
local DEFAULT_MOUSE_CACHE_DURATION = 8 -- milliseconds (max 120 FPS)
local DEFAULT_ZOOM_ANIMATION_DURATION = 300 -- milliseconds
local DEFAULT_ZOOM_OUT_DURATION = 500 -- milliseconds
local DEFAULT_SCENE_TRANSITION_DURATION = 300 -- milliseconds
local DEFAULT_MOUSE_DEADZONE = 3 -- pixels: minimum mouse movement to trigger crop update
local DEFAULT_CROP_UPDATE_THRESHOLD = 2 -- pixels: minimum crop change to trigger update
local DEFAULT_CROP_EDGE_THRESHOLD = 5 -- pixels: increased threshold when crop is at edges
local DEFAULT_MONITOR_WIDTH = 1920
local DEFAULT_MONITOR_HEIGHT = 1080

-- Valid video source types
local VALID_SOURCE_TYPES = {
    "ffmpeg_source",
    "browser_source",
    "vlc_source",
    "monitor_capture",
    "window_capture",
    "game_capture",
    "dshow_input",
    "av_capture_input"
}

-- ============================================================================
-- FFI PLATFORM MODULE
-- ============================================================================

local ffi_platform = {
    initialized = false,
    os_type = nil,
    -- Windows
    windows_loaded = false,
    -- Linux
    x11 = nil,
    xrandr = nil,
    x11_display = nil,
    x11_root = nil,
    -- macOS
    core_graphics = nil,
    -- Monitors cache
    monitors = {},
    -- Mouse position cache
    mouse_cache = {x = 0, y = 0, timestamp = 0}
}

-- Initialize FFI definitions for Windows
local function init_windows_ffi()
    if ffi_platform.windows_loaded then
        return true
    end
    
    local success, err = pcall(function()
        ffi.cdef[[
            typedef long BOOL;
            typedef void* HANDLE;
            typedef HANDLE HMONITOR;
            typedef struct {
                long left;
                long top;
                long right;
                long bottom;
            } RECT;
            typedef struct {
                unsigned long cbSize;
                RECT rcMonitor;
                RECT rcWork;
                unsigned long dwFlags;
            } MONITORINFO;
            typedef BOOL (*MONITORENUMPROC)(HMONITOR, void*, RECT*, long);
            
            BOOL EnumDisplayMonitors(void*, void*, MONITORENUMPROC, long);
            BOOL GetMonitorInfoA(HMONITOR, MONITORINFO*);
            typedef struct { long x; long y; } POINT;
            bool GetCursorPos(POINT* point);
        ]]
        ffi_platform.windows_loaded = true
    end)
    
    if not success then
        return false, err
    end
    return true
end

-- Initialize FFI definitions and handles for Linux
local function init_linux_ffi()
    if ffi_platform.x11_display ~= nil then
        return true
    end
    
    local success, err = pcall(function()
        ffi.cdef[[
            typedef struct {
                int x, y;
                int width, height;
            } XRRMonitorInfo;
            
            typedef void* Display;
            typedef unsigned long Window;
            
            Display* XOpenDisplay(const char*);
            void XCloseDisplay(Display*);
            Window DefaultRootWindow(Display*);
            XRRMonitorInfo* XRRGetMonitors(Display*, Window, int, int*);
            void XRRFreeMonitors(XRRMonitorInfo*);
            
            typedef struct {
                int x, y;
                int dummy1, dummy2, dummy3;
                int dummy4, dummy5, dummy6;
            } XButtonEvent;
            
            int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
        ]]
        
        ffi_platform.x11 = ffi.load("X11")
        ffi_platform.xrandr = ffi.load("Xrandr")
        
        ffi_platform.x11_display = ffi_platform.x11.XOpenDisplay(nil)
        if ffi_platform.x11_display ~= nil then
            ffi_platform.x11_root = ffi_platform.x11.DefaultRootWindow(ffi_platform.x11_display)
        end
    end)
    
    if not success then
        return false, err
    end
    
    if ffi_platform.x11_display == nil then
        return false, "Failed to open X11 display"
    end
    
    return true
end

-- Initialize FFI definitions and handles for macOS
local function init_macos_ffi()
    if ffi_platform.core_graphics ~= nil then
        return true
    end
    
    local success, err = pcall(function()
        ffi.cdef[[
            typedef struct CGDirectDisplayID *CGDirectDisplayID;
            typedef uint32_t CGDisplayCount;
            typedef struct CGRect CGRect;
            typedef struct CGPoint CGPoint;
            
            int CGGetActiveDisplayList(CGDisplayCount maxDisplays, CGDirectDisplayID *activeDisplays, CGDisplayCount *displayCount);
            CGRect CGDisplayBounds(CGDirectDisplayID display);
            CGPoint CGEventGetLocation(void* event);
            void* CGEventCreate(void* source);
            void CFRelease(void* cf);
        ]]
        
        ffi_platform.core_graphics = ffi.load("CoreGraphics", true)
    end)
    
    if not success then
        return false, err
    end
    
    return true
end

-- Initialize FFI platform module
function ffi_platform.init()
    if ffi_platform.initialized then
        return true
    end
    
    ffi_platform.os_type = ffi.os
    local success, err
    
    if ffi_platform.os_type == "Windows" then
        success, err = init_windows_ffi()
    elseif ffi_platform.os_type == "Linux" then
        success, err = init_linux_ffi()
    elseif ffi_platform.os_type == "OSX" then
        success, err = init_macos_ffi()
    else
        -- Fallback for unknown OS
        ffi_platform.monitors = {{left = 0, top = 0, right = app_state.default_monitor_width, bottom = app_state.default_monitor_height}}
        ffi_platform.initialized = true
        return true
    end
    
    if not success then
        return false, err
    end
    
    ffi_platform.initialized = true
    return true
end

-- Get monitors information
function ffi_platform.get_monitors()
    if not ffi_platform.initialized then
        return {}
    end
    
    if #ffi_platform.monitors > 0 then
        return ffi_platform.monitors
    end
    
    local monitors = {}
    
    if ffi_platform.os_type == "Windows" then
        local function enum_callback(hMonitor, _, _, _)
            local mi = ffi.new("MONITORINFO")
            mi.cbSize = ffi.sizeof("MONITORINFO")
            if ffi.C.GetMonitorInfoA(hMonitor, mi) ~= 0 then
                table.insert(monitors, {
                    left = mi.rcMonitor.left,
                    top = mi.rcMonitor.top,
                    right = mi.rcMonitor.right,
                    bottom = mi.rcMonitor.bottom
                })
            end
            return true
        end
        
        local callback = ffi.cast("MONITORENUMPROC", enum_callback)
        ffi.C.EnumDisplayMonitors(nil, nil, callback, 0)
        callback:free()
        
    elseif ffi_platform.os_type == "Linux" then
        if ffi_platform.x11_display ~= nil then
            local count = ffi.new("int[1]")
            local info = ffi_platform.xrandr.XRRGetMonitors(ffi_platform.x11_display, ffi_platform.x11_root, 1, count)
            
            if info ~= nil then
                for i = 0, count[0] - 1 do
                    table.insert(monitors, {
                        left = info[i].x,
                        top = info[i].y,
                        right = info[i].x + info[i].width,
                        bottom = info[i].y + info[i].height
                    })
                end
                ffi_platform.xrandr.XRRFreeMonitors(info)
            end
        end
        
    elseif ffi_platform.os_type == "OSX" then
        if ffi_platform.core_graphics ~= nil then
            local active_displays = ffi.new("CGDirectDisplayID[?]", MAX_DISPLAYS)
            local display_count = ffi.new("CGDisplayCount[1]")
            
            if ffi_platform.core_graphics.CGGetActiveDisplayList(MAX_DISPLAYS, active_displays, display_count) == 0 then
                for i = 0, display_count[0] - 1 do
                    local bounds = ffi_platform.core_graphics.CGDisplayBounds(active_displays[i])
                    table.insert(monitors, {
                        left = bounds.origin.x,
                        top = bounds.origin.y,
                        right = bounds.origin.x + bounds.size.width,
                        bottom = bounds.origin.y + bounds.size.height
                    })
                end
            end
        end
    else
        -- Fallback for unknown OS
        monitors = {{left = 0, top = 0, right = app_state.default_monitor_width, bottom = app_state.default_monitor_height}}
    end
    
    ffi_platform.monitors = monitors
    return monitors
end

-- Get mouse position with caching
function ffi_platform.get_mouse_pos()
    if not ffi_platform.initialized then
        return 0, 0
    end
    
    -- Check cache validity
    local current_time = obs.os_gettime_ns() / 1000000 -- Convert to milliseconds
    local cache_duration = app_state and app_state.mouse_cache_duration or DEFAULT_MOUSE_CACHE_DURATION
    if current_time - ffi_platform.mouse_cache.timestamp < cache_duration then
        return ffi_platform.mouse_cache.x, ffi_platform.mouse_cache.y
    end
    
    local x, y = 0, 0
    local success = false
    
    if ffi_platform.os_type == "Windows" then
        local success_pcall, x_result, y_result = pcall(function()
            local point = ffi.new("POINT[1]")
            if ffi.C.GetCursorPos(point) then
                return point[0].x, point[0].y
            end
            return 0, 0
        end)
        if success_pcall then
            x, y = x_result, y_result
            success = true
        end
        
    elseif ffi_platform.os_type == "Linux" then
        if ffi_platform.x11_display ~= nil then
            local success_pcall, x_result, y_result = pcall(function()
                local root_x = ffi.new("int[1]")
                local root_y = ffi.new("int[1]")
                local win_x = ffi.new("int[1]")
                local win_y = ffi.new("int[1]")
                local mask = ffi.new("unsigned int[1]")
                local child = ffi.new("Window[1]")
                local child_revert = ffi.new("Window[1]")
                
                if ffi_platform.x11.XQueryPointer(ffi_platform.x11_display, ffi_platform.x11_root, 
                                                  child_revert, child, root_x, root_y, win_x, win_y, mask) ~= 0 then
                    return root_x[0], root_y[0]
                end
                return 0, 0
            end)
            if success_pcall then
                x, y = x_result, y_result
                success = true
            end
        end
        
    elseif ffi_platform.os_type == "OSX" then
        if ffi_platform.core_graphics ~= nil then
            local success_pcall, x_result, y_result = pcall(function()
                local event = ffi_platform.core_graphics.CGEventCreate(nil)
                if event ~= nil then
                    local point = ffi_platform.core_graphics.CGEventGetLocation(event)
                    ffi_platform.core_graphics.CFRelease(event)
                    return point.x, point.y
                end
                return 0, 0
            end)
            if success_pcall then
                x, y = x_result, y_result
                success = true
            end
        end
    end
    
    -- Update cache
    if success then
        ffi_platform.mouse_cache.x = x
        ffi_platform.mouse_cache.y = y
        ffi_platform.mouse_cache.timestamp = current_time
        -- Removed app_state dependency - ffi_platform should be independent
    end
    
    return x, y
end

-- Cleanup FFI platform resources
function ffi_platform.cleanup()
    if ffi_platform.os_type == "Linux" and ffi_platform.x11_display ~= nil then
        pcall(function()
            ffi_platform.x11.XCloseDisplay(ffi_platform.x11_display)
        end)
        ffi_platform.x11_display = nil
        ffi_platform.x11_root = nil
        ffi_platform.x11 = nil
        ffi_platform.xrandr = nil
    end
    
    ffi_platform.monitors = {}
    ffi_platform.mouse_cache = {x = 0, y = 0, timestamp = 0}
    ffi_platform.initialized = false
end

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local app_state = {
    zoom = {
        active = false,
        value = 3.0,
        speed = 0.2,
        current = 1.0,
        target = 1.0,
        start_time = 0
    },
    follow = {
        active = false,
        speed = 0.2
    },
    source = nil,
    crop_filter = nil,
    crop_filter_owned = false, -- Track if filter was created by us (needs release) or borrowed (no release)
    original_crop = nil,
    current_crop = nil,
    target_crop = nil,
    last_mouse_pos = {x = 0, y = 0}, -- Track last mouse position for deadzone calculation
    last_crop = {left = 0, top = 0, right = 0, bottom = 0}, -- Track last crop values to prevent unnecessary updates
    current_scene = nil,
    current_filter_target = nil,
    animation_timer = nil,
    zoom_out_timer = nil,
    zoom_out_in_progress = false,
    cleanup_in_progress = false, -- Flag to prevent timer creation during cleanup
    monitors = {},
    zoom_hotkey_id = nil,
    follow_hotkey_id = nil,
    debug_mode = false,
    -- Configurable parameters
    update_interval = DEFAULT_UPDATE_INTERVAL,
    mouse_cache_duration = DEFAULT_MOUSE_CACHE_DURATION,
    zoom_animation_duration = DEFAULT_ZOOM_ANIMATION_DURATION,
    zoom_out_duration = DEFAULT_ZOOM_OUT_DURATION,
    scene_transition_duration = DEFAULT_SCENE_TRANSITION_DURATION,
    mouse_deadzone = DEFAULT_MOUSE_DEADZONE,
    crop_update_threshold = DEFAULT_CROP_UPDATE_THRESHOLD,
    crop_edge_threshold = DEFAULT_CROP_EDGE_THRESHOLD,
    default_monitor_width = DEFAULT_MONITOR_WIDTH,
    default_monitor_height = DEFAULT_MONITOR_HEIGHT
}

-- Validate state consistency
local function validate_state()
    if app_state.zoom.active and not app_state.source then
        app_state.zoom.active = false
        app_state.follow.active = false
        return false
    end
    if app_state.follow.active and not app_state.zoom.active then
        app_state.follow.active = false
        return false
    end
    return true
end

-- Reset state to default
local function reset_state()
    app_state.zoom.active = false
    app_state.zoom.current = 1.0
    app_state.zoom.target = 1.0
    app_state.follow.active = false
    app_state.current_crop = nil
    app_state.target_crop = nil
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Enhanced logging function with levels
local function log(level, message)
    if not app_state.debug_mode and level ~= "error" then
        return
    end
    
    local prefix = "[Zoom and Follow]"
    if level == "error" then
        print(prefix .. " [ERROR] " .. message)
    elseif level == "warning" then
        print(prefix .. " [WARNING] " .. message)
    else
        print(prefix .. " " .. message)
    end
end

-- Check if source type is valid
local function is_valid_source_type(source)
    if not source then
        return false
    end
    
    local source_id = obs.obs_source_get_id(source)
    for _, valid_type in ipairs(VALID_SOURCE_TYPES) do
        if source_id == valid_type then
            return true
        end
    end
    return false
end

-- Find valid video source in current scene (recursive)
local function find_valid_video_source()
    local current_scene = obs.obs_frontend_get_current_scene()
    if not current_scene then
        log("info", "No current scene found")
        return nil
    end
    
    local scene = obs.obs_scene_from_source(current_scene)
    local items = obs.obs_scene_enum_items(scene)
    
    local function check_source(source)
        if not source then
            return nil
        end
        
        if is_valid_source_type(source) then
            return source
        elseif obs.obs_source_get_type(source) == obs.OBS_SOURCE_TYPE_SCENE then
            -- Recursively search in nested scenes
            local nested_scene = obs.obs_scene_from_source(source)
            if nested_scene then
                local nested_items = obs.obs_scene_enum_items(nested_scene)
                for _, nested_item in ipairs(nested_items) do
                    local nested_source = obs.obs_sceneitem_get_source(nested_item)
                    local valid_source = check_source(nested_source)
                    if valid_source then
                        obs.sceneitem_list_release(nested_items)
                        return valid_source
                    end
                end
                obs.sceneitem_list_release(nested_items)
            end
        end
        return nil
    end
    
    local valid_source = nil
    for _, item in ipairs(items) do
        local item_source = obs.obs_sceneitem_get_source(item)
        valid_source = check_source(item_source)
        if valid_source then
            break
        end
    end
    
    obs.sceneitem_list_release(items)
    -- Release scene (protected with pcall)
    pcall(function()
        obs.obs_source_release(current_scene)
    end)
    
    if valid_source then
        -- Note: Sources from scene items are managed by OBS, no need to addref/release
        log("info", "Found valid video source: " .. obs.obs_source_get_name(valid_source))
    else
        log("info", "No valid video source found in the current scene")
    end
    
    return valid_source
end

-- ============================================================================
-- ANIMATION SYSTEM
-- ============================================================================

-- Easing functions
local function ease_linear(t)
    return t
end

local function ease_in_out(t)
    return t * t * (3.0 - 2.0 * t)
end

local function ease_out(t)
    return 1.0 - (1.0 - t) * (1.0 - t)
end

-- Generic animation function
local function animate_value(start_value, target_value, duration, easing_func, callback)
    local start_time = obs.os_gettime_ns() / 1000000 -- Convert to milliseconds
    local easing = easing_func or ease_linear
    
    local function animate()
        local current_time = obs.os_gettime_ns() / 1000000
        local elapsed = current_time - start_time
        local progress = math.min(elapsed / duration, 1.0)
        
        local eased_progress = easing(progress)
        local current_value = start_value + (target_value - start_value) * eased_progress
        
        if callback then
            callback(current_value, progress)
        end
        
        if progress < 1.0 then
            return true -- Continue animation
        else
            return false -- Animation complete
        end
    end
    
    return animate
end

-- ============================================================================
-- CROP & FILTER MANAGEMENT
-- ============================================================================

-- Validate source has valid dimensions
local function validate_source_dimensions(source)
    if not source then
        return false, "Source is nil"
    end
    
    local success, width_result, height_result = pcall(function()
        return obs.obs_source_get_width(source), obs.obs_source_get_height(source)
    end)
    
    if not success then
        return false, "Failed to get source dimensions"
    end
    
    if not width_result or not height_result then
        return false, "Source dimensions are nil"
    end
    
    if width_result == 0 or height_result == 0 then
        return false, string.format("Source has invalid dimensions: %dx%d", width_result, height_result)
    end
    
    return true, width_result, height_result
end

-- Apply crop filter to target source
local function apply_crop_filter(target_source)
    if not target_source then
        log("warning", "Cannot apply crop filter: target source is nil")
        return false
    end
    
    -- Validate source dimensions before applying filter
    local is_valid, width, height = validate_source_dimensions(target_source)
    if not is_valid then
        log("error", "Cannot apply crop filter: " .. tostring(width))
        return false
    end
    
    local parent_source = obs.obs_frontend_get_current_scene()
    if not parent_source then
        log("warning", "Cannot get current scene")
        return
    end
    
    local filter_target = obs.obs_source_get_type(target_source) == obs.OBS_SOURCE_TYPE_SCENE and parent_source or target_source
    
    -- Remove filter from previous source/scene if it exists
    if app_state.current_filter_target and app_state.current_filter_target ~= filter_target then
        local old_filter = obs.obs_source_get_filter_by_name(app_state.current_filter_target, CROP_FILTER_NAME)
        if old_filter then
            -- Note: obs_source_get_filter_by_name returns borrowed reference, no need to release
            pcall(function()
                obs.obs_source_filter_remove(app_state.current_filter_target, old_filter)
            end)
        end
    end
    
    -- Release old filter reference if it was created by us (not a borrowed reference)
    if app_state.crop_filter and app_state.crop_filter_owned then
        -- Only release if we created it (protected with pcall)
        pcall(function()
            obs.obs_source_release(app_state.crop_filter)
        end)
        app_state.crop_filter = nil
        app_state.crop_filter_owned = false
    end
    
    -- Always create a new filter to ensure clean state
    -- Remove any existing filter first
    local existing_filter = obs.obs_source_get_filter_by_name(filter_target, CROP_FILTER_NAME)
    if existing_filter then
        -- Remove existing filter first
        pcall(function()
            obs.obs_source_filter_remove(filter_target, existing_filter)
        end)
        log("info", "Removed existing crop filter before creating new one")
    end
    
    -- Create new filter (must be released when done)
    app_state.crop_filter = obs.obs_source_create("crop_filter", CROP_FILTER_NAME, nil, nil)
    if app_state.crop_filter then
        obs.obs_source_filter_add(filter_target, app_state.crop_filter)
        app_state.crop_filter_owned = true
        log("info", "Crop filter created and applied to " .. obs.obs_source_get_name(filter_target))
    else
        log("error", "Failed to create crop filter")
    end
    
    app_state.current_filter_target = filter_target
    -- Release parent source (protected with pcall)
    pcall(function()
        obs.obs_source_release(parent_source)
    end)
    
    -- Always log filter application details for debugging
    local filter_target_name = obs.obs_source_get_name(filter_target) or "unknown"
    log("info", string.format("Filter applied - Target: %s, size: %dx%d, type: %s", 
        filter_target_name, width, height, 
        obs.obs_source_get_type(filter_target) == obs.OBS_SOURCE_TYPE_SCENE and "SCENE" or "SOURCE"))
    
    -- Note: We don't verify dimensions immediately after filter application because
    -- OBS may need a moment to update the source dimensions. The dimensions will be
    -- validated when get_target_crop() is called, which has retry logic.
    
    return true
end

-- Update crop (keeping original implementation for OBS limitations)
local function update_crop(left, top, right, bottom)
    if not app_state.crop_filter then
        return
    end
    
    -- Validate filter is still valid
    local filter_valid = pcall(function()
        obs.obs_source_get_name(app_state.crop_filter)
    end)
    
    if not filter_valid then
        log("warning", "Crop filter became invalid")
        app_state.crop_filter = nil
        return
    end
    
    local settings = obs.obs_data_create()
    local left_int = math.floor(left + 0.5)
    local top_int = math.floor(top + 0.5)
    local right_int = math.floor(right + 0.5)
    local bottom_int = math.floor(bottom + 0.5)
    
    obs.obs_data_set_int(settings, "left", left_int)
    obs.obs_data_set_int(settings, "top", top_int)
    obs.obs_data_set_int(settings, "right", right_int)
    obs.obs_data_set_int(settings, "bottom", bottom_int)
    
    
    local update_success = pcall(function()
        obs.obs_source_update(app_state.crop_filter, settings)
    end)
    
    if not update_success then
        log("warning", "Failed to update crop filter")
    end
    
    obs.obs_data_release(settings)
end

-- Calculate target crop based on mouse position and zoom
local function get_target_crop(mouse_x, mouse_y, current_zoom)
    -- Debug: Track what target we're using
    local target_source = app_state.current_filter_target
    local fallback_source = app_state.source
    local target = nil
    local target_type = "none"
    
    -- Try to get the filter target, with fallback to source
    if target_source then
        target = target_source
        target_type = "current_filter_target"
    elseif app_state.crop_filter then
        -- If filter_target is not set, try to get it from the filter
        local success, filter_target = pcall(function()
            return obs.obs_filter_get_parent(app_state.crop_filter)
        end)
        if success and filter_target then
            target = filter_target
            target_type = "filter_parent"
            app_state.current_filter_target = filter_target
            if app_state.debug_mode then
                log("info", "Retrieved filter target from filter parent")
            end
        end
    end
    
    -- Fallback to source if still no target
    if not target and fallback_source then
        target = fallback_source
        target_type = "source_fallback"
    end
    
    if not target then
        if app_state.debug_mode then
            log("warning", "get_target_crop: No target available (filter_target: " .. 
                tostring(target_source ~= nil) .. ", source: " .. tostring(fallback_source ~= nil) .. 
                ", filter: " .. tostring(app_state.crop_filter ~= nil) .. ")")
        end
        return {left = 0, top = 0, right = 0, bottom = 0}
    end
    
    -- Get target name for debugging
    local target_name = "unknown"
    pcall(function()
        target_name = obs.obs_source_get_name(target) or "unknown"
    end)
    
    -- Validate target is still valid
    -- According to OBS documentation (obs_source_get_width/height), these functions call
    -- the source's get_width/get_height callbacks, which may return 0 if the source
    -- dimensions are not yet available (e.g., immediately after filter application).
    -- We check once and if dimensions are 0, we return empty crop and let the next
    -- frame (via the animation timer) handle it. This is the correct approach per OBS docs.
    local source_width, source_height
    local success, width_result, height_result = pcall(function()
        return obs.obs_source_get_width(target), obs.obs_source_get_height(target)
    end)
    
    if success and width_result and height_result then
        source_width = width_result
        source_height = height_result
        
        -- If dimensions are valid, proceed with crop calculation
        if source_width > 0 and source_height > 0 then
            -- Dimensions are valid, continue with crop calculation below
        else
            -- Dimensions are 0 - this is expected immediately after filter application
            -- per OBS documentation. The source dimensions will be available on the next frame.
            -- Return empty crop and let the animation timer retry on next frame.
            if app_state.debug_mode and not app_state._dimension_warning_logged then
                log("info", string.format("Source dimensions not yet available (0x0) - will retry on next frame. Target: %s", target_name))
            end
            return {left = 0, top = 0, right = 0, bottom = 0}
        end
    else
        -- Failed to get dimensions - source may be invalid
        if app_state.debug_mode then
            log("warning", string.format("Failed to get source dimensions for target: %s", target_name))
        end
        return {left = 0, top = 0, right = 0, bottom = 0}
    end
    
    -- Reset warning flag if dimensions are now valid
    if source_width > 0 and source_height > 0 then
        if app_state._dimension_warning_logged then
            log("info", string.format("Filter target dimensions now valid: %dx%d (target: %s, type: %s)", 
                source_width, source_height, target_name, target_type))
            app_state._dimension_warning_logged = false
        end
    end
    
    
    -- Find monitor where mouse is located
    local current_monitor = app_state.monitors[1] or {left = 0, top = 0, right = app_state.default_monitor_width, bottom = app_state.default_monitor_height}
    for _, monitor in ipairs(app_state.monitors) do
        if mouse_x >= monitor.left and mouse_x < monitor.right and
           mouse_y >= monitor.top and mouse_y < monitor.bottom then
            current_monitor = monitor
            break
        end
    end
    
    local screen_width = current_monitor.right - current_monitor.left
    local screen_height = current_monitor.bottom - current_monitor.top
    
    if screen_width == 0 or screen_height == 0 then
        return {left = 0, top = 0, right = 0, bottom = 0}
    end
    
    local scale_x = source_width / screen_width
    local scale_y = source_height / screen_height
    
    local target_width = math.floor(source_width / current_zoom)
    local target_height = math.floor(source_height / current_zoom)
    
    local target_x = math.floor((mouse_x - current_monitor.left) * scale_x - (target_width / 2))
    local target_y = math.floor((mouse_y - current_monitor.top) * scale_y - (target_height / 2))
    
    target_x = math.max(0, math.min(target_x, source_width - target_width))
    target_y = math.max(0, math.min(target_y, source_height - target_height))
    
    return {
        left = target_x,
        top = target_y,
        right = source_width - (target_x + target_width),
        bottom = source_height - (target_y + target_height)
    }
end

-- ============================================================================
-- CROP INTERPOLATION AND UPDATE HELPERS
-- ============================================================================

-- Apply follow speed interpolation to crop and handle edge cases
-- Returns the interpolated crop with anti-flickering logic for edges
local function apply_follow_interpolation(new_crop, mouse_distance)
    if not app_state.follow.active then
        return new_crop
    end
    
    app_state.current_crop = app_state.current_crop or {left = 0, top = 0, right = 0, bottom = 0}
    
    -- Calculate interpolated crop with follow speed
    local interpolated_crop = {
        left = app_state.current_crop.left + (new_crop.left - app_state.current_crop.left) * app_state.follow.speed,
        top = app_state.current_crop.top + (new_crop.top - app_state.current_crop.top) * app_state.follow.speed,
        right = app_state.current_crop.right + (new_crop.right - app_state.current_crop.right) * app_state.follow.speed,
        bottom = app_state.current_crop.bottom + (new_crop.bottom - app_state.current_crop.bottom) * app_state.follow.speed
    }
    
    -- Check if we're at the edges (crop values are at 0 or near 0)
    local is_at_left_edge = interpolated_crop.left <= 1
    local is_at_top_edge = interpolated_crop.top <= 1
    local is_at_right_edge = interpolated_crop.right <= 1
    local is_at_bottom_edge = interpolated_crop.bottom <= 1
    local is_at_edge = is_at_left_edge or is_at_top_edge or is_at_right_edge or is_at_bottom_edge
    
    -- If at edge and mouse hasn't moved significantly, use current crop to prevent flickering
    if is_at_edge and mouse_distance < app_state.mouse_deadzone * 2 then
        -- Keep current crop when at edges and mouse is stationary
        return {
            left = app_state.current_crop.left,
            top = app_state.current_crop.top,
            right = app_state.current_crop.right,
            bottom = app_state.current_crop.bottom
        }
    else
        -- Apply interpolated crop
        return interpolated_crop
    end
end

-- Update crop if change exceeds threshold (with edge-aware threshold)
-- Returns true if crop was updated, false otherwise
local function update_crop_if_needed(new_crop, should_update)
    if not should_update then
        return false
    end
    
    local crop_delta_left = math.abs(new_crop.left - app_state.last_crop.left)
    local crop_delta_top = math.abs(new_crop.top - app_state.last_crop.top)
    local crop_delta_right = math.abs(new_crop.right - app_state.last_crop.right)
    local crop_delta_bottom = math.abs(new_crop.bottom - app_state.last_crop.bottom)
    
    local max_crop_delta = math.max(crop_delta_left, crop_delta_top, crop_delta_right, crop_delta_bottom)
    
    -- Use higher threshold when at edges to prevent flickering
    local is_at_edge = (app_state.last_crop.left <= 1 or app_state.last_crop.top <= 1 or 
                       app_state.last_crop.right <= 1 or app_state.last_crop.bottom <= 1)
    local threshold = is_at_edge and app_state.crop_edge_threshold or app_state.crop_update_threshold
    
    if max_crop_delta >= threshold then
        update_crop(new_crop.left, new_crop.top, new_crop.right, new_crop.bottom)
        app_state.last_crop = {
            left = new_crop.left,
            top = new_crop.top,
            right = new_crop.right,
            bottom = new_crop.bottom
        }
        return true
    end
    
    return false
end

-- ============================================================================
-- ANIMATION HANDLERS
-- ============================================================================

-- Main zoom animation handler
local function animate_zoom()
    -- CRITICAL: Check if app_state exists (prevents crash if script is unloaded)
    if not app_state then
        return
    end
    
    -- Validate source before using it
    if not app_state.source then
        if app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
            log("warning", "Animation timer removed - source is nil")
        end
        return
    end
    
    -- Check if source is still valid
    local source_valid = pcall(function()
        obs.obs_source_get_width(app_state.source)
    end)
    
    if not source_valid then
        log("warning", "Source became invalid, stopping animation and deactivating zoom/follow")
        app_state.zoom.active = false
        app_state.follow.active = false
        if app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
            log("info", "Animation timer removed due to invalid source")
        end
        -- Note: Sources from scene items are managed by OBS, no need to release
        app_state.source = nil
        return
    end
    
    if not app_state.zoom.active and not app_state.follow.active then
        if app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
        end
        return
    end
    
    local current_time = obs.os_gettime_ns() / 1000000 -- Convert to milliseconds
    local elapsed_time = current_time - app_state.zoom.start_time
    local progress = math.min(elapsed_time / app_state.zoom_animation_duration, 1.0)
    
    if app_state.zoom.active then
        app_state.zoom.current = 1.0 + (app_state.zoom.target - 1.0) * progress * app_state.zoom.speed
    end
    
    local mouse_x, mouse_y = ffi_platform.get_mouse_pos()
    
    -- Calculate mouse movement distance
    local mouse_delta_x = math.abs(mouse_x - app_state.last_mouse_pos.x)
    local mouse_delta_y = math.abs(mouse_y - app_state.last_mouse_pos.y)
    local mouse_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
    
    -- Only update crop if mouse moved beyond deadzone (prevents flickering when mouse is stationary)
    local should_update = true
    if app_state.follow.active and mouse_distance < app_state.mouse_deadzone then
        should_update = false
        -- Update last_mouse_pos even when skipping update to prevent deadzone accumulation
        app_state.last_mouse_pos = {x = mouse_x, y = mouse_y}
        return -- Exit early to avoid unnecessary calculations
    end
    
    -- Debug: Log state before get_target_crop (only first few times)
    if app_state.debug_mode and (not app_state._crop_calc_count or app_state._crop_calc_count < 3) then
        app_state._crop_calc_count = (app_state._crop_calc_count or 0) + 1
        local ft_name = "nil"
        local s_name = "nil"
        if app_state.current_filter_target then
            pcall(function() ft_name = obs.obs_source_get_name(app_state.current_filter_target) or "unknown" end)
        end
        if app_state.source then
            pcall(function() s_name = obs.obs_source_get_name(app_state.source) or "unknown" end)
        end
        log("info", string.format("get_target_crop called (call #%d) - filter_target: %s, source: %s", 
            app_state._crop_calc_count, ft_name, s_name))
    end
    
    local new_crop = get_target_crop(mouse_x, mouse_y, app_state.zoom.current)
    
    -- Apply follow interpolation (handles edge cases)
    new_crop = apply_follow_interpolation(new_crop, mouse_distance)
    
    -- Update crop if needed (handles threshold logic)
    update_crop_if_needed(new_crop, should_update)
    
    app_state.current_crop = new_crop
    app_state.last_mouse_pos = {x = mouse_x, y = mouse_y}
    
    -- Only remove timer if zoom animation is complete AND follow is not active
    -- If follow is active, keep the timer running
    if progress >= 1.0 and not app_state.follow.active and not app_state.zoom.active then
        obs.timer_remove(animate_zoom)
        app_state.animation_timer = nil
        log("info", "Animation timer removed - zoom complete and follow inactive")
    end
end

-- Smooth zoom out animation
local function smooth_zoom_out()
    -- CRITICAL: Check if app_state exists and cleanup is not in progress
    if not app_state or app_state.cleanup_in_progress then
        log("warning", "Cannot start zoom out - cleanup in progress or app_state invalid")
        return
    end
    
    -- Prevent multiple zoom out animations
    if app_state.zoom_out_in_progress then
        log("warning", "Zoom out already in progress, skipping")
        return
    end
    
    log("info", "Starting smooth zoom out animation")
    
    local start_zoom = app_state.zoom.current
    local start_time = obs.os_gettime_ns() / 1000000 -- Convert to milliseconds
    
    -- Stop any existing timers
    if app_state.animation_timer then
        obs.timer_remove(animate_zoom)
        app_state.animation_timer = nil
    end
    
    if app_state.zoom_out_timer then
        obs.timer_remove(app_state.zoom_out_timer)
        app_state.zoom_out_timer = nil
    end
    
    app_state.zoom_out_in_progress = true
    
    -- Create timer for zoom out animation
    app_state.zoom_out_timer = obs.timer_add(function()
        -- CRITICAL: Check if app_state exists (prevents crash if script is unloaded)
        if not app_state then
            return
        end
        
        -- CRITICAL: Check if zoom out is still in progress (prevents loop after completion)
        if not app_state.zoom_out_in_progress then
            -- Timer was already completed, remove it immediately
            if app_state.zoom_out_timer then
                obs.timer_remove(app_state.zoom_out_timer)
                app_state.zoom_out_timer = nil
            end
            return
        end
        
        -- Early exit if zoom was reactivated
        if app_state.zoom.active then
            app_state.zoom_out_in_progress = false
            if app_state.zoom_out_timer then
                obs.timer_remove(app_state.zoom_out_timer)
                app_state.zoom_out_timer = nil
            end
            return
        end
        
        local current_time = obs.os_gettime_ns() / 1000000
        local elapsed = current_time - start_time
        local progress = math.min(elapsed / app_state.zoom_out_duration, 1.0)
        
        local eased_progress = ease_out(progress)
        app_state.zoom.current = start_zoom + (1.0 - start_zoom) * eased_progress
        
        local mouse_x, mouse_y = ffi_platform.get_mouse_pos()
        
        -- Calculate mouse movement distance
        local mouse_delta_x = math.abs(mouse_x - app_state.last_mouse_pos.x)
        local mouse_delta_y = math.abs(mouse_y - app_state.last_mouse_pos.y)
        local mouse_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
        
        -- Only update crop if mouse moved beyond deadzone (prevents flickering when mouse is stationary)
        local should_update = true
        if app_state.follow.active and mouse_distance < app_state.mouse_deadzone then
            should_update = false
            -- Update last_mouse_pos even when skipping update to prevent deadzone accumulation
            app_state.last_mouse_pos = {x = mouse_x, y = mouse_y}
            -- Continue with zoom out animation even if crop update is skipped
        end
        
        local new_crop = get_target_crop(mouse_x, mouse_y, app_state.zoom.current)
        
        -- Apply follow interpolation (handles edge cases)
        new_crop = apply_follow_interpolation(new_crop, mouse_distance)
        
        -- Update crop if needed (handles threshold logic)
        update_crop_if_needed(new_crop, should_update)
        
        app_state.current_crop = new_crop
        app_state.last_mouse_pos = {x = mouse_x, y = mouse_y}
        
        if progress >= 1.0 then
            -- CRITICAL: Mark as completed FIRST, then remove timer
            app_state.zoom_out_in_progress = false
            
            -- CRITICAL: Remove timer IMMEDIATELY to prevent further callbacks
            local timer_to_remove = app_state.zoom_out_timer
            app_state.zoom_out_timer = nil
            if timer_to_remove then
                obs.timer_remove(timer_to_remove)
            end
            
            -- Now safe to log and cleanup
            log("info", "Zoom out animation completed - cleaning up resources")
            
            app_state.zoom.active = false
            app_state.zoom.current = 1.0 -- Reset zoom to default
            app_state.current_crop = nil
            app_state.last_mouse_pos = {x = 0, y = 0}
            app_state.last_crop = {left = 0, top = 0, right = 0, bottom = 0}
            
            -- Always remove filter when zoom is deactivated
            if app_state.crop_filter and app_state.current_filter_target then
                log("info", "Removing crop filter after zoom out")
                pcall(function()
                    obs.obs_source_filter_remove(app_state.current_filter_target, app_state.crop_filter)
                end)
                -- Release filter only if we created it (protected with pcall)
                if app_state.crop_filter_owned then
                    pcall(function()
                        obs.obs_source_release(app_state.crop_filter)
                    end)
                    log("info", "Crop filter released")
                end
                app_state.crop_filter = nil
                app_state.crop_filter_owned = false
                app_state.current_filter_target = nil
                log("info", "Filter removed after zoom out")
            end
            
            log("info", "Zoom out cleanup completed")
            return -- Exit immediately after completion
        end
    end, app_state.update_interval)
end

-- ============================================================================
-- HOTKEY HANDLERS
-- ============================================================================

-- Handler for zoom hotkey
local function on_zoom_hotkey(pressed)
    if not pressed then
        return
    end
    
    -- Validate or find source
    if not app_state.source then
        app_state.source = find_valid_video_source()
        if not app_state.source then
            log("warning", "No valid video source found in the current scene")
            return
        end
    else
        -- Verify source is still valid
        local source_valid = pcall(function()
            obs.obs_source_get_width(app_state.source)
        end)
        if not source_valid then
            log("warning", "Source became invalid, searching for new one")
            -- Note: Sources from scene items are managed by OBS, no need to release
            app_state.source = nil
            app_state.source = find_valid_video_source()
            if not app_state.source then
                log("warning", "No valid video source found in the current scene")
                return
            end
        end
    end
    
    -- CRITICAL: Validate source has valid dimensions before proceeding
    local is_valid, error_msg = validate_source_dimensions(app_state.source)
    if not is_valid then
        log("error", "Cannot activate zoom: " .. tostring(error_msg))
        log("error", "Please ensure the source has valid dimensions before activating zoom")
        return
    end
    
    if app_state.zoom.active then
        -- Deactivate zoom
        log("info", "Deactivating zoom - stopping all timers immediately")
        
        -- Stop all timers IMMEDIATELY to prevent performance issues
        if app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
            log("info", "Animation timer removed")
        end
        
        if app_state.zoom_out_timer then
            obs.timer_remove(app_state.zoom_out_timer)
            app_state.zoom_out_timer = nil
            log("info", "Zoom out timer removed")
        end
        
        app_state.zoom.active = false
        app_state.follow.active = false -- Also deactivate follow when zoom is deactivated
        app_state.zoom_out_in_progress = false
        
        -- Start smooth zoom out animation
        smooth_zoom_out()
    else
        -- Stop any existing animation before starting new one
        log("info", "Activating zoom")
        
        -- CRITICAL: Stop zoom out animation FIRST
        app_state.zoom_out_in_progress = false
        if app_state.zoom_out_timer then
            obs.timer_remove(app_state.zoom_out_timer)
            app_state.zoom_out_timer = nil
        end
        
        if app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
        end
        
        -- Ensure filter is cleaned up before reactivating
        if app_state.crop_filter and app_state.current_filter_target then
            pcall(function()
                obs.obs_source_filter_remove(app_state.current_filter_target, app_state.crop_filter)
            end)
            if app_state.crop_filter_owned then
                pcall(function()
                    obs.obs_source_release(app_state.crop_filter)
                end)
            end
            app_state.crop_filter = nil
            app_state.crop_filter_owned = false
            app_state.current_filter_target = nil
        end
        
        -- Revalidate source dimensions before reactivating
        local is_valid, error_msg = validate_source_dimensions(app_state.source)
        if not is_valid then
            log("error", "Cannot reactivate zoom: " .. tostring(error_msg))
            log("error", "Please ensure the source has valid dimensions before activating zoom")
            return
        end
        
        -- Reset zoom state completely
        app_state.zoom.current = 1.0
        app_state.zoom.active = true
        app_state.current_crop = nil
        app_state.last_mouse_pos = {x = 0, y = 0}
        app_state.last_crop = {left = 0, top = 0, right = 0, bottom = 0}
        
        -- Reapply filter (returns false if source has invalid dimensions)
        local filter_applied = apply_crop_filter(app_state.source)
        if not filter_applied then
            log("error", "Failed to apply crop filter - zoom activation cancelled")
            app_state.zoom.active = false
            return
        end
        
        if not app_state.original_crop then
            app_state.original_crop = {left = 0, top = 0, right = 0, bottom = 0}
        end
        app_state.zoom.target = app_state.zoom.value
        app_state.zoom.start_time = obs.os_gettime_ns() / 1000000
        
        app_state.animation_timer = obs.timer_add(animate_zoom, app_state.update_interval)
        log("info", string.format("Zoom activated - target: %.2f, speed: %.2f", 
            app_state.zoom.target, app_state.zoom.speed))
    end
    
    log("info", "Zoom " .. (app_state.zoom.active and "activated" or "deactivating"))
    if not app_state.zoom.active then
        log("info", "Follow deactivated automatically")
    end
end

-- Handler for follow hotkey
local function on_follow_hotkey(pressed)
    if not pressed then
        return
    end
    
    if not app_state.zoom.active then
        log("warning", "Follow can only be activated when zoom is active")
        return
    end
    
    app_state.follow.active = not app_state.follow.active
    if app_state.follow.active then
        -- Always ensure timer is running when follow is activated
        if not app_state.animation_timer then
            app_state.animation_timer = obs.timer_add(animate_zoom, app_state.update_interval)
            log("info", "Animation timer started for follow mode")
        end
        log("info", string.format("Follow activated - speed: %.2f", app_state.follow.speed))
    else
        log("info", "Follow deactivated")
        -- Only remove timer if zoom is also inactive
        if not app_state.zoom.active and app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
            log("info", "Animation timer removed - both zoom and follow inactive")
        end
    end
end

-- ============================================================================
-- SCENE CHANGE HANDLER
-- ============================================================================

-- Handle scene changes
local function on_scene_change()
    local new_scene = obs.obs_frontend_get_current_scene()
    if new_scene ~= app_state.current_scene then
        app_state.current_scene = new_scene
        
        -- Remove filter from previous scene if it exists
        if app_state.current_filter_target then
            local old_filter = obs.obs_source_get_filter_by_name(app_state.current_filter_target, CROP_FILTER_NAME)
            if old_filter then
                -- Note: obs_source_get_filter_by_name returns borrowed reference, no need to release
                pcall(function()
                    obs.obs_source_filter_remove(app_state.current_filter_target, old_filter)
                end)
            end
        end
        
        -- Note: Sources from scene items are managed by OBS, no need to release
        app_state.source = nil
        
        -- Release old filter reference only if we created it
        -- Filters obtained with obs_source_get_filter_by_name are borrowed and shouldn't be released
        if app_state.crop_filter and app_state.crop_filter_owned then
            pcall(function()
                obs.obs_source_release(app_state.crop_filter)
            end)
            app_state.crop_filter = nil
            app_state.crop_filter_owned = false
        end
        
        -- Find new valid video source in the new scene
        app_state.source = find_valid_video_source()
        
        if app_state.source then
            -- Apply filter to the new source
            apply_crop_filter(app_state.source)
            
            if app_state.zoom.active then
                -- If zoom was active, gradually reapply zoom to the new scene
                local mouse_x, mouse_y = ffi_platform.get_mouse_pos()
                local start_crop = {left = 0, top = 0, right = 0, bottom = 0}
                local end_crop = get_target_crop(mouse_x, mouse_y, app_state.zoom.current)
                local start_time = obs.os_gettime_ns() / 1000000
                
                local transition_timer = nil
                transition_timer = obs.timer_add(function()
                    -- CRITICAL: Check if app_state exists (prevents crash if script is unloaded)
                    if not app_state then
                        if transition_timer then
                            obs.timer_remove(transition_timer)
                        end
                        return
                    end
                    
                    local current_time = obs.os_gettime_ns() / 1000000
                    local progress = math.min((current_time - start_time) / app_state.scene_transition_duration, 1.0)
                    
                    local new_crop = {
                        left = start_crop.left + (end_crop.left - start_crop.left) * progress,
                        top = start_crop.top + (end_crop.top - start_crop.top) * progress,
                        right = start_crop.right + (end_crop.right - start_crop.right) * progress,
                        bottom = start_crop.bottom + (end_crop.bottom - start_crop.bottom) * progress
                    }
                    
                    update_crop(new_crop.left, new_crop.top, new_crop.right, new_crop.bottom)
                    
                    if progress >= 1.0 then
                        if transition_timer then
                            obs.timer_remove(transition_timer)
                        end
                    end
                end, app_state.update_interval)
            else
                -- If zoom wasn't active, ensure the filter is set without zoom
                update_crop(0, 0, 0, 0)
            end
        else
            -- If no valid source is found, deactivate zoom
            app_state.zoom.active = false
            app_state.follow.active = false
            if app_state.animation_timer then
                obs.timer_remove(animate_zoom)
                app_state.animation_timer = nil
            end
            log("warning", "Zoom deactivated: no valid video source in the new scene")
        end
    end
    -- Release scene (protected with pcall)
    pcall(function()
        obs.obs_source_release(new_scene)
    end)
end

-- ============================================================================
-- SETTINGS VALIDATION
-- ============================================================================

-- Validate settings
local function validate_settings(settings)
    local zoom_val = obs.obs_data_get_double(settings, "zoom_value")
    local zoom_spd = obs.obs_data_get_double(settings, "zoom_speed")
    local follow_spd = obs.obs_data_get_double(settings, "follow_speed")
    
    -- Clamp values to valid ranges
    if zoom_val < 1.1 or zoom_val > 5.0 then
        log("warning", "Zoom value out of range, clamping to valid range")
        obs.obs_data_set_double(settings, "zoom_value", math.max(1.1, math.min(5.0, zoom_val)))
    end
    
    if zoom_spd < 0.01 or zoom_spd > 1.0 then
        log("warning", "Zoom speed out of range, clamping to valid range")
        obs.obs_data_set_double(settings, "zoom_speed", math.max(0.01, math.min(1.0, zoom_spd)))
    end
    
    if follow_spd < 0.01 or follow_spd > 1.0 then
        log("warning", "Follow speed out of range, clamping to valid range")
        obs.obs_data_set_double(settings, "follow_speed", math.max(0.01, math.min(1.0, follow_spd)))
    end
end

-- ============================================================================
-- RESOURCE CLEANUP
-- ============================================================================

-- Cleanup all resources
local function cleanup_all_resources()
    -- CRITICAL: Set cleanup flag FIRST to prevent new timers
    if app_state then
        app_state.cleanup_in_progress = true
        
        -- Remove animation timer
        if app_state.animation_timer then
            obs.timer_remove(animate_zoom)
            app_state.animation_timer = nil
            log("info", "Animation timer removed during cleanup")
        end
        
        -- Remove zoom out timer
        if app_state.zoom_out_timer then
            obs.timer_remove(app_state.zoom_out_timer)
            app_state.zoom_out_timer = nil
            log("info", "Zoom out timer removed during cleanup")
        end
    end
    
    -- Remove crop filter (protected with pcall to prevent crashes)
    if app_state.crop_filter and app_state.current_filter_target then
        pcall(function()
            obs.obs_source_filter_remove(app_state.current_filter_target, app_state.crop_filter)
        end)
        -- Release filter only if we created it (protected with pcall)
        if app_state.crop_filter_owned then
            pcall(function()
                obs.obs_source_release(app_state.crop_filter)
            end)
        end
        app_state.crop_filter = nil
        app_state.crop_filter_owned = false
        app_state.current_filter_target = nil
    end
    
    -- Note: Sources from scene items are managed by OBS, no need to release
    app_state.source = nil
    
    -- Release scene reference (protected with pcall to prevent crashes)
    if app_state.current_scene then
        pcall(function()
            obs.obs_source_release(app_state.current_scene)
        end)
        app_state.current_scene = nil
    end
    
    -- Cleanup FFI platform
    ffi_platform.cleanup()
    
    -- Reset state (after all timers are removed)
    if app_state then
        reset_state()
    end
end

-- ============================================================================
-- OBS CALLBACKS
-- ============================================================================

-- Script description
function script_description()
    return "Zoom and follow mouse for OBS Studio. Supports multi-monitor setups. Version 2.0.0 (Refactored 2025)"
end

-- Script properties
function script_properties()
    local props = obs.obs_properties_create()
    
    -- Main zoom settings
    obs.obs_properties_add_float_slider(props, "zoom_value", "Zoom Value", 1.1, 5.0, 0.1)
    obs.obs_properties_add_float_slider(props, "zoom_speed", "Zoom Speed", 0.01, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "follow_speed", "Follow Speed", 0.01, 1.0, 0.01)
    
    -- Advanced settings group
    local advanced_group = obs.obs_properties_create()
    obs.obs_properties_add_int(advanced_group, "update_interval", "Update Interval (ms)", 8, 100, 1)
    obs.obs_properties_add_int(advanced_group, "mouse_deadzone", "Mouse Deadzone (pixels)", 1, 10, 1)
    obs.obs_properties_add_int(advanced_group, "crop_update_threshold", "Crop Update Threshold (pixels)", 1, 10, 1)
    obs.obs_properties_add_int(advanced_group, "crop_edge_threshold", "Crop Edge Threshold (pixels)", 1, 20, 1)
    obs.obs_properties_add_int(advanced_group, "zoom_animation_duration", "Zoom In Duration (ms)", 100, 1000, 50)
    obs.obs_properties_add_int(advanced_group, "zoom_out_duration", "Zoom Out Duration (ms)", 100, 1000, 50)
    obs.obs_properties_add_int(advanced_group, "scene_transition_duration", "Scene Transition Duration (ms)", 100, 1000, 50)
    obs.obs_properties_add_int(advanced_group, "mouse_cache_duration", "Mouse Cache Duration (ms)", 4, 32, 1)
    obs.obs_properties_add_int(advanced_group, "default_monitor_width", "Default Monitor Width", 640, 7680, 1)
    obs.obs_properties_add_int(advanced_group, "default_monitor_height", "Default Monitor Height", 480, 4320, 1)
    obs.obs_properties_add_group(props, "advanced", "Advanced Settings", obs.OBS_GROUP_NORMAL, advanced_group)
    
    -- Debug
    obs.obs_properties_add_bool(props, "debug_mode", "Enable Debug Mode")
    
    return props
end

-- Default values
function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2.0)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.1)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.1)
    obs.obs_data_set_default_bool(settings, "debug_mode", false)
    
    -- Advanced settings defaults
    obs.obs_data_set_default_int(settings, "update_interval", DEFAULT_UPDATE_INTERVAL)
    obs.obs_data_set_default_int(settings, "mouse_deadzone", DEFAULT_MOUSE_DEADZONE)
    obs.obs_data_set_default_int(settings, "crop_update_threshold", DEFAULT_CROP_UPDATE_THRESHOLD)
    obs.obs_data_set_default_int(settings, "crop_edge_threshold", DEFAULT_CROP_EDGE_THRESHOLD)
    obs.obs_data_set_default_int(settings, "zoom_animation_duration", DEFAULT_ZOOM_ANIMATION_DURATION)
    obs.obs_data_set_default_int(settings, "zoom_out_duration", DEFAULT_ZOOM_OUT_DURATION)
    obs.obs_data_set_default_int(settings, "scene_transition_duration", DEFAULT_SCENE_TRANSITION_DURATION)
    obs.obs_data_set_default_int(settings, "mouse_cache_duration", DEFAULT_MOUSE_CACHE_DURATION)
    obs.obs_data_set_default_int(settings, "default_monitor_width", DEFAULT_MONITOR_WIDTH)
    obs.obs_data_set_default_int(settings, "default_monitor_height", DEFAULT_MONITOR_HEIGHT)
end

-- Settings update
function script_update(settings)
    -- Validate settings first
    validate_settings(settings)
    
    -- Update main state with validated settings
    app_state.zoom.value = obs.obs_data_get_double(settings, "zoom_value")
    app_state.zoom.speed = obs.obs_data_get_double(settings, "zoom_speed")
    app_state.follow.speed = obs.obs_data_get_double(settings, "follow_speed")
    app_state.debug_mode = obs.obs_data_get_bool(settings, "debug_mode")
    
    -- Update advanced configurable parameters
    app_state.update_interval = obs.obs_data_get_int(settings, "update_interval") or DEFAULT_UPDATE_INTERVAL
    app_state.mouse_deadzone = obs.obs_data_get_int(settings, "mouse_deadzone") or DEFAULT_MOUSE_DEADZONE
    app_state.crop_update_threshold = obs.obs_data_get_int(settings, "crop_update_threshold") or DEFAULT_CROP_UPDATE_THRESHOLD
    app_state.crop_edge_threshold = obs.obs_data_get_int(settings, "crop_edge_threshold") or DEFAULT_CROP_EDGE_THRESHOLD
    app_state.zoom_animation_duration = obs.obs_data_get_int(settings, "zoom_animation_duration") or DEFAULT_ZOOM_ANIMATION_DURATION
    app_state.zoom_out_duration = obs.obs_data_get_int(settings, "zoom_out_duration") or DEFAULT_ZOOM_OUT_DURATION
    app_state.scene_transition_duration = obs.obs_data_get_int(settings, "scene_transition_duration") or DEFAULT_SCENE_TRANSITION_DURATION
    app_state.mouse_cache_duration = obs.obs_data_get_int(settings, "mouse_cache_duration") or DEFAULT_MOUSE_CACHE_DURATION
    app_state.default_monitor_width = obs.obs_data_get_int(settings, "default_monitor_width") or DEFAULT_MONITOR_WIDTH
    app_state.default_monitor_height = obs.obs_data_get_int(settings, "default_monitor_height") or DEFAULT_MONITOR_HEIGHT
    
    if app_state.zoom.active then
        app_state.zoom.target = app_state.zoom.value
    end
    
    validate_state()
end

-- Script loading
function script_load(settings)
    -- Initialize FFI platform
    local success, err = ffi_platform.init()
    if not success then
        log("error", "Failed to initialize FFI platform: " .. tostring(err))
    end
    
    -- Get monitor information
    app_state.monitors = ffi_platform.get_monitors()
    log("info", "Detected " .. #app_state.monitors .. " monitor(s)")
    
    -- Register hotkeys
    app_state.zoom_hotkey_id = obs.obs_hotkey_register_frontend(ZOOM_HOTKEY_NAME, "Toggle Zoom", on_zoom_hotkey)
    app_state.follow_hotkey_id = obs.obs_hotkey_register_frontend(FOLLOW_HOTKEY_NAME, "Toggle Follow", on_follow_hotkey)
    
    -- Load saved hotkeys
    local zoom_hotkey_save_array = obs.obs_data_get_array(settings, ZOOM_HOTKEY_NAME)
    obs.obs_hotkey_load(app_state.zoom_hotkey_id, zoom_hotkey_save_array)
    obs.obs_data_array_release(zoom_hotkey_save_array)
    
    local follow_hotkey_save_array = obs.obs_data_get_array(settings, FOLLOW_HOTKEY_NAME)
    obs.obs_hotkey_load(app_state.follow_hotkey_id, follow_hotkey_save_array)
    obs.obs_data_array_release(follow_hotkey_save_array)
    
    -- Add event handler for scene changes
    obs.obs_frontend_add_event_callback(function(event)
        if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
            on_scene_change()
        end
    end)
    
    -- Update settings
    script_update(settings)
    
    -- Apply filter to current scene at startup
    app_state.source = find_valid_video_source()
    if app_state.source then
        apply_crop_filter(app_state.source)
    end
end

-- Script saving
function script_save(settings)
    local zoom_hotkey_save_array = obs.obs_hotkey_save(app_state.zoom_hotkey_id)
    obs.obs_data_set_array(settings, ZOOM_HOTKEY_NAME, zoom_hotkey_save_array)
    obs.obs_data_array_release(zoom_hotkey_save_array)
    
    local follow_hotkey_save_array = obs.obs_hotkey_save(app_state.follow_hotkey_id)
    obs.obs_data_set_array(settings, FOLLOW_HOTKEY_NAME, follow_hotkey_save_array)
    obs.obs_data_array_release(follow_hotkey_save_array)
end

-- Script unloading
function script_unload()
    cleanup_all_resources()
end

