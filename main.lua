local CompareRequest = require("compare_request")
local DiffParser = require("diff_parser")
local DiffView = require("diff_view")
local GitHubClient = require("github_client")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Diffs = WidgetContainer:extend {
    name = "diffs",
    is_doc_only = false,
}

function Diffs:init()
    self.ui.menu:registerToMainMenu(self)
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
        local call_ok, diff_text, metadata, comparison_error = pcall(
            GitHubClient.compare,
            GitHubClient,
            request
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

        local title = string.format(
            "%s/%s  %s…%s",
            request.owner,
            request.repo,
            request.base_ref,
            request.head_ref
        )
        UIManager:show(DiffView:new {
            patch = patch,
            metadata = metadata,
            title = title,
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
                description = _("Repository URL"),
                text = "https://github.com/",
                hint = "https://github.com/owner/repository",
            },
            {
                description = _("Base revision"),
                text = "",
                hint = _("Commit, branch, or tag"),
            },
            {
                description = _("Head revision"),
                text = "",
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
                            fields[1], fields[2], fields[3]
                        )
                        if not request then
                            UIManager:show(InfoMessage:new { text = validation_error })
                            return
                        end
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

--- Add the plugin entry to KOReader's Tools menu.
-- @tparam table menu_items mutable KOReader menu registry
function Diffs:addToMainMenu(menu_items)
    menu_items.diffs = {
        text = _("Diffs"),
        sorting_hint = "more_tools",
        callback = function()
            self:openCompareDialog()
        end,
    }
end

return Diffs
