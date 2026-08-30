local DiffViewState = require("diff_view_state")

describe("diff view state", function()
    it("reserves enough room for four-digit line numbers", function()
        local metrics = DiffViewState.gutterMetrics(9, 4, 2, 5)

        assert.are.equal(46, metrics.number_width)
        assert.are.equal(97, metrics.gutter_width)
        assert.is_true(metrics.number_width > 9 * 4)
    end)

    it("keeps the scrollbar outside combined code", function()
        local viewport = DiffViewState.viewportMetrics(600, 40, false)

        assert.are.equal(560, viewport.code_width)
        assert.are.equal(560, viewport.scrollbar_offset)
        assert.are.equal(40, viewport.scrollbar_width)
    end)

    it("divides only the code area into split panes", function()
        local viewport = DiffViewState.viewportMetrics(800, 40, true)

        assert.are.equal(760, viewport.code_width)
        assert.are.equal(380, viewport.left_width)
        assert.are.equal(379, viewport.right_width)
        assert.are.equal(381, viewport.right_offset)
    end)

    it("preserves relative progress when the layout row count changes", function()
        local progress = DiffViewState.scrollProgress(45, 110, 20)
        local split_row = DiffViewState.rowForProgress(progress, 70, 20)

        assert.are.equal(0.5, progress)
        assert.are.equal(25, split_row)
    end)

    it("clamps restored progress to the scrollable range", function()
        assert.are.equal(0, DiffViewState.rowForProgress(-1, 100, 20))
        assert.are.equal(80, DiffViewState.rowForProgress(2, 100, 20))
    end)
end)
