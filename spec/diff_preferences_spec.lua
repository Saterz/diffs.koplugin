local DiffPreferences = require("diff_preferences")

describe("diff preferences", function()
    local function settingsWith(data)
        return {
            data = data,
            readSetting = function(self, key)
                return self.data[key]
            end,
            isTrue = function(self, key)
                return self.data[key] == true
            end,
            has = function(self, key)
                return self.data[key] ~= nil
            end,
            saveSetting = function(self, key, value)
                self.data[key] = value
                return self
            end,
            delSetting = function(self, key)
                self.data[key] = nil
                return self
            end,
            flush = function(self)
                self.flush_count = (self.flush_count or 0) + 1
                return self
            end,
        }
    end

    it("migrates the previous portrait choice and removes the scrollbar key", function()
        local settings = settingsWith {
            wrap_lines = true,
            portrait_mode = "split",
            show_scrollbar = false,
        }

        local preferences = DiffPreferences.load(settings)

        assert.is_true(preferences.wrap_lines)
        assert.are.equal("split", preferences.layout_mode)
        assert.are.equal("split", settings.data.layout_mode)
        assert.is_nil(settings.data.portrait_mode)
        assert.is_nil(settings.data.show_scrollbar)
        assert.are.equal(1, settings.flush_count)
    end)

    it("keeps a valid orientation-independent layout", function()
        local settings = settingsWith {
            layout_mode = "combined",
            portrait_mode = "split",
        }

        local preferences = DiffPreferences.load(settings)

        assert.are.equal("combined", preferences.layout_mode)
        assert.is_nil(settings.data.portrait_mode)
        assert.are.equal(1, settings.flush_count)
    end)

    it("uses combined mode for missing or invalid values", function()
        local settings = settingsWith { layout_mode = "unknown" }

        local preferences = DiffPreferences.load(settings)

        assert.are.equal("combined", preferences.layout_mode)
        assert.are.equal("combined", settings.data.layout_mode)
    end)
end)
