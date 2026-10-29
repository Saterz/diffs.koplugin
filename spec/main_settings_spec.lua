describe("main settings dialog", function()
    local plugin
    local originals
    local read_result
    local shown
    local closed
    local api_key
    local pending

    local function translated(text)
        return "translated: " .. text
    end

    before_each(function()
        read_result = { exists = false }
        shown = {}
        closed = {}
        pending = {}
        api_key = {
            read = function(path)
                assert.are.equal("/settings/Diffs/github_api.key", path)
                return read_result.token, read_result.exists, read_result.error
            end,
        }

        local stubs = {
            compare_request = {},
            datastorage = {
                getSettingsDir = function()
                    return "/settings"
                end,
            },
            diff_parser = {},
            diff_preferences = {},
            diff_view = {},
            github_client = {},
            github_api_key = api_key,
            ["libs/libkoreader-lfs"] = {},
            ["ui/widget/infomessage"] = {
                new = function(_, options)
                    return options
                end,
            },
            luasettings = {},
            ["ui/widget/multiinputdialog"] = {
                new = function(_, options)
                    function options:onShowKeyboard()
                        self.keyboard_shown = true
                    end
                    function options:getFields()
                        return { self.fields[1].text }
                    end
                    return options
                end,
            },
            ["ui/network/manager"] = {
                willRerunWhenOnline = function() return false end,
            },
            ["ui/uimanager"] = {
                nextTick = function(_, action)
                    pending[#pending + 1] = action
                end,
                show = function(_, widget)
                    table.insert(shown, widget)
                end,
                close = function(_, widget)
                    table.insert(closed, widget)
                end,
            },
            ["ui/widget/container/widgetcontainer"] = {
                extend = function(_, options)
                    return options
                end,
            },
            gettext = translated,
        }

        originals = { main = { package.loaded.main } }
        for name, stub in pairs(stubs) do
            originals[name] = { package.loaded[name] }
            package.loaded[name] = stub
        end
        package.loaded.main = nil
        plugin = require("main")
    end)

    after_each(function()
        for name, original in pairs(originals) do
            package.loaded[name] = original[1]
        end
    end)

    local function assertDialog(hint)
        assert.are.equal(1, #shown)
        local dialog = shown[1]
        assert.are.equal(translated("GitHub API key"), dialog.title)
        assert.are.equal(translated("API key"), dialog.fields[1].description)
        assert.are.equal("", dialog.fields[1].text)
        assert.are.equal(translated(hint), dialog.fields[1].hint)
        assert.are.equal(translated("Cancel"), dialog.buttons[1][1].text)
        assert.are.equal(translated("Clear"), dialog.buttons[1][2].text)
        assert.are.equal(translated("Save"), dialog.buttons[1][3].text)
        assert.is_true(dialog.keyboard_shown)
        assert.are.equal(0, #closed)
        return dialog
    end

    describe("comparison messages", function()
        local request = { owner = "example", repo = "plugin", base_ref = "v1", head_ref = "v2" }

        local function runComparison(expected)
            plugin:loadComparison(request)
            assert.are.equal(translated("Downloading comparison…"), shown[1].text)
            assert.are.equal(1, #pending)
            pending[1]()
            assert.are.equal(shown[1], closed[1])
            assert.are.equal(2, #shown)
            assert.are.equal(translated(expected), shown[2].text)
        end

        for _, exists in ipairs({ false, true }) do
            it("shows a returned API error when key existence is " .. tostring(exists), function()
                read_result = { exists = exists, token = exists and "secret" or nil }
                package.loaded.github_client.compare = function(_, actual_request, token)
                    assert.are.equal(request, actual_request)
                    assert.are.equal(read_result.token, token)
                    return nil, nil, "GitHub returned HTTP 404."
                end
                runComparison("The comparison failed: GitHub returned HTTP 404.")
            end)
        end

        it("shows key read errors without calling GitHub", function()
            read_result = { exists = false, error = "permission denied" }
            package.loaded.github_client.compare = function() error("must not call GitHub") end
            runComparison("The GitHub API key could not be read: permission denied")
        end)

        it("shows unexpected client errors", function()
            package.loaded.github_client.compare = function() error("network failure", 0) end
            runComparison("The comparison failed: network failure")
        end)

        it("shows parser errors", function()
            package.loaded.github_client.compare = function() return "diff text", {} end
            package.loaded.diff_parser.parse = function() error("invalid patch", 0) end
            runComparison("The diff could not be parsed: invalid patch")
        end)

        it("shows a message for comparisons without file changes", function()
            package.loaded.github_client.compare = function() return "", {} end
            package.loaded.diff_parser.parse = function() return { files = {} } end
            runComparison("These revisions do not contain any file changes.")
        end)
    end)

    it("prefills a ZenPM comparison without reusing unrelated saved revisions", function()
        plugin:openCompareDialog {
            owner = "example",
            repo = "plugin",
            base_ref = "v1",
            head_ref = "v2",
        }

        assert.are.equal(1, #shown)
        local fields = shown[1].fields
        assert.are.equal("example", fields[1].text)
        assert.are.equal("plugin", fields[2].text)
        assert.are.equal("v1", fields[3].text)
        assert.are.equal("v2", fields[4].text)
        assert.is_true(shown[1].keyboard_shown)
    end)

    it("keeps unknown ZenPM revisions empty", function()
        plugin:openCompareDialog { owner = "example", repo = "plugin" }

        assert.are.equal("", shown[1].fields[3].text)
        assert.are.equal("", shown[1].fields[4].text)
    end)

    it("still uses saved fields when opened from the Tools menu", function()
        local previous = plugin.settings
        plugin.settings = {
            readSetting = function(_, key) return "saved_" .. key end,
        }
        plugin:openCompareDialog()
        plugin.settings = previous

        assert.are.equal("saved_last_owner", shown[1].fields[1].text)
        assert.are.equal("saved_last_repo", shown[1].fields[2].text)
        assert.are.equal("saved_last_base_ref", shown[1].fields[3].text)
        assert.are.equal("saved_last_head_ref", shown[1].fields[4].text)
    end)

    it("translates the dialog when no API key exists", function()
        plugin:openSettingsDialog()

        assertDialog("Enter a GitHub API key")
    end)

    it("translates the dialog without exposing the existing API key", function()
        read_result = { token = "existing-secret", exists = true }

        plugin:openSettingsDialog()

        assertDialog("A key is configured; enter a new key to replace it")
    end)

    it("translates the read error without opening the input dialog", function()
        read_result = { exists = false, error = "permission denied" }

        plugin:openSettingsDialog()

        assert.are.equal(1, #shown)
        assert.are.equal(
            translated("The GitHub API key could not be read: ") .. "permission denied",
            shown[1].text
        )
        assert.is_nil(shown[1].fields)
        assert.is_nil(shown[1].keyboard_shown)
        assert.are.equal(0, #closed)
    end)

    it("translates save errors and leaves the dialog open", function()
        api_key.write = function(path, token)
            assert.are.equal(plugin.github_api_key_file, path)
            assert.are.equal("replacement-secret", token)
            return nil, "disk full"
        end
        plugin:openSettingsDialog()
        local dialog = assertDialog("Enter a GitHub API key")
        dialog.fields[1].text = "  replacement-secret  "

        dialog.buttons[1][3].callback()

        assert.are.equal(2, #shown)
        assert.are.equal(
            translated("The GitHub API key could not be saved: ") .. "disk full",
            shown[2].text
        )
        assert.are.equal(0, #closed)
    end)

    it("translates clear errors and leaves the dialog open", function()
        read_result = { token = "existing-secret", exists = true }
        api_key.clear = function(path)
            assert.are.equal(plugin.github_api_key_file, path)
            return nil, "read-only filesystem"
        end
        plugin:openSettingsDialog()
        local dialog = assertDialog("A key is configured; enter a new key to replace it")

        dialog.buttons[1][2].callback()

        assert.are.equal(2, #shown)
        assert.are.equal(
            translated("The GitHub API key could not be cleared: ") .. "read-only filesystem",
            shown[2].text
        )
        assert.are.equal(0, #closed)
    end)
end)
