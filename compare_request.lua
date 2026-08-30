local CompareRequest = {}

--- Remove whitespace from both ends of a string.
-- @tparam string value input string
-- @treturn string trimmed string
local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse a normal GitHub repository URL.
-- @tparam string repository_url URL such as https://github.com/owner/repository
-- @treturn table|nil table with `owner` and `repo` string fields
-- @treturn string|nil validation error
function CompareRequest.parseRepositoryUrl(repository_url)
    if type(repository_url) ~= "string" then
        return nil, "Repository URL must be a string."
    end

    local normalized_url = trim(repository_url):gsub("/+$", "")
    local owner, repo = normalized_url:match("^https?://github%.com/([^/]+)/([^/]+)$")
    if not owner or not repo then
        return nil, "Use a GitHub repository URL such as https://github.com/owner/repository."
    end

    repo = repo:gsub("%.git$", "")
    if owner == "" or repo == "" then
        return nil, "The repository owner and name cannot be empty."
    end

    return {
        owner = owner,
        repo = repo,
    }
end

--- Validate and normalize the user's comparison fields.
-- @tparam string repository_url GitHub repository URL
-- @tparam string base_ref base commit SHA, branch, or tag
-- @tparam string head_ref head commit SHA, branch, or tag
-- @treturn table|nil normalized request with `owner`, `repo`, `base_ref`, and `head_ref`
-- @treturn string|nil validation error
function CompareRequest.fromFields(repository_url, base_ref, head_ref)
    local repository, repository_error = CompareRequest.parseRepositoryUrl(repository_url)
    if not repository then
        return nil, repository_error
    end

    base_ref = type(base_ref) == "string" and trim(base_ref) or ""
    head_ref = type(head_ref) == "string" and trim(head_ref) or ""
    if base_ref == "" or head_ref == "" then
        return nil, "Both the base and head references are required."
    end
    if base_ref:find("...", 1, true) or head_ref:find("...", 1, true) then
        return nil, "References cannot contain the comparison separator (...)."
    end

    repository.base_ref = base_ref
    repository.head_ref = head_ref
    return repository
end

return CompareRequest
