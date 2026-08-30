local DiffLayout = require("diff_layout")
local DiffParser = require("diff_parser")
local Intraline = require("intraline")

describe("diff layout", function()
    local patch = DiffParser.parse([[
diff --git a/example.lua b/example.lua
index 1111111..2222222 100644
--- a/example.lua
+++ b/example.lua
@@ -1,3 +1,3 @@
 local value = {
-    enabled = false,
+    enabled = true,
 }
]])

    it("finds UTF-8-safe intraline segments", function()
        local old_segments, new_segments = Intraline.diff("café = false", "café = true")

        assert.are.equal("café = ", old_segments.prefix)
        assert.are.equal("fals", old_segments.changed)
        assert.are.equal("tru", new_segments.changed)
        assert.are.equal("e", old_segments.suffix)
    end)

    it("keeps changes sequential in combined mode", function()
        local rows = DiffLayout.combined(patch)

        assert.are.equal("file", rows[1].kind)
        assert.are.equal("hunk", rows[2].kind)
        assert.are.equal("deletion", rows[4].line.kind)
        assert.are.equal("addition", rows[5].line.kind)
        assert.are.equal("fals", rows[4].line.intraline.changed)
    end)

    it("aligns corresponding changes in split mode", function()
        local rows = DiffLayout.split(patch)

        assert.are.equal("deletion", rows[4].left.kind)
        assert.are.equal("addition", rows[4].right.kind)
        assert.are.equal(2, rows[4].left.old_line)
        assert.are.equal(2, rows[4].right.new_line)
    end)
end)

