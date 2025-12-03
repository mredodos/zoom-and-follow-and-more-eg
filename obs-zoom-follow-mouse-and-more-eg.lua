-- Zoom, Follow Mouse and MORE for OBS Studio
-- Version 1.1.2

local obs = obslua
local ffi = require("ffi")

-- Constants
local ZOOM_HOTKEY_NAME = "zoom_and_follow.zoom.toggle"
local FOLLOW_HOTKEY_NAME = "zoom_and_follow.follow.toggle"
local CROP_FILTER_NAME = "zoom_and_follow_crop"
local UPDATE_INTERVAL = 16

-- Global variables
local zoom_active = false
local follow_active = false
local zoom_value = 3.0
local zoom_speed = 0.2
local follow_speed = 0.2
local source = nil
local crop_filter = nil
local original_crop = nil
local current_crop = nil
local target_crop = nil
local current_scene = nil
local current_filter_target = nil
local target_zoom = 1.0
local current_zoom = 1.0
local zoom_start_time = 0
local ZOOM_ANIMATION_DURATION = 300 -- milliseconds
local animation_timer = nil
local monitors = {}
local zoom_hotkey_id = nil
local follow_hotkey_id = nil
local debug_mode = false

-- Utility functions

-- Function to log messages
local function log(message)
    if debug_mode then
        print("[Zoom and Follow] " .. message)
    end
end

