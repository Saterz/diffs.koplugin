local Intraline = require("intraline")

local DiffLayout = {}

--- Add intraline segments to corresponding deletion/addition lines.
-- @tparam table deletions ordered deletion lines
-- @tparam table additions ordered addition lines
local function pairChangedLines(deletions, additions)
    local paired_count = math.min(#deletions, #additions)
    for index = 1, paired_count do
        deletions[index].intraline, additions[index].intraline = Intraline.diff(
            deletions[index].content,
            additions[index].content
        )
    end
end

--- Extract one consecutive block of deleted and added lines.
-- @tparam table lines hunk line array
-- @tparam number start_index first changed line
-- @treturn table deletions
-- @treturn table additions
-- @treturn number next unconsumed index
local function collectChangeBlock(lines, start_index)
    local deletions = {}
    local additions = {}
    local index = start_index

    while index <= #lines and lines[index].kind ~= "context" do
        if lines[index].kind == "deletion" then
            table.insert(deletions, lines[index])
        elseif lines[index].kind == "addition" then
            table.insert(additions, lines[index])
        end
        index = index + 1
    end

    pairChangedLines(deletions, additions)
    return deletions, additions, index
end

--- Build rows for a combined (unified) viewer.
-- @tparam table patch parsed patch
-- @treturn table ordered display rows
function DiffLayout.combined(patch)
    local rows = {}

    for _, file in ipairs(patch.files) do
        table.insert(rows, { kind = "file", file = file })
        if file.binary then
            table.insert(rows, { kind = "binary", file = file })
        end

        for _, hunk in ipairs(file.hunks) do
            table.insert(rows, { kind = "hunk", hunk = hunk })
            local index = 1
            while index <= #hunk.lines do
                if hunk.lines[index].kind == "context" then
                    table.insert(rows, { kind = "code", line = hunk.lines[index] })
                    index = index + 1
                else
                    local _, _, next_index = collectChangeBlock(hunk.lines, index)
                    for changed_index = index, next_index - 1 do
                        table.insert(rows, { kind = "code", line = hunk.lines[changed_index] })
                    end
                    index = next_index
                end
            end
        end
    end

    return rows
end

--- Build aligned rows for a side-by-side viewer.
-- @tparam table patch parsed patch
-- @treturn table ordered rows containing `left` and `right` code lines
function DiffLayout.split(patch)
    local rows = {}

    for _, file in ipairs(patch.files) do
        table.insert(rows, { kind = "file", file = file })
        if file.binary then
            table.insert(rows, { kind = "binary", file = file })
        end

        for _, hunk in ipairs(file.hunks) do
            table.insert(rows, { kind = "hunk", hunk = hunk })
            local index = 1
            while index <= #hunk.lines do
                local line = hunk.lines[index]
                if line.kind == "context" then
                    table.insert(rows, { kind = "code", left = line, right = line })
                    index = index + 1
                else
                    local deletions, additions, next_index = collectChangeBlock(hunk.lines, index)
                    local row_count = math.max(#deletions, #additions)
                    for pair_index = 1, row_count do
                        table.insert(rows, {
                            kind = "code",
                            left = deletions[pair_index],
                            right = additions[pair_index],
                        })
                    end
                    index = next_index
                end
            end
        end
    end

    return rows
end

return DiffLayout

