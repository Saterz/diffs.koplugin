local DiffView = require("diff_view")

describe("diff view wrapping", function()
    local function newView(mode)
        local view = setmetatable({
            mode = mode,
            wrap_lines = true,
        }, { __index = DiffView })
        function view:measureCode(text)
            return #text
        end
        function view:codeColumnWidths()
            return 2, 1
        end
        return view
    end

    it("leaves combined continuation number fields blank", function()
        local view = newView("combined")
        local rows = view:visualRows({
            {
                kind = "code",
                line = {
                    kind = "context",
                    content = "abcd",
                    old_line = 123,
                    new_line = 456,
                },
            },
        }, 8, 8)

        assert.are.equal(123, rows[1].line.old_line)
        assert.are.equal(456, rows[1].line.new_line)
        assert.is_nil(rows[2].line.old_line)
        assert.is_nil(rows[2].line.new_line)
        assert.is_true(rows[2].line.continuation)
    end)

    it("leaves split continuation number fields blank", function()
        local view = newView("split")
        local rows = view:visualRows({
            {
                kind = "code",
                left = {
                    kind = "deletion",
                    content = "abcd",
                    old_line = 123,
                },
                right = {
                    kind = "addition",
                    content = "wxyz",
                    new_line = 456,
                },
            },
        }, 8, 16)

        assert.are.equal(123, rows[1].left.old_line)
        assert.are.equal(456, rows[1].right.new_line)
        assert.is_nil(rows[2].left.old_line)
        assert.is_nil(rows[2].right.new_line)
    end)
end)
