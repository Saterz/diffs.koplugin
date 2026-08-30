local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local DiffLayout = require("diff_layout")
local DiffScrollbar = require("diff_scrollbar")
local DiffSettings = require("diff_settings")
local DiffViewState = require("diff_view_state")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen

--- Resolve a KOReader palette constant and fail before painting if it is invalid.
-- `paintRect` treats nil as black, so silently accepting a misspelled constant
-- would make text unreadable on the device.
local function requiredColor(name)
    local color = Blitbuffer[name]
    assert(color, "Unknown KOReader Blitbuffer color: " .. name)
    return color
end

local DiffView = InputContainer:extend {
    name = "diff_view",
    covers_fullscreen = true,
    dithered = true,
    stop_events_propagation = true,
    wrap_lines = false,
    scroll_row = 0,
    scroll_column = 0,
}

local PALETTE = {
    background = requiredColor("COLOR_WHITE"),
    foreground = requiredColor("COLOR_BLACK"),
    muted = requiredColor("COLOR_DARK_GRAY"),
    header = requiredColor("COLOR_GRAY_D"),
    hunk = requiredColor("COLOR_GRAY_E"),
    addition = requiredColor("COLOR_GRAY_E"),
    addition_strong = requiredColor("COLOR_LIGHT_GRAY"),
    deletion = requiredColor("COLOR_GRAY_D"),
    deletion_strong = requiredColor("COLOR_GRAY_B"),
}

--- Return the path that best identifies a parsed file.
-- @tparam table file parsed file
-- @treturn string display path
local function filePath(file)
    if file.old_path and file.new_path and file.old_path ~= file.new_path then
        return file.old_path .. " → " .. file.new_path
    end
    return file.new_path or file.old_path or _("Unknown file")
end

--- Split UTF-8 text into chunks with at most `max_characters` characters.
-- @tparam string text source text
-- @tparam number max_characters positive maximum per chunk
-- @treturn table chunk array
local function wrapText(text, max_characters)
    if max_characters <= 0 then
        return { text }
    end

    local chunks = {}
    local chunk = {}
    local chunk_length = 0
    local position = 1
    while position <= #text do
        local first_byte = text:byte(position)
        local width = 1
        if first_byte >= 0xF0 and first_byte <= 0xF7 then
            width = 4
        elseif first_byte >= 0xE0 and first_byte <= 0xEF then
            width = 3
        elseif first_byte >= 0xC0 and first_byte <= 0xDF then
            width = 2
        end
        table.insert(chunk, text:sub(position, position + width - 1))
        chunk_length = chunk_length + 1
        position = position + width
        if chunk_length == max_characters then
            table.insert(chunks, table.concat(chunk))
            chunk = {}
            chunk_length = 0
        end
    end
    if chunk_length > 0 or #chunks == 0 then
        table.insert(chunks, table.concat(chunk))
    end
    return chunks
end

--- Remove the first `count` UTF-8 characters from text.
-- @tparam string text source text
-- @tparam number count number of characters to discard
-- @treturn string remaining text
local function dropCharacters(text, count)
    local position = 1
    local discarded = 0
    while position <= #text and discarded < count do
        local first_byte = text:byte(position)
        local width = 1
        if first_byte >= 0xF0 and first_byte <= 0xF7 then
            width = 4
        elseif first_byte >= 0xE0 and first_byte <= 0xEF then
            width = 3
        elseif first_byte >= 0xC0 and first_byte <= 0xDF then
            width = 2
        end
        position = position + width
        discarded = discarded + 1
    end
    return text:sub(position)
end

--- Return the first `count` UTF-8 characters from text.
-- @tparam string text source text
-- @tparam number count number of characters to retain
-- @treturn string retained prefix
local function takeCharacters(text, count)
    local position = 1
    local retained = 0
    while position <= #text and retained < count do
        local first_byte = text:byte(position)
        local width = 1
        if first_byte >= 0xF0 and first_byte <= 0xF7 then
            width = 4
        elseif first_byte >= 0xE0 and first_byte <= 0xEF then
            width = 3
        elseif first_byte >= 0xC0 and first_byte <= 0xDF then
            width = 2
        end
        position = position + width
        retained = retained + 1
    end
    return text:sub(1, position - 1)
