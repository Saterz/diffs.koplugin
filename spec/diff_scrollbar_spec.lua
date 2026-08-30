local DiffScrollbar = require("diff_scrollbar")

describe("diff scrollbar", function()
    local bounds = { x = 560, y = 100, w = 40, h = 800 }

    it("sizes its thumb in proportion to the visible rows", function()
        local scrollbar = assert(DiffScrollbar.calculate(bounds, 100, 20, 0))

        assert.are.equal(156, scrollbar.thumb_height)
        assert.are.equal(109, scrollbar.thumb_y)
        assert.are.same(bounds, scrollbar.touch)
        assert.is_true(scrollbar.thumb_x >= bounds.x)
        assert.is_true(scrollbar.thumb_x + scrollbar.thumb_width <= bounds.x + bounds.w)
    end)

    it("maps either end of the rail to the first and last row", function()
        local scrollbar = assert(DiffScrollbar.calculate(bounds, 100, 20, 0))

        assert.are.equal(0, DiffScrollbar.rowAtY(scrollbar, scrollbar.rail_y))
        assert.are.equal(80, DiffScrollbar.rowAtY(
            scrollbar,
            scrollbar.rail_y + scrollbar.rail_height
        ))
    end)

    it("stays visible when every row fits", function()
        local scrollbar = assert(DiffScrollbar.calculate(bounds, 20, 20, 0))

        assert.are.equal(scrollbar.rail_height, scrollbar.thumb_height)
        assert.are.equal(0, scrollbar.travel)
        assert.are.equal(0, scrollbar.max_scroll)
        assert.are.equal(0, DiffScrollbar.rowAtY(scrollbar, bounds.y + bounds.h))
    end)

    it("reserves a touch-friendly dedicated gutter", function()
        assert.are.equal(36, DiffScrollbar.gutterWidth())
        assert.are.equal(72, DiffScrollbar.gutterWidth(function(value)
            return value * 2
        end))
    end)
end)
