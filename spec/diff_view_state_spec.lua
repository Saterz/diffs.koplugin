local DiffViewState = require("diff_view_state")

describe("diff view state", function()
    it("reserves enough room for four-digit line numbers", function()
        local metrics = DiffViewState.gutterMetrics(9, 4, 2, 5)

        assert.are.equal(46, metrics.number_width)
        assert.are.equal(97, metrics.gutter_width)
        assert.is_true(metrics.number_width > 9 * 4)
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
