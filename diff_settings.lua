local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen

local DiffSettings = InputContainer:extend {
    name = "diff_settings",
    covers_fullscreen = true,
    stop_events_propagation = true,
}

function DiffSettings:init()
    self.preferences = self.preferences or {}
    self.face = Font:getFace("infont", 17)
    local face_height, face_ascender = self.face.ftsize:getHeightAndAscender()
    self.row_height = math.max(Screen:scaleBySize(52), math.ceil(face_height) + 20)
    self.baseline_offset = math.floor(face_ascender) + math.floor((self.row_height - face_height) / 2)
    self.dimen = Geom:new { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:registerTouchZones {
        {
            id = "diff_settings_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(gesture)
                return self:handleTap(gesture)
            end,
        },
    }
end

function DiffSettings:getSize()
    return self.dimen
end

function DiffSettings:onShow()
    UIManager:setDirty(self, "full", self.dimen)
    return true
end

function DiffSettings:onClose()
    UIManager:close(self)
    return true
end

function DiffSettings:change(key, value)
    self.preferences[key] = value
    if self.on_change then
        self.on_change(key, value)
    end
    UIManager:setDirty(self, "ui")
end

function DiffSettings:handleTap(gesture)
    local y = gesture.pos.y
    if y < self.row_height then
        return self:onClose()
    elseif y < self.row_height * 2 then
        self:change("wrap_lines", not self.preferences.wrap_lines)
    elseif y < self.row_height * 3 then
        local mode = self.preferences.portrait_mode == "split" and "combined" or "split"
        self:change("portrait_mode", mode)
    elseif y < self.row_height * 4 then
        self:change("show_scrollbar", self.preferences.show_scrollbar == false)
    end
    return true
end

function DiffSettings:drawText(bb, x, y, text, width, bold)
    RenderText:renderUtf8Text(
        bb,
        x,
        y + self.baseline_offset,
        self.face,
        text,
        false,
        bold or false,
        Blitbuffer.COLOR_BLACK,
        width
    )
end

function DiffSettings:paintRow(bb, x, y, width, label, value)
    bb:paintRect(x, y, width, self.row_height, Blitbuffer.COLOR_WHITE)
    self:drawText(bb, x + 12, y, label, math.floor(width * 0.68))
    local value_width = RenderText:sizeUtf8Text(0, nil, self.face, value, false, true).x
    self:drawText(bb, x + width - value_width - 12, y, value, value_width, true)
    bb:paintRect(x + 8, y + self.row_height - 1, width - 16, 1, Blitbuffer.COLOR_GRAY_B)
end

function DiffSettings:paintTo(bb, x, y)
    local width = Screen:getWidth()
    local height = Screen:getHeight()
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, width, height
    self:updateTouchZonesOnScreenResize(self.dimen)

    bb:paintRect(x, y, width, height, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x, y, width, self.row_height, Blitbuffer.COLOR_GRAY_D)
    self:drawText(bb, x + 12, y, "×", self.row_height - 12, true)
    self:drawText(bb, x + self.row_height, y, _("Diff settings"), width - self.row_height * 2, true)
    bb:paintRect(x, y + self.row_height - 2, width, 2, Blitbuffer.COLOR_BLACK)

    self:paintRow(
        bb,
        x,
        y + self.row_height,
        width,
        _("Wrap long lines"),
        self.preferences.wrap_lines and _("On") or _("Off")
    )
    self:paintRow(
        bb,
        x,
        y + self.row_height * 2,
        width,
        _("Portrait layout"),
        self.preferences.portrait_mode == "split" and _("Split") or _("Combined")
    )
    self:paintRow(
        bb,
        x,
        y + self.row_height * 3,
        width,
        _("Fast scrollbar"),
        self.preferences.show_scrollbar == false and _("Off") or _("On")
    )
end

return DiffSettings
