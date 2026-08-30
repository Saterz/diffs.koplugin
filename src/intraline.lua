local Intraline = {}

--- Split UTF-8 text into character-sized byte strings.
-- Invalid leading bytes are retained as individual characters.
-- @tparam string text UTF-8 text
-- @treturn table array of character strings
local function toCharacters(text)
    local characters = {}
    local position = 1

    while position <= #text do
        local first_byte = text:byte(position)
        local width = 1
        if first_byte >= 0xF0 and first_byte <= 0xF7 then
            width = 4
        elseif first_byte >= 0xE0 and first_byte <= 0xEF then
            width = 3
        elseif first_byte >= 0xC0 and first_byte <= 0xDF then
            width = 2
        end
        table.insert(characters, text:sub(position, position + width - 1))
        position = position + width
    end

    return characters
end

--- Join a character range, returning an empty string for an empty range.
-- @tparam table characters character array
-- @tparam number first_index inclusive first index
-- @tparam number last_index inclusive last index
-- @treturn string joined range
local function joinRange(characters, first_index, last_index)
    if first_index > last_index then
        return ""
    end

    local result = {}
    for index = first_index, last_index do
        table.insert(result, characters[index])
    end
    return table.concat(result)
end

--- Find the changed character ranges in a deletion/addition pair.
-- The result keeps the shared prefix and suffix outside the emphasized range.
-- @tparam string old_text deleted line content
-- @tparam string new_text added line content
-- @treturn table old segments with `prefix`, `changed`, and `suffix`
-- @treturn table new segments with `prefix`, `changed`, and `suffix`
function Intraline.diff(old_text, new_text)
    local old_characters = toCharacters(old_text)
    local new_characters = toCharacters(new_text)
    local shared_prefix = 0
    local max_prefix = math.min(#old_characters, #new_characters)

    while shared_prefix < max_prefix
        and old_characters[shared_prefix + 1] == new_characters[shared_prefix + 1] do
        shared_prefix = shared_prefix + 1
    end

    local shared_suffix = 0
    local old_remaining = #old_characters - shared_prefix
    local new_remaining = #new_characters - shared_prefix
    local max_suffix = math.min(old_remaining, new_remaining)
    while shared_suffix < max_suffix
        and old_characters[#old_characters - shared_suffix]
            == new_characters[#new_characters - shared_suffix] do
        shared_suffix = shared_suffix + 1
    end

    local old_result = {
        prefix = joinRange(old_characters, 1, shared_prefix),
        changed = joinRange(old_characters, shared_prefix + 1, #old_characters - shared_suffix),
        suffix = joinRange(old_characters, #old_characters - shared_suffix + 1, #old_characters),
    }
    local new_result = {
        prefix = joinRange(new_characters, 1, shared_prefix),
        changed = joinRange(new_characters, shared_prefix + 1, #new_characters - shared_suffix),
        suffix = joinRange(new_characters, #new_characters - shared_suffix + 1, #new_characters),
    }

    return old_result, new_result
end

return Intraline

