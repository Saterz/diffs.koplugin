local CompareRequest = require("compare_request")
local DataStorage = require("datastorage")
local DiffParser = require("diff_parser")
local DiffPreferences = require("diff_preferences")
local DiffView = require("diff_view")
local GitHubClient = require("github_client")
local GithubApiKey = require("github_api_key")
local lfs = require("libs/libkoreader-lfs")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Diffs = WidgetContainer:extend {
    name = "diffs",
    is_doc_only = false,
    settings_dir = DataStorage:getSettingsDir() .. "/Diffs",
    settings_file = DataStorage:getSettingsDir() .. "/Diffs/settings.lua",
    legacy_settings_file = DataStorage:getSettingsDir() .. "/diffs.lua",
    github_api_key_file = DataStorage:getSettingsDir() .. "/Diffs/github_api.key",
}

local LEGACY_SETTING_KEYS = {
    "last_owner",
    "last_repo",
    "last_base_ref",
    "last_head_ref",
    "wrap_lines",
    "layout_mode",
    "portrait_mode",
    "show_scrollbar",
}

function Diffs:migrateLegacySettings()
    if not lfs.attributes(self.legacy_settings_file) then
        return
    end

    local legacy_settings = LuaSettings:open(self.legacy_settings_file)
    for _, key in ipairs(LEGACY_SETTING_KEYS) do
        if self.settings:readSetting(key) == nil then
            local value = legacy_settings:readSetting(key)
            if value ~= nil then
                self.settings:saveSetting(key, value)
            end
        end
    end

    local _, key_file_exists, key_error = GithubApiKey.read(self.github_api_key_file)
    assert(not key_error, "Unable to read GitHub API key file: " .. tostring(key_error))
    if not key_file_exists then
        local legacy_token = legacy_settings:readSetting("github_api_token")
        if legacy_token ~= nil then
            local write_ok, write_error = GithubApiKey.write(self.github_api_key_file, legacy_token)
            assert(write_ok, "Unable to migrate GitHub API key: " .. tostring(write_error))
        end
    end

    self.settings:flush()
    local removed, remove_error = os.remove(self.legacy_settings_file)
    assert(removed, "Unable to remove legacy settings file: " .. tostring(remove_error))
end

function Diffs:init()
    local directory = lfs.attributes(self.settings_dir)
    if not directory then
        local created, create_error = lfs.mkdir(self.settings_dir)
        assert(created, "Unable to create Diffs settings directory: " .. tostring(create_error))
    elseif directory.mode ~= "directory" then
        error("Diffs settings path is not a directory: " .. self.settings_dir)
    end

    self.settings = LuaSettings:open(self.settings_file)
    self:migrateLegacySettings()
    self.preferences = DiffPreferences.load(self.settings)
    self.ui.menu:registerToMainMenu(self)
end

--- Store a viewer preference immediately so it survives a KOReader restart.
function Diffs:savePreference(key, value)
    self.preferences[key] = value
    self.settings:saveSetting(key, value):flush()
end

--- Download, parse, and display a validated comparison.
-- @tparam table request normalized comparison request
function Diffs:loadComparison(request)
    if NetworkMgr:willRerunWhenOnline(function()
        self:loadComparison(request)
    end) then
        return
    end

    local loading_message = InfoMessage:new {
        text = _("Downloading comparison…"),
        dismissable = false,
    }
    UIManager:show(loading_message)

    UIManager:nextTick(function()
        local token, _, token_error = GithubApiKey.read(self.github_api_key_file)
        if token_error then
            UIManager:close(loading_message)
            UIManager:show(InfoMessage:new {
                text = _("The GitHub API key could not be read: ") .. tostring(token_error),
            })
            return
        end

        local call_ok, diff_text, metadata, comparison_error = pcall(
            GitHubClient.compare,
            GitHubClient,
            request,
            token
        )
        UIManager:close(loading_message)

        if not call_ok then
            UIManager:show(InfoMessage:new {
                text = _("The comparison failed: ") .. tostring(diff_text),
            })
            return
        end
        if not diff_text then
            UIManager:show(InfoMessage:new {
                text = _("The comparison failed: ") .. tostring(comparison_error),
            })
            return
        end

        local parse_ok, patch = pcall(DiffParser.parse, diff_text)
        if not parse_ok then
            UIManager:show(InfoMessage:new {
                text = _("The diff could not be parsed: ") .. tostring(patch),
            })
            return
        end
        if #patch.files == 0 then
            UIManager:show(InfoMessage:new {
                text = _("These revisions do not contain any file changes."),
            })
            return
        end

        UIManager:show(DiffView:new {
            patch = patch,
            metadata = metadata,
            plugin_path = self.path,
            title = string.format("%s/%s", request.owner, request.repo),
            comparison_title = string.format("%s → %s", request.base_ref, request.head_ref),
            preferences = self.preferences,
            on_preference_change = function(key, value)
                self:savePreference(key, value)
            end,
        })
    end)
