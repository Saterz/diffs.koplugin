describe("ZenPM integration", function()
    local integration
    local originals
    local original_loader
    local modals
    local ButtonDialog
    local original_new
    local shown
    local closed
    local compared
    local plugin

    before_each(function()
        shown, closed, compared = {}, {}, {}
        plugin = {
            openCompareDialog = function(_, fields)
                compared[#compared + 1] = fields
            end,
        }
        ButtonDialog = {
            new = function(_, options)
                return options
            end,
        }
        original_new = ButtonDialog.new
        modals = {
            package_modify = function(_, callbacks)
                local dialog = ButtonDialog:new {
                    buttons = { { { text = "Update", callback = callbacks.update } } },
                }
                shown[#shown + 1] = dialog
                return dialog
            end,
        }
        local stubs = {
            ["ui/widget/buttondialog"] = ButtonDialog,
            ["ui/uimanager"] = {
                close = function(_, dialog)
                    closed[#closed + 1] = dialog
                end,
            },
            models = {
                is_unmanaged_patch = function(pkg) return pkg.unmanaged_patch end,
                is_installed_patch_item = function(pkg) return pkg.patch_asset ~= nil end,
                is_icon_pack_package = function(pkg) return pkg.category == "iconpacks" end,
                is_patch_package = function(pkg) return pkg.category == "patches" end,
            },
            gettext = function(text) return text end,
        }
        originals = {}
        for _, name in ipairs({ "zenpm_integration", "zenpm_app", "ui/modals" }) do
            originals[name] = { package.loaded[name] }
            package.loaded[name] = nil
        end
        for name, stub in pairs(stubs) do
            originals[name] = { package.loaded[name] }
            package.loaded[name] = stub
        end
        original_loader = package.preload.zenpm_app
        package.preload.zenpm_app = nil
        integration = require("zenpm_integration")
    end)

    after_each(function()
        for name, original in pairs(originals) do
            package.loaded[name] = original[1]
        end
        package.preload.zenpm_app = original_loader
    end)

    local function packageInfo()
        return {
            source = "https://github.com/example/plugin.git/",
            repo = "Not the upstream repository",
            installed = true,
            installed_version = "v1.0.0",
            latest_release = "v2.0.0",
            latest_version = "2.0.0",
        }
    end

    local function loadApp()
        package.loaded.zenpm_app = {}
        package.loaded["ui/modals"] = modals
        integration.install(plugin)
    end

    it("does nothing when ZenPM is not installed", function()
        local modify = modals.package_modify
        integration.install(plugin)
        assert.are.equal(modify, modals.package_modify)
        assert.is_nil(package.preload.zenpm_app)
        assert.are.equal(original_new, ButtonDialog.new)
    end)

    it("adds one button without replacing existing actions", function()
        loadApp()
        integration.install(plugin)
        local updated = false
        local dialog = modals.package_modify(packageInfo(), {
            update = function() updated = true end,
        })
        assert.are.equal(2, #dialog.buttons)
        assert.are.equal("View changes", dialog.buttons[2][1].text)
        dialog.buttons[1][1].callback()
        assert.is_true(updated)
        assert.are.equal(original_new, ButtonDialog.new)

        dialog.buttons[2][1].callback()
        assert.are.equal(dialog, closed[1])
        assert.same({
            owner = "example", repo = "plugin", base_ref = "v1.0.0", head_ref = "v2.0.0",
        }, compared[1])
    end)

    it("patches the lazily loaded app without opening it at startup", function()
        local loads = 0
        local app = {}
        package.preload.zenpm_app = function()
            loads = loads + 1
            package.loaded["ui/modals"] = modals
            return app
        end
        integration.install(plugin)
        integration.install(plugin)
        assert.are.equal(0, loads)
        assert.are.equal(app, require("zenpm_app"))
        assert.are.equal(1, loads)
        assert.are.equal(2, #modals.package_modify(packageInfo(), {}).buttons)
    end)

    it("offers comparison before the normal-mode update shortcut", function()
        local performed = {}
        local app = {
            perform_package_action = function(self, pkg, on_done)
                performed = { self, pkg, on_done }
            end,
        }
        package.loaded.zenpm_app = app
        package.loaded["ui/modals"] = modals
        integration.install(plugin)
        local instance = setmetatable({ state = { advanced = false } }, { __index = app })
        local pkg = packageInfo()
        pkg.update_available = true
        local on_done = function() end

        instance:perform_package_action(pkg, on_done)
        assert.same({}, performed)
        assert.are.equal(2, #shown[1].buttons)
        shown[1].buttons[2][1].callback()
        assert.are.equal("v1.0.0", compared[1].base_ref)
        assert.same({}, performed)
        shown[1].buttons[1][1].callback()
        assert.same({ instance, pkg, on_done }, performed)
    end)

    it("preserves advanced, busy, and special-package action handling", function()
        local calls = 0
        local app = {
            perform_package_action = function() calls = calls + 1 end,
        }
        package.loaded.zenpm_app = app
        package.loaded["ui/modals"] = modals
        integration.install(plugin)
        local instance = setmetatable({ state = { advanced = true } }, { __index = app })
        local pkg = packageInfo()
        pkg.update_available = true
        instance:perform_package_action(pkg)
        instance.state.advanced = false
        instance.busy = true
        instance:perform_package_action(pkg)
        instance.busy = false
        pkg.category = "patches"
        instance:perform_package_action(pkg)
        pkg.category = "iconpacks"
        instance:perform_package_action(pkg)
        pkg.category = nil
        pkg.source = "https://gitlab.com/example/plugin"
        instance:perform_package_action(pkg)
        assert.are.equal(5, calls)
        assert.are.equal(0, #shown)
    end)

    it("leaves menus for unsupported or missing sources unchanged", function()
        loadApp()
        for _, source in ipairs({ "", "https://gitlab.com/example/plugin", "https://github.com.evil/a/b",
                "https://github.com/example/plugin/releases/tag/v1", "https://github.com/a/.." }) do
            assert.are.equal(1, #modals.package_modify({ source = source }, {}).buttons)
        end
        assert.are.equal(1, #modals.package_modify({}, {}).buttons)
        assert.is_nil(integration.comparisonFields(nil))
        assert.are.equal(original_new, ButtonDialog.new)
    end)

    it("keeps missing versions blank rather than guessing GitHub tags", function()
        local pkg = packageInfo()
        pkg.installed_version = "0.0.0"
        pkg.latest_release = nil
        pkg.latest_version = nil
        pkg.version = "source"
        local fields = integration.comparisonFields(pkg)
        assert.are.equal("", fields.base_ref)
        assert.are.equal("", fields.head_ref)
        pkg.installed = false
        pkg.installed_version = "v1"
        pkg.github_latest_version = "release/next"
        fields = integration.comparisonFields(pkg)
        assert.are.equal("", fields.base_ref)
        assert.are.equal("release/next", fields.head_ref)
    end)

    it("restores the constructor if ZenPM's menu build fails", function()
        modals.package_modify = function()
            error("menu failure")
        end
        loadApp()
        local ok, err = pcall(modals.package_modify, packageInfo(), {})
        assert.is_false(ok)
        assert.matches("menu failure", err, 1, true)
        assert.are.equal(original_new, ButtonDialog.new)
    end)

    it("uses the current Diffs instance after switching KOReader UIs", function()
        loadApp()
        integration.install({
            openCompareDialog = function() compared.current = true end,
        })
        local dialog = modals.package_modify(packageInfo(), {})
        dialog.buttons[2][1].callback()
        assert.is_true(compared.current)
    end)
end)
