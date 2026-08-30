local Blitbuffer = require("ffi/blitbuffer")
local DiffView = require("diff_view")

describe("diff view palette", function()
    it("uses the requested dark intraline shade", function()
        assert.are.equal(Blitbuffer.COLOR_GRAY_B, DiffView._palette.intraline)
    end)

    it("keeps addition and deletion row backgrounds distinct", function()
        assert.are_not.equal(DiffView._palette.addition, DiffView._palette.deletion)
    end)
end)
