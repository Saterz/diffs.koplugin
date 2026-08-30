local DiffViewState = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

--- Calculate fixed-width number columns with padding on both sides.
-- @tparam number digit_width width of the widest rendered digit
-- @tparam number digit_count digits in the largest line number
-- @tparam number column_count one for split mode, two for combined mode
-- @tparam number padding horizontal padding around a number
-- @treturn table number and gutter widths
function DiffViewState.gutterMetrics(digit_width, digit_count, column_count, padding)
    digit_width = math.max(0, digit_width or 0)
    digit_count = math.max(1, digit_count or 1)
    column_count = math.max(1, column_count or 1)
    padding = math.max(0, padding or 0)
    local number_width = math.ceil(digit_width * digit_count) + padding * 2
    return {
        number_width = number_width,
        gutter_width = number_width * column_count + padding,
        padding = padding,
    }
end

--- Divide a screen width into code cells and a dedicated scrollbar gutter.
-- @tparam number width complete viewer width
-- @tparam number scrollbar_width requested scrollbar gutter width
-- @tparam boolean split whether the code area uses two panes
-- @treturn table normalized code, pane, and scrollbar widths
function DiffViewState.viewportMetrics(width, scrollbar_width, split)
    width = math.max(2, math.floor(width or 0))
    scrollbar_width = math.max(0, math.floor(scrollbar_width or 0))
    scrollbar_width = math.min(scrollbar_width, width - 2)
    local code_width = width - scrollbar_width
    local left_width = split and math.floor(code_width / 2) or code_width
    return {
        code_width = code_width,
        left_width = left_width,
        right_width = split and code_width - left_width - 1 or 0,
        right_offset = split and left_width + 1 or 0,
        scrollbar_width = scrollbar_width,
        scrollbar_offset = code_width,
    }
end

--- Convert a row offset into progress across its scrollable range.
function DiffViewState.scrollProgress(scroll_row, total_rows, visible_rows)
    local max_scroll = math.max(0, total_rows - visible_rows)
    if max_scroll == 0 then
        return 0
    end
    return clamp(scroll_row or 0, 0, max_scroll) / max_scroll
end

--- Convert progress back into a valid row offset for another layout.
function DiffViewState.rowForProgress(progress, total_rows, visible_rows)
    local max_scroll = math.max(0, total_rows - visible_rows)
    return math.floor(max_scroll * clamp(progress or 0, 0, 1) + 0.5)
end

return DiffViewState