-- Function to get information about all monitors
local function get_monitors_info()
    if ffi.os == "Windows" then
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
        ]]

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
    elseif ffi.os == "Linux" then
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
        ]]

        local x11 = ffi.load("X11")
        local xrandr = ffi.load("Xrandr")

        local display = x11.XOpenDisplay(nil)
        if display ~= nil then
            local root = x11.DefaultRootWindow(display)
            local count = ffi.new("int[1]")
            local info = xrandr.XRRGetMonitors(display, root, 1, count)
            
            for i = 0, count[0] - 1 do
                table.insert(monitors, {
                    left = info[i].x,
                    top = info[i].y,
                    right = info[i].x + info[i].width,
                    bottom = info[i].y + info[i].height
                })
            end

            xrandr.XRRFreeMonitors(info)
            x11.XCloseDisplay(display)
        end
    elseif ffi.os == "OSX" then
        ffi.cdef[[
            typedef struct CGDirectDisplayID *CGDirectDisplayID;
            typedef uint32_t CGDisplayCount;
            typedef struct CGRect CGRect;

            int CGGetActiveDisplayList(CGDisplayCount maxDisplays, CGDirectDisplayID *activeDisplays, CGDisplayCount *displayCount);
            CGRect CGDisplayBounds(CGDirectDisplayID display);
        ]]

        local core_graphics = ffi.load("CoreGraphics", true)

        local max_displays = 32
        local active_displays = ffi.new("CGDirectDisplayID[?]", max_displays)
        local display_count = ffi.new("CGDisplayCount[1]")

        if core_graphics.CGGetActiveDisplayList(max_displays, active_displays, display_count) == 0 then
            for i = 0, display_count[0] - 1 do
                local bounds = core_graphics.CGDisplayBounds(active_displays[i])
                table.insert(monitors, {
                    left = bounds.origin.x,
                    top = bounds.origin.y,
                    right = bounds.origin.x + bounds.size.width,
                    bottom = bounds.origin.y + bounds.size.height
                })
            end
        end
    else
        -- For other operating systems, use default values for a single monitor
        monitors = {{left = 0, top = 0, right = 1920, bottom = 1080}}
    end
    log("Detected " .. #monitors .. " monitor(s)")
end

-- Function to get mouse position
local function get_mouse_pos()
    if ffi.os == "Windows" then
        ffi.cdef[[
            typedef struct { long x; long y; } POINT;
            bool GetCursorPos(POINT* point);
        ]]
        local point = ffi.new("POINT[1]")
        if ffi.C.GetCursorPos(point) then
            return point[0].x, point[0].y
        end
    elseif ffi.os == "Linux" then
        ffi.cdef[[
            typedef struct {
                int x, y;
                int dummy1, dummy2, dummy3;
                int dummy4, dummy5, dummy6;
            } XButtonEvent;

            typedef void* Display;
            typedef unsigned long Window;

            Display* XOpenDisplay(const char*);
            void XCloseDisplay(Display*);
            Window DefaultRootWindow(Display*);
            int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
        ]]

        local x11 = ffi.load("X11")

        local display = x11.XOpenDisplay(nil)
        if display ~= nil then
            local root = x11.DefaultRootWindow(display)
            local root_x = ffi.new("int[1]")
            local root_y = ffi.new("int[1]")
            local win_x = ffi.new("int[1]")
            local win_y = ffi.new("int[1]")
            local mask = ffi.new("unsigned int[1]")
            local child = ffi.new("Window[1]")
            local child_revert = ffi.new("Window[1]")

            if x11.XQueryPointer(display, root, child_revert, child, root_x, root_y, win_x, win_y, mask) ~= 0 then
                x11.XCloseDisplay(display)
                return root_x[0], root_y[0]
            end

            x11.XCloseDisplay(display)
        end
    elseif ffi.os == "OSX" then
        ffi.cdef[[
            typedef struct CGPoint CGPoint;
            CGPoint CGEventGetLocation(void* event);
            void* CGEventCreate(void* source);
            void CFRelease(void* cf);
        ]]

        local core_graphics = ffi.load("CoreGraphics", true)

        local event = core_graphics.CGEventCreate(nil)
        local point = core_graphics.CGEventGetLocation(event)
        core_graphics.CFRelease(event)

        return point.x, point.y
    end
    return 0, 0  -- Fallback if we can't get the mouse position
end

-- Function to check if the source type is valid
local function is_valid_source_type(source)
    local source_id = obs.obs_source_get_id(source)
    local valid_types = {
        "ffmpeg_source", "browser_source", "vlc_source",
        "monitor_capture", "window_capture", "game_capture",
        "dshow_input", "av_capture_input"
    }
    for _, valid_type in ipairs(valid_types) do
        if source_id == valid_type then
            return true
        end
    end
    return false
end

-- Function to find a valid video source in the current scene
local function find_valid_video_source()
    local current_scene = obs.obs_frontend_get_current_scene()
    if not current_scene then 
        log("No current scene found")
        return nil 
    end

    local scene = obs.obs_scene_from_source(current_scene)
    local items = obs.obs_scene_enum_items(scene)

    local function check_source(source)
        if is_valid_source_type(source) then
            return source
        elseif obs.obs_source_get_type(source) == obs.OBS_SOURCE_TYPE_SCENE then
            -- Recursively search in nested scenes
            local nested_scene = obs.obs_scene_from_source(source)
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
    obs.obs_source_release(current_scene)

    if valid_source then
        log("Found valid video source: " .. obs.obs_source_get_name(valid_source))
    else
        log("No valid video source found in the current scene")
    end

    return valid_source
end

-- Function to apply the crop filter
local function apply_crop_filter(target_source)
    local parent_source = obs.obs_frontend_get_current_scene()
    local filter_target = obs.obs_source_get_type(target_source) == obs.OBS_SOURCE_TYPE_SCENE and parent_source or target_source

    -- Remove the filter from the previous source or scene if it exists
    if current_filter_target and current_filter_target ~= filter_target then
        local old_filter = obs.obs_source_get_filter_by_name(current_filter_target, CROP_FILTER_NAME)
        if old_filter then
            obs.obs_source_filter_remove(current_filter_target, old_filter)
            obs.obs_source_release(old_filter)
        end
    end

    -- Apply the filter only if it doesn't already exist
    crop_filter = obs.obs_source_get_filter_by_name(filter_target, CROP_FILTER_NAME)
    if not crop_filter then
        crop_filter = obs.obs_source_create("crop_filter", CROP_FILTER_NAME, nil, nil)
        obs.obs_source_filter_add(filter_target, crop_filter)
        log("Crop filter applied to " .. obs.obs_source_get_name(filter_target))
    else
        obs.obs_source_release(crop_filter)
    end

    current_filter_target = filter_target
    obs.obs_source_release(parent_source)
end

-- Function to update the crop
local function update_crop(left, top, right, bottom)
    if crop_filter then
        local settings = obs.obs_data_create()
        obs.obs_data_set_int(settings, "left", math.floor(left + 0.5))
        obs.obs_data_set_int(settings, "top", math.floor(top + 0.5))
        obs.obs_data_set_int(settings, "right", math.floor(right + 0.5))
        obs.obs_data_set_int(settings, "bottom", math.floor(bottom + 0.5))
        obs.obs_source_update(crop_filter, settings)
        obs.obs_data_release(settings)
    end
end

-- Function to calculate the target crop
local function get_target_crop(mouse_x, mouse_y, current_zoom)
    local source_width = obs.obs_source_get_width(source)
    local source_height = obs.obs_source_get_height(source)
    
    -- Find the monitor where the mouse is located
    local current_monitor = monitors[1]  -- Default to the first monitor
    for _, monitor in ipairs(monitors) do
        if mouse_x >= monitor.left and mouse_x < monitor.right and
           mouse_y >= monitor.top and mouse_y < monitor.bottom then
            current_monitor = monitor
            break
        end
    end

    local screen_width = current_monitor.right - current_monitor.left
    local screen_height = current_monitor.bottom - current_monitor.top

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

-- Function for zoom animation
local function animate_zoom()
    if not source or (not zoom_active and not follow_active) then
        obs.timer_remove(animate_zoom)
        animation_timer = nil
        return
    end

    local current_time = obs.os_gettime_ns() / 1000000 -- Convert nanoseconds to milliseconds
    local elapsed_time = current_time - zoom_start_time
    local progress = math.min(elapsed_time / ZOOM_ANIMATION_DURATION, 1.0)
    
    if zoom_active then
        current_zoom = 1.0 + (target_zoom - 1.0) * progress * zoom_speed
    end
    
    local mouse_x, mouse_y = get_mouse_pos()
    local new_crop = get_target_crop(mouse_x, mouse_y, current_zoom)
    
    if follow_active then
        current_crop = current_crop or {left = 0, top = 0, right = 0, bottom = 0}
        new_crop.left = current_crop.left + (new_crop.left - current_crop.left) * follow_speed
        new_crop.top = current_crop.top + (new_crop.top - current_crop.top) * follow_speed
        new_crop.right = current_crop.right + (new_crop.right - current_crop.right) * follow_speed
        new_crop.bottom = current_crop.bottom + (new_crop.bottom - current_crop.bottom) * follow_speed
    end
    
    update_crop(new_crop.left, new_crop.top, new_crop.right, new_crop.bottom)
    current_crop = new_crop
    
    if progress >= 1.0 and not follow_active then
        obs.timer_remove(animate_zoom)
        animation_timer = nil
    end
end

-- Function for smooth zoom out
local function smooth_zoom_out()
    local start_zoom = current_zoom
    local start_time = obs.os_gettime_ns() / 1000000 -- Convert nanoseconds to milliseconds
    local duration = 500 -- 500 ms for zoom out

    local function animate_zoom_out()
        local current_time = obs.os_gettime_ns() / 1000000
        local progress = math.min((current_time - start_time) / duration, 1.0)
        
        current_zoom = start_zoom + (1.0 - start_zoom) * progress
        
        local mouse_x, mouse_y = get_mouse_pos()
        local new_crop = get_target_crop(mouse_x, mouse_y, current_zoom)
        
        if follow_active then
            current_crop = current_crop or {left = 0, top = 0, right = 0, bottom = 0}
            new_crop.left = current_crop.left + (new_crop.left - current_crop.left) * follow_speed
            new_crop.top = current_crop.top + (new_crop.top - current_crop.top) * follow_speed
            new_crop.right = current_crop.right + (new_crop.right - current_crop.right) * follow_speed
            new_crop.bottom = current_crop.bottom + (new_crop.bottom - current_crop.bottom) * follow_speed
        end
        
        update_crop(new_crop.left, new_crop.top, new_crop.right, new_crop.bottom)
        current_crop = new_crop
        
        if progress >= 1.0 then
            obs.timer_remove(animate_zoom_out)
            zoom_active = false
            if not follow_active then
                if crop_filter then
                    obs.obs_source_filter_remove(current_filter_target, crop_filter)
                    crop_filter = nil
                end
                current_filter_target = nil
                if animation_timer then
                    obs.timer_remove(animate_zoom)
                    animation_timer = nil
                end
            end
        end
    end

    if animation_timer then
        obs.timer_remove(animate_zoom)
        animation_timer = nil
    end
    obs.timer_add(animate_zoom_out, 16) -- Approximately 60 FPS
end

-- Hotkey handlers

-- Handler for zoom hotkey
local function on_zoom_hotkey(pressed)
    if not pressed then return end

    if not source then
        source = find_valid_video_source()
        if not source then
            log("No valid video source found in the current scene.")
            return
        end
    end

    if zoom_active then
        zoom_active = false
        follow_active = false  -- Also deactivate follow when zoom is deactivated
        smooth_zoom_out()
    else
        zoom_active = true
        apply_crop_filter(source)
        if not original_crop then
            original_crop = {left = 0, top = 0, right = 0, bottom = 0}
        end
        target_zoom = zoom_value
        zoom_start_time = obs.os_gettime_ns() / 1000000
        
        if not animation_timer then
            animation_timer = obs.timer_add(animate_zoom, UPDATE_INTERVAL)
        end
    end

    log("Zoom " .. (zoom_active and "activated" or "deactivating"))
    if not zoom_active then
        log("Follow deactivated automatically")
    end
end

-- Handler for follow hotkey
local function on_follow_hotkey(pressed)
    if not pressed then return end

    if not zoom_active then
        log("Follow can only be activated when zoom is active.")
        return
    end

    follow_active = not follow_active
    if follow_active then
        if not animation_timer then
            animation_timer = obs.timer_add(animate_zoom, UPDATE_INTERVAL)
        end
    end
    log("Follow " .. (follow_active and "activated" or "deactivated"))
end

-- Function to handle scene changes
local function on_scene_change()
    local new_scene = obs.obs_frontend_get_current_scene()
    if new_scene ~= current_scene then
        current_scene = new_scene
        
        -- Remove the filter from the previous scene if it exists
        if current_filter_target then
            local old_filter = obs.obs_source_get_filter_by_name(current_filter_target, CROP_FILTER_NAME)
            if old_filter then
                obs.obs_source_filter_remove(current_filter_target, old_filter)
                obs.obs_source_release(old_filter)
            end
        end
        
        -- Find a new valid video source in the new scene
        source = find_valid_video_source()
        
        if source then
            -- Apply the filter to the new source
            apply_crop_filter(source)
            
            if zoom_active then
                -- If zoom was active, gradually reapply zoom to the new scene
                local start_crop = {left = 0, top = 0, right = 0, bottom = 0}
                local end_crop = get_target_crop(mouse_x, mouse_y, current_zoom)
                local transition_duration = 300 -- milliseconds
                local start_time = obs.os_gettime_ns() / 1000000
                
                local function transition_crop()
                    local current_time = obs.os_gettime_ns() / 1000000
                    local progress = math.min((current_time - start_time) / transition_duration, 1.0)
                    
                    local new_crop = {
                        left = start_crop.left + (end_crop.left - start_crop.left) * progress,
                        top = start_crop.top + (end_crop.top - start_crop.top) * progress,
                        right = start_crop.right + (end_crop.right - start_crop.right) * progress,
                        bottom = start_crop.bottom + (end_crop.bottom - start_crop.bottom) * progress
                    }
                    
                    update_crop(new_crop.left, new_crop.top, new_crop.right, new_crop.bottom)
                    
                    if progress < 1.0 then
                        obs.timer_add(transition_crop, UPDATE_INTERVAL)
                    end
                end
                
                transition_crop()
            else
                -- If zoom wasn't active, ensure the filter is set without zoom
                update_crop(0, 0, 0, 0)
            end
        else
            -- If no valid source is found, deactivate zoom
            zoom_active = false
            follow_active = false
            if animation_timer then
                obs.timer_remove(animate_zoom)
                animation_timer = nil
            end
            log("Zoom deactivated: no valid video source in the new scene")
        end
    end
    obs.obs_source_release(new_scene)
end

-- OBS functions

-- Script description
function script_description()
    return "Zoom and follow mouse for OBS Studio. Supports multi-monitor setups."
end

-- Script properties
function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_float_slider(props, "zoom_value", "Zoom Value", 1.1, 5.0, 0.1)
    obs.obs_properties_add_float_slider(props, "zoom_speed", "Zoom Speed", 0.01, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "follow_speed", "Follow Speed", 0.01, 1.0, 0.01)
    obs.obs_properties_add_bool(props, "debug_mode", "Enable Debug Mode")
    return props
end

-- Default values
function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2.0)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.1)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.1)
    obs.obs_data_set_default_bool(settings, "debug_mode", false)
