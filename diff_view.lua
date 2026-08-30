local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local DiffLayout = require("diff_layout")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen

local DiffView = InputContainer:extend {
    name = "diff_view",
    stop_events_propagation = true,
    wrap_lines = false,
    scroll_row = 0,
    scroll_column = 0,
}

local PALETTE = {
    background = Blitbuffer.COLOR_WHITE,
    foreground = Blitbuffer.COLOR_BLACK,
    muted = Blitbuffer.COLOR_DARK_GRAY,
    header = Blitbuffer.COLOR_GRAY_D,
    hunk = Blitbuffer.COLOR_GRAY_E,
    addition = Blitbuffer.COLOR_GRAY_E,
    addition_strong = Blitbuffer.COLOR_GRAY_C,
    deletion = Blitbuffer.COLOR_GRAY_D,
    deletion_strong = Blitbuffer.COLOR_GRAY_B,
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
    self.code_face = Font:getFace("infont", 15)
    local face_height, face_ascender = self.code_face.ftsize:getHeightAndAscender()
    self.line_height = math.ceil(face_height) + 6
    self.baseline_offset = math.floor(face_ascender) + 3
    self.header_height = self.line_height * 2
    self.combined_rows = DiffLayout.combined(self.patch)
    self.split_rows = DiffLayout.split(self.patch)
    self.line_number_digits = self:findLineNumberDigits()
    self.mode = Screen:getWidth() > Screen:getHeight() and "split" or "combined"
    self.dimen = Geom:new {
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
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
    }
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
    local number_width = self:measureCode(string.rep("0", self.line_number_digits)) + 5
    local number_columns = side and 1 or 2
    local gutter_width = number_width * number_columns + 5
    local marker_width = self:measureCode("+") + 8
    return gutter_width, marker_width
end

--- Return the full-screen size requested by this view.
-- @treturn table geometry containing width and height
function DiffView:getSize()
    return self.dimen
end

--- Schedule an e-ink UI refresh after navigation or a mode change.
function DiffView:refresh()
    UIManager:setDirty(self, "ui")
end

--- Close the viewer.
-- @treturn boolean true because the event was handled
function DiffView:onClose()
    UIManager:close(self)
    return true
end

--- Handle taps in the custom title bar.
-- Left closes, the center toggles layout, and the right toggles wrapping.
-- @tparam table gesture KOReader tap gesture with a `pos` point
-- @treturn boolean true when handled
function DiffView:handleTap(gesture)
    if gesture.pos.y > self.header_height then
        return true
    end

    local third = self.dimen.w / 3
    if gesture.pos.x < third then
        return self:onClose()
    elseif gesture.pos.x < third * 2 then
        if self.dimen.w <= self.dimen.h then
            self.mode = self.mode == "combined" and "split" or "combined"
            self.scroll_row = 0
            self.scroll_column = 0
            self:refresh()
        end
    else
        self.wrap_lines = not self.wrap_lines
        if self.wrap_lines then
            self.scroll_column = 0
        end
        self.scroll_row = 0
        self:refresh()
    end
    return true
end

--- Handle page and horizontal navigation gestures.
-- @tparam table gesture KOReader swipe gesture with a direction string
-- @treturn boolean true when handled
function DiffView:handleSwipe(gesture)
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

--- Paint the emphasized character range for a changed line.
-- @tparam userdata bb destination BlitBuffer
-- @tparam number content_x unscrolled content start
-- @tparam number y row top
-- @tparam number cell_right clipping boundary
-- @tparam table line parsed line containing intraline segments
function DiffView:paintIntraline(bb, content_x, y, cell_right, line)
    if not line.intraline or line.intraline.changed == ""
        or self.wrap_lines or self.scroll_column > 0 then
        return
    end
    local start_x = content_x + self:measureCode(line.intraline.prefix)
    local changed_width = math.max(2, self:measureCode(line.intraline.changed))
    local clipped_x = math.max(content_x, start_x)
    local clipped_right = math.min(cell_right, start_x + changed_width)
    if clipped_right > clipped_x then
        local shade = line.kind == "addition" and PALETTE.addition_strong or PALETTE.deletion_strong
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
    if line.kind == "addition" then
        bb:paintRect(x, y, width, 1, PALETTE.muted)
    elseif line.kind == "deletion" then
        bb:paintRect(x, y + self.line_height - 2, width, 2, PALETTE.foreground)
    end

    local gutter_width, marker_width = self:codeColumnWidths(side)
    local number_width = math.floor((gutter_width - 5) / (side and 1 or 2))
    local number_x = x + 2
    local function drawNumber(value)
        local text = value and tostring(value) or ""
        local text_width = self:measureCode(text)
        self:drawText(bb, number_x + number_width - text_width - 3, y, text, number_width, PALETTE.muted)
        number_x = number_x + number_width
    end
    if side == "left" then
        drawNumber(line.old_line)
    elseif side == "right" then
        drawNumber(line.new_line)
    else
        drawNumber(line.old_line)
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
-- @treturn table visual row array
function DiffView:visualRows(rows, cell_width)
    local gutter_width, marker_width = self:codeColumnWidths(self.mode == "split" and "left" or nil)
    local character_width = math.max(1, self:measureCode("M"))
    local max_characters = math.max(
        1,
        math.floor((cell_width - gutter_width - marker_width - 4) / character_width)
    )
    local metadata_characters = math.max(1, math.floor((self.dimen.w - 10) / character_width))
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

    if width > height then
        self.mode = "split"
    end

    bb:paintRect(x, y, width, height, PALETTE.background)
    bb:paintRect(x, y, width, self.header_height, PALETTE.header)
    local title = self.title or _("Diffs")
    self:drawText(bb, x + 5, y + 2, title, width - 10, PALETTE.foreground, true)
    local mode_label = self.mode == "split" and _("Split") or _("Combined")
    local wrap_label = self.wrap_lines and _("Wrap: on") or _("Wrap: off")
    self:drawText(bb, x + 5, y + self.line_height, _("Close"), width / 3 - 10, PALETTE.foreground)
    self:drawText(bb, x + width / 3 + 5, y + self.line_height, mode_label, width / 3 - 10, PALETTE.foreground)
    self:drawText(bb, x + width * 2 / 3 + 5, y + self.line_height, wrap_label, width / 3 - 10, PALETTE.foreground)
    bb:paintRect(x, y + self.header_height - 2, width, 2, PALETTE.foreground)

    local logical_rows = self.mode == "split" and self.split_rows or self.combined_rows
    local cell_width = self.mode == "split" and math.floor(width / 2) or width
    local rows = self:visualRows(logical_rows, cell_width)
    local visible_count = math.max(1, math.floor((height - self.header_height) / self.line_height))
    local max_scroll = math.max(0, #rows - visible_count)
    self.scroll_row = math.min(self.scroll_row, max_scroll)

    local row_y = y + self.header_height
    for index = self.scroll_row + 1, math.min(#rows, self.scroll_row + visible_count) do
        local row = rows[index]
        if row.kind ~= "code" then
            self:paintMetadataRow(bb, x, row_y, width, row)
        elseif self.mode == "combined" then
            self:paintCodeCell(bb, x, row_y, width, row.line)
        else
            local left_width = math.floor(width / 2)
            self:paintCodeCell(bb, x, row_y, left_width, row.left, "left")
            bb:paintRect(x + left_width - 1, row_y, 2, self.line_height, PALETTE.foreground)
            self:paintCodeCell(bb, x + left_width + 1, row_y, width - left_width - 1, row.right, "right")
        end
        row_y = row_y + self.line_height
    end
end

return DiffView
