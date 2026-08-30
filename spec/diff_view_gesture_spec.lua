local DiffScrollbar = require("diff_scrollbar")
local DiffView = require("diff_view")
local UIManager = require("ui/uimanager")

describe("diff view gestures", function()
    local original_unschedule
    local unscheduled

    local function newView()
        local view = setmetatable({
            dimen = { w = 200, h = 100 },
            header_height = 10,
            line_height = 10,
            scroll_row = 0,
            scrollbar_dragging = false,
            scrollbar = assert(DiffScrollbar.calculate(
                { x = 0, y = 10, w = 200, h = 90 },
                100,
                20,
                0
            )),
            _scrollbar_render = function()
            end,
        }, { __index = DiffView })
        function view:refresh()
            self.refresh_count = (self.refresh_count or 0) + 1
        end
        return view
    end

    before_each(function()
        original_unschedule = UIManager.unschedule
        unscheduled = nil
        UIManager.unschedule = function(_, action)
            unscheduled = action
            return true
        end
    end)

    after_each(function()
        UIManager.unschedule = original_unschedule
    end)

    it("finalizes a fast drag without also paging", function()
        local view = newView()
        view.scrollbar_dragging = true

        view:handleSwipe({
            direction = "north",
            pos = { x = 190, y = 10 },
            end_pos = { x = 190, y = 100 },
        })

        assert.is_false(view.scrollbar_dragging)
        assert.are.equal(view.scrollbar.max_scroll, view.scroll_row)
        assert.are.equal(1, view.refresh_count)
        assert.are.equal(view._scrollbar_render, unscheduled)
    end)

    it("allows repeated page swipes after a drag ends", function()
        local view = newView()
        view.scrollbar_dragging = true
        view:handleSwipe({
            direction = "north",
            pos = { x = 190, y = 10 },
            end_pos = { x = 190, y = 10 },
        })

        view:handleSwipe({ direction = "north", pos = { x = 20, y = 50 } })
        local first_page = view.scroll_row
        view:handleSwipe({ direction = "north", pos = { x = 20, y = 50 } })

        assert.is_true(first_page > 0)
        assert.is_true(view.scroll_row > first_page)
    end)

    it("uses the pan start position for scrollbar ownership", function()
        local view = newView()
        local touch = view.scrollbar.touch

        local handled = view:handlePan({
            start_pos = { x = touch.x - 1, y = touch.y + 10 },
            pos = { x = touch.x + 1, y = touch.y + 20 },
        })

        assert.is_false(handled)
        assert.is_false(view.scrollbar_dragging)
    end)

    it("cleans up a pending drag when the viewer closes", function()
        local view = newView()
        view.scrollbar_dragging = true

        view:onCloseWidget()

        assert.is_false(view.scrollbar_dragging)
        assert.are.equal(view._scrollbar_render, unscheduled)
        assert.is_nil(view.refresh_count)
    end)
end)
