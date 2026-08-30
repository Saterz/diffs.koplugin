local RenderImage = require("ui/renderimage")

local DiffIcon = {}

--- Paint an SVG, showing KOReader's checkerboard when it cannot be loaded.
-- The placeholder makes a missing asset or renderer failure visible without
-- reverting to the previous text-glyph controls.
function DiffIcon.paint(bb, filename, x, y, width, height)
    local image, is_straight_alpha = RenderImage:renderSVGImageFile(filename, width, height)
    if not image then
        local placeholder = RenderImage:renderCheckerboard(width, height, bb:getType())
        bb:blitFrom(placeholder, x, y)
        placeholder:free()
        return false
    end
    if is_straight_alpha then
        bb:alphablitFrom(image, x, y)
    else
        bb:pmulalphablitFrom(image, x, y)
    end
    image:free()
    return true
end

return DiffIcon