end

-- Settings update
function script_update(settings)
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    debug_mode = obs.obs_data_get_bool(settings, "debug_mode")

    if zoom_active then
        target_zoom = zoom_value
    end
end

-- Script loading
function script_load(settings)
    get_monitors_info()  -- Get monitor information at startup

    zoom_hotkey_id = obs.obs_hotkey_register_frontend(ZOOM_HOTKEY_NAME, "Toggle Zoom", on_zoom_hotkey)
    follow_hotkey_id = obs.obs_hotkey_register_frontend(FOLLOW_HOTKEY_NAME, "Toggle Follow", on_follow_hotkey)

    local zoom_hotkey_save_array = obs.obs_data_get_array(settings, ZOOM_HOTKEY_NAME)
    obs.obs_hotkey_load(zoom_hotkey_id, zoom_hotkey_save_array)
    obs.obs_data_array_release(zoom_hotkey_save_array)

    local follow_hotkey_save_array = obs.obs_data_get_array(settings, FOLLOW_HOTKEY_NAME)
    obs.obs_hotkey_load(follow_hotkey_id, follow_hotkey_save_array)
    obs.obs_data_array_release(follow_hotkey_save_array)

    -- Add event handler for scene changes
    obs.obs_frontend_add_event_callback(function(event)
        if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
            on_scene_change()
        end
    end)

    script_update(settings)
    
    -- Apply filter to current scene at startup
    source = find_valid_video_source()
    if source then
        apply_crop_filter(source)
    end
end

-- Script saving
function script_save(settings)
    local zoom_hotkey_save_array = obs.obs_hotkey_save(zoom_hotkey_id)
    obs.obs_data_set_array(settings, ZOOM_HOTKEY_NAME, zoom_hotkey_save_array)
    obs.obs_data_array_release(zoom_hotkey_save_array)

    local follow_hotkey_save_array = obs.obs_hotkey_save(follow_hotkey_id)
    obs.obs_data_set_array(settings, FOLLOW_HOTKEY_NAME, follow_hotkey_save_array)
    obs.obs_data_array_release(follow_hotkey_save_array)
end

-- Script unloading
function script_unload()
    if animation_timer then
        obs.timer_remove(animate_zoom)
        animation_timer = nil
    end
    if crop_filter then
        obs.obs_source_filter_remove(source, crop_filter)
    end
end