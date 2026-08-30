local DiffParser = require("diff_parser")

describe("DiffParser", function()
    it("parses files, hunks, line numbers, and statistics", function()
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

        assert.are.equal(1, #patch.files)
        local file = patch.files[1]
        assert.are.equal("example.lua", file.old_path)
        assert.are.equal("modified", file.status)
        assert.are.equal(1, file.additions)
        assert.are.equal(1, file.deletions)
        assert.are.equal(7, #file.old_hash)
        assert.are.equal(1, file.hunks[1].lines[1].old_line)
        assert.are.equal(2, file.hunks[1].lines[2].old_line)
        assert.is_nil(file.hunks[1].lines[2].new_line)
        assert.are.equal(2, file.hunks[1].lines[3].new_line)
        assert.are.equal(0, #patch.warnings)
    end)

    it("recognizes additions, deletions, and missing final newlines", function()
        local patch = DiffParser.parse([[
diff --git a/new.txt b/new.txt
new file mode 100644
index 0000000..1111111
--- /dev/null
+++ b/new.txt
@@ -0,0 +1 @@
+hello
\ No newline at end of file
diff --git a/old.txt b/old.txt
deleted file mode 100644
index 1111111..0000000
--- a/old.txt
+++ /dev/null
@@ -1 +0,0 @@
-goodbye
]])

        assert.are.equal("added", patch.files[1].status)
        assert.is_nil(patch.files[1].old_path)
        assert.is_true(patch.files[1].hunks[1].lines[1].no_newline)
        assert.are.equal("deleted", patch.files[2].status)
        assert.is_nil(patch.files[2].new_path)
    end)

    it("preserves rename and unknown metadata", function()
        local patch = DiffParser.parse([[
diff --git a/old name.lua b/new name.lua
similarity index 95%
rename from old name.lua
rename to new name.lua
future-special-header enabled
]])

        local file = patch.files[1]
        assert.are.equal("renamed", file.status)
        assert.are.equal("old name.lua", file.old_path)
        assert.are.equal("new name.lua", file.new_path)
        assert.are.equal(95, file.similarity)
        assert.are.equal("future-special-header enabled", file.unknown_headers[1])
    end)

    it("recognizes binary diffs", function()
        local patch = DiffParser.parse([[
diff --git a/image.png b/image.png
index 1111111..2222222 100644
Binary files a/image.png and b/image.png differ
]])

        assert.is_true(patch.files[1].binary)
        assert.are.equal(0, #patch.files[1].hunks)
    end)
end)
