local RenderImage = require("ui/renderimage")
local lfs = require("libs/libkoreader-lfs")

local DiffIcon = {}

--- Paint an SVG only when its file is present and the renderer accepts it.
-- Returning false leaves the caller free to keep the control blank without
-- KOReader's checkerboard missing-image placeholder.
function DiffIcon.paint(bb, filename, x, y, width, height)
    if lfs.attributes(filename, "mode") ~= "file" then
        return false
    end

    local image, is_straight_alpha = RenderImage:renderSVGImageFile(filename, width, height)
    if not image then
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
