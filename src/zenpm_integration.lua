local CompareRequest = require("compare_request")
local _ = require("gettext")

local ZenPMIntegration = {}
local active_plugin
local loader_wrapped = false
local patched_modals
local patched_app

local function revision(value)
    if type(value) ~= "string" or value == "0.0.0" or value:lower() == "source" then
        return ""
    end
    return value
end

--- ZenPM's `repo` is the catalog name, not the upstream GitHub repository.
function ZenPMIntegration.comparisonFields(pkg)
    if type(pkg) ~= "table" or type(pkg.source) ~= "string" then
        return nil
    end
    local owner, repo = pkg.source:match("^https?://github%.com/([^/]+)/([^/%?#]+)/?$")
    local request = CompareRequest.fromFields(owner, repo, "base", "head")
    if not request then
        return nil
    end
    return {
        owner = request.owner,
        repo = request.repo,
        base_ref = pkg.installed and revision(pkg.installed_version) or "",
        head_ref = revision(pkg.latest_release) ~= "" and revision(pkg.latest_release)
            or revision(pkg.github_latest_version) ~= "" and revision(pkg.github_latest_version)
            or revision(pkg.latest_version) ~= "" and revision(pkg.latest_version)
            or revision(pkg.version),
    }
end

local function patchModals()
    local modals = package.loaded["ui/modals"]
    if type(modals) ~= "table" or type(modals.package_modify) ~= "function" or patched_modals == modals then
        return
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")
    local package_modify = modals.package_modify
    modals.package_modify = function(pkg, callbacks, ...)
        local fields = ZenPMIntegration.comparisonFields(pkg)
        if not fields then
            return package_modify(pkg, callbacks, ...)
        end

        -- ZenPM has no menu extension API. Scope the constructor interception to
        -- its synchronous package menu build, restoring it even if that build fails.
        local new = ButtonDialog.new
        local inserted = false
        ButtonDialog.new = function(class, options, ...)
            local dialog
            if not inserted and type(options) == "table" and type(options.buttons) == "table" then
                inserted = true
                table.insert(options.buttons, {
                    {
                        text = _("View changes"),
                        align = "left",
                        callback = function()
                            UIManager:close(dialog)
                            active_plugin:openCompareDialog(fields)
                        end,
                    },
                })
            end
            dialog = new(class, options, ...)
            return dialog
        end
        local ok, result = pcall(package_modify, pkg, callbacks, ...)
        ButtonDialog.new = new
        if not ok then
            error(result, 0)
        end
        return result
    end
    patched_modals = modals
end

local function patchApp(app)
    patchModals()
    if type(app) ~= "table" or type(app.perform_package_action) ~= "function" or patched_app == app then
        return
    end
    local modals = package.loaded["ui/modals"]
    local models = package.loaded.models
    if type(modals) ~= "table" or type(models) ~= "table" then
        return
    end
    local perform_package_action = app.perform_package_action
    app.perform_package_action = function(self, pkg, on_done)
        -- In normal mode ZenPM skips package_modify for pending updates. Offer
        -- the same comparison entry before delegating to that original shortcut.
        if not self.busy and pkg.installed and pkg.update_available and not self.state.advanced
                and ZenPMIntegration.comparisonFields(pkg)
                and not models.is_unmanaged_patch(pkg) and not models.is_installed_patch_item(pkg)
                and not models.is_icon_pack_package(pkg) and not models.is_patch_package(pkg) then
            return modals.package_modify(pkg, {
                update = function()
                    return perform_package_action(self, pkg, on_done)
                end,
            })
        end
        return perform_package_action(self, pkg, on_done)
    end
    patched_app = app
end

--- Called after plugin initialization; ZenPM may not have opened its lazy app yet.
function ZenPMIntegration.install(plugin)
    active_plugin = plugin
    if package.loaded.zenpm_app then
        patchApp(package.loaded.zenpm_app)
    elseif not loader_wrapped and type(package.preload.zenpm_app) == "function" then
        local load_app = package.preload.zenpm_app
        package.preload.zenpm_app = function(...)
            local app = load_app(...)
            patchApp(app)
            return app
        end
        loader_wrapped = true
    end
end

return ZenPMIntegration
