local DiffParser = {}

--- Split text into logical lines without returning a sentinel trailing line.
-- @tparam string text text using LF or CRLF line endings
-- @treturn table array of strings without their line terminators
local function splitLines(text)
    local normalized = text:gsub("\r\n", "\n")
    local lines = {}
    local position = 1

    while position <= #normalized do
        local newline = normalized:find("\n", position, true)
        if not newline then
            table.insert(lines, normalized:sub(position))
            break
        end
        table.insert(lines, normalized:sub(position, newline - 1))
        position = newline + 1
    end

    return lines
end

--- Decode the common quoting used for paths in Git diff headers.
-- This deliberately leaves uncommon escape sequences intact instead of losing data.
-- @tparam string path raw Git path
-- @treturn string decoded path
local function decodePath(path)
    if path:sub(1, 1) == '"' and path:sub(-1) == '"' then
        path = path:sub(2, -2)
        path = path:gsub("\\t", "\t")
            :gsub("\\n", "\n")
            :gsub("\\r", "\r")
            :gsub('\\"', '"')
            :gsub("\\\\", "\\")
    end
    return path
end

--- Remove Git's `a/` or `b/` comparison prefixes.
-- @tparam string|nil path raw comparison path
-- @treturn string|nil normalized repository path
local function normalizePath(path)
    if not path or path == "/dev/null" then
        return nil
    end
    path = decodePath(path)
    return (path:gsub("^[ab]/", "", 1))
end

