local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")

local GitHubClient = {
    api_root = "https://api.github.com",
    user_agent = "diffs.koplugin/0.1",
}

--- Percent-encode a value for use as one URL path segment.
-- @tparam string value unescaped value
-- @treturn string percent-encoded value
local function encodePathSegment(value)
    return (value:gsub("([^A-Za-z0-9%-._~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

--- Perform an HTTP GET and collect its response body.
-- @tparam string url absolute request URL
-- @tparam table|nil headers optional string-to-string request headers
-- @treturn string|nil response body
-- @treturn number|nil HTTP status code
-- @treturn string|nil transport error
function GitHubClient:get(url, headers)
    local response_chunks = {}
    local request = {
        url = url,
        method = "GET",
        headers = headers or {},
        sink = ltn12.sink.table(response_chunks),
    }

    request.headers["User-Agent"] = self.user_agent
    request.headers["Accept"] = request.headers["Accept"] or "application/vnd.github+json"
    request.headers["X-GitHub-Api-Version"] = "2022-11-28"

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local ok, status_code = http.request(request)
    socketutil:reset_timeout()

    if not ok then
        return nil, nil, tostring(status_code or "Network request failed.")
    end

    return table.concat(response_chunks), tonumber(status_code), nil
end

--- Download a GitHub comparison and then its unified-diff representation.
-- @tparam table request normalized request from `CompareRequest.fromFields`
-- @treturn string|nil unified diff text
-- @treturn table|nil metadata containing comparison status, commit count, and URL
-- @treturn string|nil user-facing error
function GitHubClient:compare(request)
    local compare_url = string.format(
        "%s/repos/%s/%s/compare/%s...%s",
        self.api_root,
        encodePathSegment(request.owner),
        encodePathSegment(request.repo),
        encodePathSegment(request.base_ref),
        encodePathSegment(request.head_ref)
    )

    local response_body, status_code, transport_error = self:get(compare_url)
    if transport_error then
        return nil, nil, transport_error
    end
    if status_code ~= 200 then
        return nil, nil, string.format("GitHub comparison failed with HTTP %s.", tostring(status_code))
    end

    local decode_ok, comparison = pcall(JSON.decode, response_body)
    if not decode_ok or type(comparison) ~= "table" then
        return nil, nil, "GitHub returned an invalid comparison response."
    end
    if type(comparison.diff_url) ~= "string" or comparison.diff_url == "" then
        return nil, nil, "GitHub did not provide a diff URL for this comparison."
    end

    local diff_body, diff_status, diff_error = self:get(comparison.diff_url, {
        Accept = "application/vnd.github.diff",
    })
    if diff_error then
        return nil, nil, diff_error
    end
    if diff_status ~= 200 then
        return nil, nil, string.format("Downloading the diff failed with HTTP %s.", tostring(diff_status))
    end

    return diff_body, {
        ahead_by = comparison.ahead_by,
        behind_by = comparison.behind_by,
        status = comparison.status,
        total_commits = comparison.total_commits,
        html_url = comparison.html_url,
    }, nil
end

return GitHubClient