end

--- Open the form used to define a GitHub comparison.
function Diffs:openCompareDialog()
    local dialog
    dialog = MultiInputDialog:new {
        title = _("Compare GitHub revisions"),
        fields = {
            {
                description = _("Repository owner"),
                text = self.settings:readSetting("last_owner") or "",
                hint = _("Account or organization"),
            },
            {
                description = _("Repository name"),
                text = self.settings:readSetting("last_repo") or "",
                hint = _("Name only"),
            },
            {
                description = _("Base revision"),
                text = self.settings:readSetting("last_base_ref") or "",
                hint = _("Commit, branch, or tag"),
            },
            {
                description = _("Head revision"),
                text = self.settings:readSetting("last_head_ref") or "",
                hint = _("Commit, branch, or tag"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Compare"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local request, validation_error = CompareRequest.fromFields(
                            fields[1], fields[2], fields[3], fields[4]
                        )
                        if not request then
                            UIManager:show(InfoMessage:new { text = validation_error })
                            return
                        end
                        self.settings
                            :saveSetting("last_owner", request.owner)
                            :saveSetting("last_repo", request.repo)
                            :saveSetting("last_base_ref", request.base_ref)
                            :saveSetting("last_head_ref", request.head_ref)
                            :flush()
                        UIManager:close(dialog)
                        self:loadComparison(request)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Open the dialog used to configure the GitHub API token.
function Diffs:openSettingsDialog()
    local _, key_file_exists, key_error = GithubApiKey.read(self.github_api_key_file)
    if key_error then
        UIManager:show(InfoMessage:new {
            text = _("The GitHub API key could not be read: ") .. tostring(key_error),
        })
        return
    end

    local dialog
    dialog = MultiInputDialog:new {
        title = _("GitHub API key"),
        fields = {
            {
                description = _("API key"),
                text = "",
                hint = key_file_exists
                    and _("A key is configured; enter a new key to replace it")
                    or _("Enter a GitHub API key"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        local clear_ok, clear_error = GithubApiKey.clear(self.github_api_key_file)
                        if not clear_ok then
                            UIManager:show(InfoMessage:new {
                                text = _("The GitHub API key could not be cleared: ") .. tostring(clear_error),
                            })
                            return
                        end
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local token = fields[1]:match("^%s*(.-)%s*$")
                        if token == "" then
                            UIManager:close(dialog)
                            return
                        end

                        local write_ok, write_error = GithubApiKey.write(self.github_api_key_file, token)
                        if not write_ok then
                            UIManager:show(InfoMessage:new {
                                text = _("The GitHub API key could not be saved: ") .. tostring(write_error),
                            })
                            return
                        end
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Add the plugin entry to KOReader's Tools menu.
-- @tparam table menu_items mutable KOReader menu registry
function Diffs:addToMainMenu(menu_items)
    menu_items.diffs = {
        text = _("Diffs"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Compare"),
                callback = function()
                    self:openCompareDialog()
                end,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("GitHub API key"),
                        callback = function()
                            self:openSettingsDialog()
                        end,
                    },
                },
            },
        },
    }
end

return Diffs
