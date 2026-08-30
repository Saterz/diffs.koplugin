local CompareRequest = require("compare_request")

describe("CompareRequest", function()
    it("normalizes comparison fields", function()
        local request = assert(CompareRequest.fromFields(
            " Saterz ",
            " diffs.koplugin.git ",
            " v0.1.0 ",
            " main "
        ))

        assert.are.equal("Saterz", request.owner)
        assert.are.equal("diffs.koplugin", request.repo)
        assert.are.equal("v0.1.0", request.base_ref)
        assert.are.equal("main", request.head_ref)
    end)

    it("rejects slashes in owner and repository fields", function()
        local request, validation_error = CompareRequest.fromFields(
            "owner/repository",
            "repository",
            "base",
            "head"
        )

        assert.is_nil(request)
        assert.is_truthy(validation_error)
    end)

    it("requires both repository fields", function()
        local request, validation_error = CompareRequest.fromFields("owner", "", "base", "head")

        assert.is_nil(request)
        assert.is_truthy(validation_error)
    end)
end)
