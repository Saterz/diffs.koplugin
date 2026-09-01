local GithubApiKey = require("github_api_key")
describe("GitHub API key storage", function()
    local path

    before_each(function()
        path = os.tmpname()
        os.remove(path)
    end)

    after_each(function()
        os.remove(path)
    end)

    it("reads a trimmed key and reports that the file exists", function()
        assert.is_true(GithubApiKey.write(path, "  github-token  "))
        local key, exists, error_message = GithubApiKey.read(path)

        assert.are.equal("github-token", key)
        assert.is_true(exists)
        assert.is_nil(error_message)
    end)

    it("reports a missing key file", function()
        local key, exists, error_message = GithubApiKey.read(path)

        assert.is_nil(key)
        assert.is_false(exists)
        assert.is_nil(error_message)
    end)

    it("clears an existing key file", function()
        assert.is_true(GithubApiKey.write(path, "github-token"))
        assert.is_true(GithubApiKey.clear(path))

        local key, exists, error_message = GithubApiKey.read(path)
        assert.is_nil(key)
        assert.is_false(exists)
        assert.is_nil(error_message)
    end)
end)
