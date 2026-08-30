local DiffPreferences = {}

local function validLayout(value)
    return value == "combined" or value == "split"
end

--- Load viewer preferences and migrate obsolete orientation/scrollbar keys.
-- @tparam table settings KOReader LuaSettings-compatible object
-- @treturn table normalized viewer preferences
function DiffPreferences.load(settings)
    local stored_layout = settings:readSetting("layout_mode")
    local previous_layout = settings:readSetting("portrait_mode")
    local layout_mode = validLayout(stored_layout) and stored_layout
        or validLayout(previous_layout) and previous_layout
        or "combined"
    local changed = false

    if stored_layout ~= layout_mode then
        settings:saveSetting("layout_mode", layout_mode)
        changed = true
    end
    if settings:has("portrait_mode") then
        settings:delSetting("portrait_mode")
        changed = true
    end
    if settings:has("show_scrollbar") then
        settings:delSetting("show_scrollbar")
        changed = true
    end
    if changed then
        settings:flush()
    end

    return {
        wrap_lines = settings:isTrue("wrap_lines"),
        layout_mode = layout_mode,
    }
end

return DiffPreferences