end

--- Copy a line for a wrapped continuation without mutating the parsed patch.
-- @tparam table line source parsed line
-- @tparam string content wrapped content
-- @tparam boolean continuation whether this is not the first visual fragment
-- @treturn table visual line
local function visualLine(line, content, continuation)
    if not line then
        return nil
    end
    return {
        kind = line.kind,
        content = content,
        continuation = continuation,
        old_line = continuation and nil or line.old_line,
        new_line = continuation and nil or line.new_line,
        no_newline = line.no_newline,
        intraline = continuation and nil or line.intraline,
    }
end

function DiffView:init()
    self.preferences = self.preferences or {}
    self.wrap_lines = self.preferences.wrap_lines == true
    self.code_face = Font:getFace("infont", 15)
    local face_height, face_ascender = self.code_face.ftsize:getHeightAndAscender()
    self.line_height = math.ceil(face_height) + 6
    self.baseline_offset = math.floor(face_ascender) + 3
    self.header_height = self.line_height * 2
    self.combined_rows = DiffLayout.combined(self.patch)
    self.split_rows = DiffLayout.split(self.patch)
    self.line_number_digits = self:findLineNumberDigits()
    self.digit_width = 0
    for digit = 0, 9 do
        self.digit_width = math.max(self.digit_width, self:measureCode(tostring(digit)))
    end
    self.mode = Screen:getWidth() > Screen:getHeight()
        and "split" or (self.preferences.portrait_mode or "combined")
    self.dimen = Geom:new {
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self._scrollbar_render = function()
        if self.scrollbar_dragging then
            UIManager:setDirty(self, "ui", self.content_dimen, true)
        end
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self:registerTouchZones {
        {
            id = "diff_view_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(gesture)
                return self:handleTap(gesture)
            end,
        },
        {
            id = "diff_view_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(gesture)
                return self:handleSwipe(gesture)
            end,
        },
        {
            id = "diff_view_pan",
            ges = "pan",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(gesture)
                return self:handlePan(gesture)
            end,
        },
        {
            id = "diff_view_pan_release",
            ges = "pan_release",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(gesture)
                return self:handlePanRelease(gesture)
            end,
        },
    }
end

--- Persist and apply a viewer preference changed in the settings widget.
function DiffView:applyPreference(key, value)
    if key == "wrap_lines" or key == "portrait_mode" then
        self.pending_scroll_progress = DiffViewState.scrollProgress(
            self.scroll_row,
            self.current_row_count or 0,
            self.current_visible_count or 0
        )
    end
    self.preferences[key] = value
    if key == "wrap_lines" then
        self.wrap_lines = value
        if value then
            self.scroll_column = 0
        end
    elseif key == "portrait_mode" and self.dimen.w <= self.dimen.h then
        self.mode = value
    end
    if self.on_preference_change then
        self.on_preference_change(key, value)
    end
    self:refresh()
end

--- Open the dedicated viewer settings screen.
function DiffView:openSettings()
    UIManager:show(DiffSettings:new {
        preferences = self.preferences,
        on_change = function(key, value)
            self:applyPreference(key, value)
        end,
    })
end

--- Find the number of digits needed by the largest source line number.
-- A fixed width prevents the gutter from shifting as the diff is scrolled.
-- @treturn number positive digit count
function DiffView:findLineNumberDigits()
    local largest = 1
    for _, file in ipairs(self.patch.files) do
        for _, hunk in ipairs(file.hunks) do
            for _, line in ipairs(hunk.lines) do
                largest = math.max(largest, line.old_line or 0, line.new_line or 0)
            end
        end
    end
    return #tostring(largest)
end

--- Return pixel widths for the line-number and change-marker columns.
-- @tparam string|nil side split side, or nil for combined mode
-- @treturn number gutter width through its separator
-- @treturn number marker column width
function DiffView:codeColumnWidths(side)
    local number_columns = side and 1 or 2
    local padding = math.max(4, Screen:scaleBySize(4))
    local metrics = DiffViewState.gutterMetrics(
        self.digit_width,
        self.line_number_digits,
        number_columns,
        padding
    )
    local marker_width = self:measureCode("+") + padding * 2
    return metrics.gutter_width, marker_width, metrics.number_width, padding
end

--- Return the full-screen size requested by this view.
-- @treturn table geometry containing width and height
function DiffView:getSize()
    return self.dimen
end

--- Force the complete first frame to replace the dialog beneath it.
function DiffView:onShow()
    UIManager:setDirty(self, "full", self.dimen, true)
    return true
end

--- Schedule an e-ink UI refresh after navigation or a mode change.
function DiffView:refresh()
    UIManager:setDirty(self, "ui", self.dimen, true)
end

--- Close the viewer.
-- @treturn boolean true because the event was handled
function DiffView:onClose()
    UIManager:close(self)
    return true
end

--- Cancel delayed scrollbar work when KOReader removes the viewer.
function DiffView:onCloseWidget()
    self:finishScrollbarDrag(nil, false)
end

--- Handle taps in the custom title bar.
-- Left closes, the center toggles layout, and the right toggles wrapping.
-- @tparam table gesture KOReader tap gesture with a `pos` point
-- @treturn boolean true when handled
function DiffView:handleTap(gesture)
    if DiffScrollbar.contains(self.scrollbar, gesture.pos.x, gesture.pos.y) then
        self.scroll_row = DiffScrollbar.rowAtY(self.scrollbar, gesture.pos.y)
        self:refresh()
        return true
    end
    if gesture.pos.y > self.header_height then
        return true
    end

    local icon_width = self.line_height * 2
    if gesture.pos.x < icon_width then
        return self:onClose()
    elseif gesture.pos.x >= self.dimen.w - icon_width then
        self:openSettings()
    end
    return true
end

--- Draw only the moving scrollbar thumb to the physical screen buffer.
-- Updating the old and new footprints separately avoids a tall black refresh
-- artifact when the user scrubs a long distance on an e-ink panel.
function DiffView:paintDragThumb(y)
    local scrollbar = self.scrollbar
    local thumb_y = DiffScrollbar.thumbAtY(scrollbar, y)
    if not thumb_y or thumb_y == scrollbar.thumb_y then
        return
    end

    local old_y = scrollbar.thumb_y
    local function footprint(top)
        return Geom:new {
            x = scrollbar.thumb_x - 1,
            y = math.max(scrollbar.rail_y, top - 1),
            w = scrollbar.thumb_width + 2,
            h = math.min(
                scrollbar.rail_y + scrollbar.rail_height,
                top + scrollbar.thumb_height + 1
            ) - math.max(scrollbar.rail_y, top - 1),
        }
    end
    local old_rect = footprint(old_y)
    local new_rect = footprint(thumb_y)
    Screen.bb:paintRect(old_rect.x, old_rect.y, old_rect.w, old_rect.h, PALETTE.background)
    Screen.bb:paintRect(new_rect.x, new_rect.y, new_rect.w, new_rect.h, PALETTE.background)
    Screen.bb:paintRect(
        scrollbar.rail_x,
        scrollbar.rail_y,
        scrollbar.rail_width,
        scrollbar.rail_height,
        PALETTE.foreground
    )
    Screen.bb:paintRect(
        scrollbar.thumb_x,
        thumb_y,
        scrollbar.thumb_width,
        scrollbar.thumb_height,
        PALETTE.foreground
    )
    scrollbar.thumb_y = thumb_y
    UIManager:setDirty(nil, "fast", old_rect)
    UIManager:setDirty(nil, "fast", new_rect)
end

--- Scrub the diff when a pan begins inside the scrollbar touch target.
function DiffView:handlePan(gesture)
    if not self.scrollbar then
        self:finishScrollbarDrag(nil, false)
        return false
    end
    if not self.scrollbar_dragging then
        local start_pos = gesture.start_pos or gesture.pos
        if not DiffScrollbar.contains(self.scrollbar, start_pos.x, start_pos.y) then
            return false
        end
        self.scrollbar_dragging = true
    end

    self:paintDragThumb(gesture.pos.y)
    local next_row = DiffScrollbar.rowAtY(self.scrollbar, gesture.pos.y)
    if next_row ~= self.scroll_row then
        self.scroll_row = next_row
        UIManager:unschedule(self._scrollbar_render)
        UIManager:scheduleIn(0.18, self._scrollbar_render)
    end
    return true
end

--- Finalize a scrollbar scrub and cancel its delayed content repaint.
-- @tparam number|nil y optional final absolute screen position
-- @tparam boolean|nil repaint whether to repaint after cleanup; defaults to true
-- @treturn boolean whether a drag was active
function DiffView:finishScrollbarDrag(y, repaint)
    local was_dragging = self.scrollbar_dragging == true
    self.scrollbar_dragging = false
    UIManager:unschedule(self._scrollbar_render)
    if y and self.scrollbar then
        self.scroll_row = DiffScrollbar.rowAtY(self.scrollbar, y)
    end
    if was_dragging and repaint ~= false then
        self:refresh()
    end
    return was_dragging
end

--- Finish a scrollbar scrub with one clean content repaint.
function DiffView:handlePanRelease(gesture)
    local y = gesture and gesture.pos and gesture.pos.y
    if not self:finishScrollbarDrag(y, true) then
        return false
    end
    return true
end

--- Handle page and horizontal navigation gestures.
-- @tparam table gesture KOReader swipe gesture with a direction string
-- @treturn boolean true when handled
function DiffView:handleSwipe(gesture)
    if self.scrollbar_dragging then
        local end_y = gesture.end_pos and gesture.end_pos.y
        self:finishScrollbarDrag(end_y, true)
        return true
    end
    local page_rows = math.max(1, math.floor((self.dimen.h - self.header_height) / self.line_height) - 1)
    if gesture.direction == "north" then
        self.scroll_row = self.scroll_row + page_rows
    elseif gesture.direction == "south" then
        self.scroll_row = math.max(0, self.scroll_row - page_rows)
    elseif not self.wrap_lines and gesture.direction == "west" then
        self.scroll_column = self.scroll_column + 12
    elseif not self.wrap_lines and gesture.direction == "east" then
        self.scroll_column = math.max(0, self.scroll_column - 12)
    end
    self:refresh()
    return true
end

--- Measure one string in the code face.
-- @tparam string text text to measure
-- @treturn number width in pixels
function DiffView:measureCode(text)
    return RenderText:sizeUtf8Text(0, nil, self.code_face, text, false, false).x
end

--- Render text directly to the destination buffer.
-- @tparam userdata bb destination BlitBuffer
-- @tparam number x left position
-- @tparam number y row top position
-- @tparam string text text to render
-- @tparam number width clipping width
-- @tparam userdata|nil color optional foreground color
-- @tparam boolean|nil bold optional bold style
function DiffView:drawText(bb, x, y, text, width, color, bold)
    if width <= 0 then
        return
    end
    RenderText:renderUtf8Text(
        bb,
        x,
        y + self.baseline_offset,
        self.code_face,
        text,
        false,
        bold or false,
        color or PALETTE.foreground,
        width
    )
end

--- Shorten a title to the available width and show that it was shortened.
function DiffView:fitText(text, width, bold)
    if self:measureCode(text) <= width then
        return text
    end
    local characters = wrapText(text, 1)
    while #characters > 1 do
        table.remove(characters)
        local candidate = table.concat(characters) .. "…"
        if self:measureCode(candidate) <= width then
            return candidate
        end
    end
    return "…"
end

--- Paint the emphasized character range for a changed line.
-- @tparam userdata bb destination BlitBuffer
-- @tparam number content_x unscrolled content start
-- @tparam number y row top
-- @tparam number cell_right clipping boundary
-- @tparam table line parsed line containing intraline segments
function DiffView:paintIntraline(bb, content_x, y, cell_right, line)
    if not line.intraline or line.intraline.changed == "" or self.wrap_lines then
        return
    end
    local hidden_width = self:measureCode(takeCharacters(line.content, self.scroll_column))
    local start_x = content_x + self:measureCode(line.intraline.prefix) - hidden_width
    local changed_width = math.max(2, self:measureCode(line.intraline.changed))
    local clipped_x = math.max(content_x, start_x)
    local clipped_right = math.min(cell_right, start_x + changed_width)
    if clipped_right > clipped_x then
        local shade = line.kind == "addition"
            and PALETTE.addition_strong or PALETTE.deletion_strong
        bb:paintRect(clipped_x, y + 1, clipped_right - clipped_x, self.line_height - 2, shade)
    end
end

--- Paint one code cell, including gutter, background, and intraline emphasis.
-- @tparam userdata bb destination BlitBuffer
-- @tparam number x cell left
-- @tparam number y row top
-- @tparam number width cell width
-- @tparam table|nil line visual line, or nil for an empty split cell
-- @tparam string|nil side `left` or `right` in split mode; nil in combined mode
function DiffView:paintCodeCell(bb, x, y, width, line, side)
    bb:paintRect(x, y, width, self.line_height, PALETTE.background)
    if not line then
        return
    end

    local background = PALETTE.background
    local marker = " "
    if line.kind == "addition" then
        background = PALETTE.addition
        marker = "+"
    elseif line.kind == "deletion" then
        background = PALETTE.deletion
        marker = "−"
    end
    bb:paintRect(x, y, width, self.line_height, background)

    local gutter_width, marker_width, number_width, number_padding = self:codeColumnWidths(side)
    local number_x = x
    local function drawNumber(value)
        local text = value and tostring(value) or ""
        local text_width = self:measureCode(text)
        self:drawText(
            bb,
            number_x + number_width - number_padding - text_width,
            y,
            text,
            number_width - number_padding,
            PALETTE.muted
        )
        number_x = number_x + number_width
    end
    if side == "left" then
        drawNumber(line.old_line)
    elseif side == "right" then
        drawNumber(line.new_line)
    else
        drawNumber(line.old_line)
        bb:paintRect(x + number_width - 1, y + 3, 1, self.line_height - 6, PALETTE.muted)
        drawNumber(line.new_line)
    end
    bb:paintRect(x + gutter_width - 1, y, 1, self.line_height, PALETTE.muted)

    local marker_x = x + gutter_width + 3
    self:drawText(bb, marker_x, y, marker, marker_width - 3, PALETTE.foreground, true)
    local content_x = x + gutter_width + marker_width
    local cell_right = x + width
    self:paintIntraline(bb, content_x, y, cell_right, line)
    local visible_content = dropCharacters(line.content, self.scroll_column)
    if line.no_newline then
        visible_content = visible_content .. "  ⟂"
    end
    self:drawText(bb, content_x, y, visible_content, cell_right - content_x - 2)
end

--- Expand code rows into wrapped visual rows when wrapping is enabled.
-- @tparam table rows logical combined or split rows
-- @tparam number cell_width available code-cell width
-- @tparam number code_width complete width excluding the scrollbar gutter
-- @treturn table visual row array
function DiffView:visualRows(rows, cell_width, code_width)
    local gutter_width, marker_width = self:codeColumnWidths(self.mode == "split" and "left" or nil)
    local character_width = math.max(1, self:measureCode("M"))
    local max_characters = math.max(
        1,
        math.floor((cell_width - gutter_width - marker_width - 4) / character_width)
    )
    local metadata_characters = math.max(1, math.floor((code_width - 10) / character_width))
    local visual_rows = {}
    for _, row in ipairs(rows) do
        if row.kind == "file" then
            local path_chunks = wrapText(filePath(row.file), metadata_characters)
            for index, chunk in ipairs(path_chunks) do
                table.insert(visual_rows, {
                    kind = index == 1 and "file" or "file_continuation",
                    file = row.file,
                    metadata_text = chunk,
                })
            end
            table.insert(visual_rows, {
                kind = "file_details",
                file = row.file,
                metadata_text = string.format(
                    "[%s]  +%d −%d",
                    row.file.status,
                    row.file.additions,
                    row.file.deletions
                ),
            })
        elseif row.kind == "hunk" then
            for index, chunk in ipairs(wrapText(row.hunk.header, metadata_characters)) do
                table.insert(visual_rows, {
                    kind = index == 1 and "hunk" or "hunk_continuation",
                    hunk = row.hunk,
                    metadata_text = chunk,
                })
            end
        elseif row.kind ~= "code" or not self.wrap_lines then
            table.insert(visual_rows, row)
        elseif self.mode == "combined" then
            local chunks = wrapText(row.line.content, max_characters)
            for index, chunk in ipairs(chunks) do
                table.insert(visual_rows, {
                    kind = "code",
                    line = visualLine(row.line, chunk, index > 1),
                })
            end
        else
            local left_chunks = row.left and wrapText(row.left.content, max_characters) or {}
            local right_chunks = row.right and wrapText(row.right.content, max_characters) or {}
            local count = math.max(#left_chunks, #right_chunks)
            for index = 1, count do
                table.insert(visual_rows, {
                    kind = "code",
                    left = left_chunks[index] and visualLine(row.left, left_chunks[index], index > 1) or nil,
                    right = right_chunks[index] and visualLine(row.right, right_chunks[index], index > 1) or nil,
                })
            end
        end
    end
    return visual_rows
end

--- Paint one file, hunk, or binary-information row.
-- @tparam userdata bb destination BlitBuffer
-- @tparam number x left position
-- @tparam number y row top
-- @tparam number width row width
-- @tparam table row logical row
function DiffView:paintMetadataRow(bb, x, y, width, row)
    if row.kind == "file" or row.kind == "file_continuation" or row.kind == "file_details" then
        bb:paintRect(x, y, width, self.line_height, PALETTE.header)
        self:drawText(
            bb,
            x + 5,
            y,
            row.metadata_text or filePath(row.file),
            width - 10,
            PALETTE.foreground,
            row.kind ~= "file_details"
        )
    elseif row.kind == "hunk" or row.kind == "hunk_continuation" then
        bb:paintRect(x, y, width, self.line_height, PALETTE.hunk)
        self:drawText(bb, x + 5, y, row.metadata_text or row.hunk.header, width - 10, PALETTE.muted)
    else
        bb:paintRect(x, y, width, self.line_height, PALETTE.background)
        self:drawText(bb, x + 5, y, _("Binary file changed"), width - 10, PALETTE.muted, true)
    end
end

--- Paint the complete full-screen diff directly to a BlitBuffer.
-- @tparam userdata bb destination BlitBuffer
-- @tparam number x left screen position
-- @tparam number y top screen position
function DiffView:paintTo(bb, x, y)
    local width = Screen:getWidth()
    local height = Screen:getHeight()
    self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h = x, y, width, height
    self:updateTouchZonesOnScreenResize(self.dimen)

    self.mode = width > height and "split" or (self.preferences.portrait_mode or "combined")

    bb:paintRect(x, y, width, height, PALETTE.background)
    bb:paintRect(x, y, width, self.header_height, PALETTE.header)
    local icon_width = self.line_height * 2
    local title_width = width - icon_width * 2
    self:drawText(bb, x + 8, y + 2, "×", icon_width - 8, PALETTE.foreground, true)
    self:drawText(
        bb,
        x + icon_width,
        y + 2,
        self:fitText(self.title or _("Diffs"), title_width, true),
        title_width,
        PALETTE.foreground,
        true
    )
    self:drawText(
        bb,
        x + width - icon_width + 6,
        y + 2,
        "⚙",
        icon_width - 8,
        PALETTE.foreground,
        true
    )
    self:drawText(
        bb,
        x + 8,
        y + self.line_height,
        self:fitText(self.comparison_title or "", width - 16),
        width - 16,
        PALETTE.foreground
    )
    bb:paintRect(x, y + self.header_height - 2, width, 2, PALETTE.foreground)

    local logical_rows = self.mode == "split" and self.split_rows or self.combined_rows
    local viewport = DiffViewState.viewportMetrics(
        width,
        DiffScrollbar.gutterWidth(function(value)
            return Screen:scaleBySize(value)
        end),
        self.mode == "split"
    )
    local cell_width = self.mode == "split" and viewport.left_width or viewport.code_width
    local rows = self:visualRows(logical_rows, cell_width, viewport.code_width)
    local visible_count = math.max(1, math.floor((height - self.header_height) / self.line_height))
    local max_scroll = math.max(0, #rows - visible_count)
    if self.pending_scroll_progress ~= nil then
        self.scroll_row = DiffViewState.rowForProgress(
            self.pending_scroll_progress,
            #rows,
            visible_count
        )
        self.pending_scroll_progress = nil
    else
        self.scroll_row = math.min(self.scroll_row, max_scroll)
    end
    self.current_row_count = #rows
    self.current_visible_count = visible_count
    self.content_dimen = Geom:new {
        x = x,
        y = y + self.header_height,
        w = width,
        h = height - self.header_height,
    }
    self.code_dimen = Geom:new {
        x = x,
        y = self.content_dimen.y,
        w = viewport.code_width,
        h = self.content_dimen.h,
    }
    self.scrollbar_dimen = Geom:new {
        x = x + viewport.scrollbar_offset,
        y = self.content_dimen.y,
        w = viewport.scrollbar_width,
        h = self.content_dimen.h,
    }

    local row_y = y + self.header_height
    for index = self.scroll_row + 1, math.min(#rows, self.scroll_row + visible_count) do
        local row = rows[index]
        if row.kind ~= "code" then
            self:paintMetadataRow(bb, x, row_y, viewport.code_width, row)
        elseif self.mode == "combined" then
            self:paintCodeCell(bb, x, row_y, viewport.code_width, row.line)
        else
            self:paintCodeCell(bb, x, row_y, viewport.left_width, row.left, "left")
            bb:paintRect(x + viewport.left_width - 1, row_y, 2, self.line_height, PALETTE.foreground)
            self:paintCodeCell(
                bb,
                x + viewport.right_offset,
                row_y,
                viewport.right_width,
                row.right,
                "right"
            )
        end
        row_y = row_y + self.line_height
    end

    bb:paintRect(
        self.scrollbar_dimen.x,
        self.scrollbar_dimen.y,
        self.scrollbar_dimen.w,
        self.scrollbar_dimen.h,
        PALETTE.background
    )
    bb:paintRect(
        self.scrollbar_dimen.x,
        self.scrollbar_dimen.y,
        1,
        self.scrollbar_dimen.h,
        PALETTE.muted
    )

    self.scrollbar = DiffScrollbar.calculate(
        self.scrollbar_dimen,
        #rows,
        visible_count,
        self.scroll_row,
        function(value)
            return Screen:scaleBySize(value)
        end
    )
    if self.scrollbar then
        bb:paintRect(
            self.scrollbar.rail_x,
            self.scrollbar.rail_y,
            self.scrollbar.rail_width,
            self.scrollbar.rail_height,
            PALETTE.foreground
        )
        bb:paintRect(
            self.scrollbar.thumb_x,
            self.scrollbar.thumb_y,
            self.scrollbar.thumb_width,
            self.scrollbar.thumb_height,
            PALETTE.foreground
        )
    end
end

return DiffView
