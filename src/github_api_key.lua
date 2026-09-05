local lfs = require("libs/libkoreader-lfs")

local GithubApiKey = {}

local function trim(value)
    return value:gsub("^%s*(.-)%s*$", "%1")
end

--- Read the API key file.
-- @tparam string path API key file path
-- @treturn string|nil trimmed key, or nil when the file is empty
-- @treturn boolean whether the file exists
-- @treturn string|nil read error
function GithubApiKey.read(path)
    if not lfs.attributes(path) then
        return nil, false, nil
    end

    local file, error_message = io.open(path, "r")
    if not file then
        return nil, true, error_message
    end

    local content = file:read("*a")
    file:close()
    return trim(content or ""), true, nil
end

--- Atomically write the API key file.
-- @tparam string path API key file path
-- @tparam string key API key content
-- @treturn boolean success
-- @treturn string|nil write error
function GithubApiKey.write(path, key)
    if type(key) ~= "string" then
        return false, "GitHub API key must be a string."
    end

    local temporary_path = path .. ".tmp"
    os.remove(temporary_path)

    local file, error_message = io.open(temporary_path, "w")
    if not file then
        return false, error_message
    end

    local write_ok, write_error = file:write(trim(key), "\n")
    if not write_ok then
        file:close()
        os.remove(temporary_path)
        return false, write_error
    end

    file:flush()
    local close_ok, close_error = file:close()
    if not close_ok then
        os.remove(temporary_path)
        return false, close_error
    end

    local rename_ok, rename_error = os.rename(temporary_path, path)
    if not rename_ok then
        os.remove(temporary_path)
        return false, rename_error
    end
    return true, nil
end

--- Remove the API key file.
-- @tparam string path API key file path
-- @treturn boolean success
-- @treturn string|nil deletion error
function GithubApiKey.clear(path)
    if not lfs.attributes(path) then
        return true, nil
    end
    local removed, error_message = os.remove(path)
    if not removed then
        return false, error_message
    end
    return true, nil
end

return GithubApiKey
