local DiffView = require("diff_view")

describe("diff view layout changes", function()
    it("preserves progress instead of returning to the first row", function()
        local saved_key
        local saved_value
        local view = setmetatable({
            preferences = { layout_mode = "combined" },
            mode = "combined",
            scroll_row = 40,
            current_row_count = 100,
            current_visible_count = 20,
            scroll_column = 0,
            dimen = { w = 800, h = 600 },
            on_preference_change = function(key, value)
                saved_key = key
                saved_value = value
            end,
        }, { __index = DiffView })
        function view:refresh()
            self.refreshed = true
        end

        view:applyPreference("layout_mode", "split")

        assert.are.equal(0.5, view.pending_scroll_progress)
        assert.are.equal("split", view.mode)
        assert.are.equal("split", view.preferences.layout_mode)
        assert.are.equal("layout_mode", saved_key)
        assert.are.equal("split", saved_value)
        assert.is_true(view.refreshed)
    end)
end)