--- Parse the two paths from a `diff --git` line.
-- @tparam string line full header line
-- @treturn string|nil old path
-- @treturn string|nil new path
local function parseDiffPaths(line)
    local payload = line:sub(#"diff --git " + 1)
    local old_path, new_path = payload:match('^(".-")%s+(".-")$')
    if not old_path then
        old_path, new_path = payload:match("^(%S+)%s+(%S+)$")
    end
    return normalizePath(old_path), normalizePath(new_path)
end

--- Read a hunk count, applying the unified-diff default of one.
-- @tparam string value optional numeric count
-- @treturn number parsed count
local function parseCount(value)
    if value == "" then
        return 1
    end
    return tonumber(value)
end

--- Determine a file's status from its parsed metadata.
-- @tparam table file parsed file object
-- @treturn string added, deleted, renamed, copied, or modified
local function determineStatus(file)
    if file.new_file_mode or file.old_path == nil then
        return "added"
    elseif file.deleted_file_mode or file.new_path == nil then
        return "deleted"
    elseif file.rename_from or file.rename_to then
        return "renamed"
    elseif file.copy_from or file.copy_to then
        return "copied"
    end
    return "modified"
end

--- Validate line totals after parsing a hunk.
-- @tparam table hunk parsed hunk
-- @tparam table warnings mutable warning array
local function validateHunk(hunk, warnings)
    if not hunk then
        return
    end

    local parsed_old = 0
    local parsed_new = 0
    for _, line in ipairs(hunk.lines) do
        if line.kind == "context" then
            parsed_old = parsed_old + 1
            parsed_new = parsed_new + 1
        elseif line.kind == "deletion" then
            parsed_old = parsed_old + 1
        elseif line.kind == "addition" then
            parsed_new = parsed_new + 1
        end
    end

    if parsed_old ~= hunk.old_count or parsed_new ~= hunk.new_count then
        table.insert(warnings, string.format(
            "Hunk %s declares %d/%d lines but contains %d/%d.",
            hunk.header,
            hunk.old_count,
            hunk.new_count,
            parsed_old,
            parsed_new
        ))
    end
end

--- Parse a unified Git diff into files, hunks, and numbered lines.
-- Unknown file headers are retained in `headers_raw` and `unknown_headers`.
-- @tparam string diff_text unified diff returned by GitHub
-- @treturn table patch with `files` and `warnings` arrays
function DiffParser.parse(diff_text)
    assert(type(diff_text) == "string", "diff_text must be a string")

    local patch = {
        files = {},
        warnings = {},
    }
    local current_file
    local current_hunk
    local old_line
    local new_line

    local function finishHunk()
        validateHunk(current_hunk, patch.warnings)
        current_hunk = nil
    end

    local function finishFile()
        finishHunk()
        if current_file then
            current_file.status = determineStatus(current_file)
        end
    end

    for _, line in ipairs(splitLines(diff_text)) do
        if line:match("^diff %-%-git ") then
            finishFile()
            local old_path, new_path = parseDiffPaths(line)
            current_file = {
                old_path = old_path,
                new_path = new_path,
                status = "modified",
                binary = false,
                headers_raw = {},
                unknown_headers = {},
                hunks = {},
                additions = 0,
                deletions = 0,
            }
            table.insert(patch.files, current_file)
        elseif current_file then
            local old_start, old_count, new_start, new_count, section =
                line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@%s?(.*)$")

            if old_start then
                finishHunk()
                current_hunk = {
                    header = line,
                    old_start = tonumber(old_start),
                    old_count = parseCount(old_count),
                    new_start = tonumber(new_start),
                    new_count = parseCount(new_count),
                    section = section ~= "" and section or nil,
                    lines = {},
                }
                old_line = current_hunk.old_start
                new_line = current_hunk.new_start
                table.insert(current_file.hunks, current_hunk)
            elseif current_hunk then
                local prefix = line:sub(1, 1)
                local parsed_line
                if prefix == " " then
                    parsed_line = {
                        kind = "context",
                        content = line:sub(2),
                        old_line = old_line,
                        new_line = new_line,
                    }
                    old_line = old_line + 1
                    new_line = new_line + 1
                elseif prefix == "-" then
                    parsed_line = {
                        kind = "deletion",
                        content = line:sub(2),
                        old_line = old_line,
                        new_line = nil,
                    }
                    old_line = old_line + 1
                    current_file.deletions = current_file.deletions + 1
                elseif prefix == "+" then
                    parsed_line = {
                        kind = "addition",
                        content = line:sub(2),
                        old_line = nil,
                        new_line = new_line,
                    }
                    new_line = new_line + 1
                    current_file.additions = current_file.additions + 1
                elseif line == "\\ No newline at end of file" then
                    local previous_line = current_hunk.lines[#current_hunk.lines]
                    if previous_line then
                        previous_line.no_newline = true
                    end
                else
                    table.insert(patch.warnings, "Unrecognized hunk line: " .. line)
                end

                if parsed_line then
                    table.insert(current_hunk.lines, parsed_line)
                end
            else
                table.insert(current_file.headers_raw, line)

                local index_old, index_new, index_mode =
                    line:match("^index ([0-9a-f]+)%.%.([0-9a-f]+)%s?(%d*)$")
                if index_old then
                    current_file.old_hash = index_old
                    current_file.new_hash = index_new
                    current_file.mode = index_mode ~= "" and index_mode or nil
                elseif line:match("^new file mode ") then
                    current_file.new_file_mode = line:match("^new file mode (.+)$")
                elseif line:match("^deleted file mode ") then
                    current_file.deleted_file_mode = line:match("^deleted file mode (.+)$")
                elseif line:match("^old mode ") then
                    current_file.old_mode = line:match("^old mode (.+)$")
                elseif line:match("^new mode ") then
                    current_file.new_mode = line:match("^new mode (.+)$")
                elseif line:match("^similarity index ") then
                    current_file.similarity = tonumber(line:match("(%d+)%%"))
                elseif line:match("^rename from ") then
                    current_file.rename_from = decodePath(line:sub(#"rename from " + 1))
                    current_file.old_path = current_file.rename_from
                elseif line:match("^rename to ") then
                    current_file.rename_to = decodePath(line:sub(#"rename to " + 1))
                    current_file.new_path = current_file.rename_to
                elseif line:match("^copy from ") then
                    current_file.copy_from = decodePath(line:sub(#"copy from " + 1))
                elseif line:match("^copy to ") then
                    current_file.copy_to = decodePath(line:sub(#"copy to " + 1))
                elseif line:match("^%-%-%- ") then
                    current_file.old_path = normalizePath(line:sub(5))
                elseif line:match("^%+%+%+ ") then
                    current_file.new_path = normalizePath(line:sub(5))
                elseif line:match("^Binary files ") or line == "GIT binary patch" then
                    current_file.binary = true
                elseif line ~= "" then
                    table.insert(current_file.unknown_headers, line)
                end
            end
        elseif line ~= "" then
            table.insert(patch.warnings, "Ignored content before first file: " .. line)
        end
    end

    finishFile()
    return patch
end

return DiffParser

