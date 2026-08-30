local DiffView = require("diff_view")

describe("diff view wrapping", function()
    local function newView(mode)
        local view = setmetatable({
            mode = mode,
            wrap_lines = true,
        }, { __index = DiffView })
        function view.measureCode(_, text)
            return #text
        end
        function view.codeColumnWidths()
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
                    kind = "addition",
                    content = "abcd",
                    old_line = 123,
                    new_line = 456,
                    intraline = {
                        prefix = "a",
                        changed = "bc",
                        suffix = "d",
                    },
                },
            },
        }, 8, 8)

        assert.are.equal(123, rows[1].line.old_line)
        assert.are.equal(456, rows[1].line.new_line)
        assert.is_nil(rows[2].line.old_line)
        assert.is_nil(rows[2].line.new_line)
        assert.is_true(rows[2].line.continuation)
        assert.are.equal(1, rows[2].line.content_start)
        assert.are.equal("bc", rows[2].line.intraline.changed)
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
                    intraline = {
                        prefix = "a",
                        changed = "bc",
                        suffix = "d",
                    },
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
        assert.are.equal(1, rows[2].left.content_start)
        assert.are.equal("bc", rows[2].left.intraline.changed)
    end)

    it("paints only the changed portion of a wrapped fragment", function()
        local view = newView("combined")
        view.line_height = 10
        view.scroll_column = 0
        local painted
        view:paintIntraline({
            paintRect = function(_, x, y, width, height, color)
                painted = { x = x, y = y, width = width, height = height, color = color }
            end,
        }, 20, 30, 100, {
            content = "bc",
            content_start = 1,
            intraline = { prefix = "a", changed = "bc", suffix = "d" },
        })

        assert.are.equal(20, painted.x)
        assert.are.equal(2, painted.width)
        assert.are.equal(31, painted.y)
        assert.are.equal(8, painted.height)
    end)
end)
