local CompareRequest = {}

--- Remove whitespace from both ends of a string.
---@param value string input string
---@return string trimmed string
local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Validate and normalize the user's comparison fields.
---@param owner string GitHub account or organization name
---@param repo string repository name
---@param base_ref string base commit SHA, branch, or tag
---@param head_ref string head commit SHA, branch, or tag
---@return table|nil normalized request with `owner`, `repo`, `base_ref`, and `head_ref`
---@return string|nil validation error
function CompareRequest.fromFields(owner, repo, base_ref, head_ref)
    owner = type(owner) == "string" and trim(owner) or ""
    repo = type(repo) == "string" and trim(repo):gsub("%.git$", "") or ""
    if owner == "" or repo == "" then
        return nil, "The repository owner and name are required."
    end
    if not owner:match("^[%w][%w-]*$") then
        return nil, "The repository owner contains unsupported characters."
    end
    if not repo:match("^[%w_.-]+$") or repo == "." or repo == ".." then
        return nil, "The repository name contains unsupported characters."
    end

    base_ref = type(base_ref) == "string" and trim(base_ref) or ""
    head_ref = type(head_ref) == "string" and trim(head_ref) or ""
    if base_ref == "" or head_ref == "" then
        return nil, "Both the base and head references are required."
    end
    if base_ref:find("...", 1, true) or head_ref:find("...", 1, true) then
        return nil, "References cannot contain the comparison separator (...)."
    end

    return {
        owner = owner,
        repo = repo,
        base_ref = base_ref,
        head_ref = head_ref,
    }
end

return CompareRequest
