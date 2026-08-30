local DiffScrollbar = require("diff_scrollbar")

describe("diff scrollbar", function()
    local bounds = { x = 0, y = 100, w = 600, h = 800 }

    it("sizes its thumb in proportion to the visible rows", function()
        local scrollbar = assert(DiffScrollbar.calculate(bounds, 100, 20, 0))

        assert.are.equal(156, scrollbar.thumb_height)
        assert.are.equal(109, scrollbar.thumb_y)
        assert.is_true(scrollbar.touch.w >= 28)
    end)

    it("maps either end of the rail to the first and last row", function()
        local scrollbar = assert(DiffScrollbar.calculate(bounds, 100, 20, 0))

        assert.are.equal(0, DiffScrollbar.rowAtY(scrollbar, scrollbar.rail_y))
        assert.are.equal(80, DiffScrollbar.rowAtY(
            scrollbar,
            scrollbar.rail_y + scrollbar.rail_height
        ))
    end)

    it("does not render when every row is visible", function()
        assert.is_nil(DiffScrollbar.calculate(bounds, 20, 20, 0))
    end)
end)
