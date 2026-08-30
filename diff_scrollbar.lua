local DiffScrollbar = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

--- Return the width reserved exclusively for the scrollbar and its touch area.
-- @tparam function|nil scale optional pixel scaling function
-- @treturn number gutter width in pixels
function DiffScrollbar.gutterWidth(scale)
    scale = scale or function(value)
        return value
    end
    return math.max(36, scale(36))
end

--- Calculate a row-based scrollbar with an enlarged touch target.
-- @tparam table bounds content rectangle (`x`, `y`, `w`, `h`)
-- @tparam number total_rows total number of visual rows
-- @tparam number visible_rows number of rows that fit in the viewport
-- @tparam number scroll_row current zero-based first row
-- @tparam function|nil scale optional pixel scaling function
-- @treturn table|nil scrollbar geometry, or nil when no scrolling is needed
function DiffScrollbar.calculate(bounds, total_rows, visible_rows, scroll_row, scale)
    if total_rows <= visible_rows or visible_rows <= 0 or bounds.h <= 0 then
        return nil
    end
    scale = scale or function(value)
        return value
    end

    local margin = scale(9)
    local rail_width = math.max(1, scale(1))
    local thumb_width = math.max(rail_width + 2, scale(7))
    local rail_height = bounds.h - margin * 2
    if rail_height <= scale(24) then
        return nil
    end

    local thumb_height = math.max(
        scale(28),
        math.floor(rail_height * visible_rows / total_rows)
    )
    thumb_height = math.min(rail_height, thumb_height)
    local travel = rail_height - thumb_height
    local max_scroll = total_rows - visible_rows
    scroll_row = clamp(scroll_row or 0, 0, max_scroll)
    local thumb_y = bounds.y + margin
    if travel > 0 then
        thumb_y = thumb_y + math.floor(travel * scroll_row / max_scroll)
    end

    local thumb_x = bounds.x + math.floor((bounds.w - thumb_width) / 2)
    local rail_x = thumb_x + math.floor((thumb_width - rail_width) / 2)
    return {
        rail_x = rail_x,
        rail_y = bounds.y + margin,
        rail_width = rail_width,
        rail_height = rail_height,
        thumb_x = thumb_x,
        thumb_y = thumb_y,
        thumb_width = thumb_width,
        thumb_height = thumb_height,
        travel = travel,
        max_scroll = max_scroll,
        touch = {
            x = bounds.x,
            y = bounds.y,
            w = bounds.w,
            h = bounds.h,
        },
    }
end

--- Return whether a screen point is in the scrollbar's wide touch target.
function DiffScrollbar.contains(scrollbar, x, y)
    if not scrollbar then
        return false
    end
    local touch = scrollbar.touch
    return x >= touch.x and x < touch.x + touch.w
        and y >= touch.y and y < touch.y + touch.h
end

--- Map an absolute pointer Y position to a zero-based scroll row.
function DiffScrollbar.rowAtY(scrollbar, y)
    if not scrollbar or scrollbar.travel <= 0 then
        return 0
    end
    local ratio = (y - scrollbar.rail_y - math.floor(scrollbar.thumb_height / 2))
        / scrollbar.travel
    ratio = clamp(ratio, 0, 1)
    return math.floor(scrollbar.max_scroll * ratio + 0.5)
end

--- Map an absolute pointer Y position to a smooth, unsnapped thumb position.
function DiffScrollbar.thumbAtY(scrollbar, y)
    if not scrollbar then
        return nil
    end
    return clamp(
        y - math.floor(scrollbar.thumb_height / 2),
        scrollbar.rail_y,
        scrollbar.rail_y + scrollbar.travel
    )
end

return DiffScrollbar
