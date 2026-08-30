local CompareRequest = require("compare_request")

describe("CompareRequest", function()
    it("parses a GitHub repository URL", function()
        local repository = assert(CompareRequest.parseRepositoryUrl(
            "https://github.com/Saterz/diffs.koplugin.git/"
        ))

        assert.are.equal("Saterz", repository.owner)
        assert.are.equal("diffs.koplugin", repository.repo)
    end)

    it("normalizes comparison fields", function()
        local request = assert(CompareRequest.fromFields(
            "https://github.com/Saterz/diffs.koplugin",
            " v0.1.0 ",
            " main "
        ))

        assert.are.equal("v0.1.0", request.base_ref)
        assert.are.equal("main", request.head_ref)
    end)

    it("rejects non-GitHub URLs", function()
        local request, validation_error = CompareRequest.fromFields(
            "https://example.com/owner/repository",
            "base",
            "head"
        )

        assert.is_nil(request)
        assert.is_truthy(validation_error)
    end)
end)

