local CompareRequest = require("compare_request")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
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

                        UIManager:show(InfoMessage:new {
                            text = _("The comparison form is ready. Diff loading is added in the next MVP step."),
                        })
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

