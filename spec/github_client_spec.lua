describe("GitHubClient", function()
    local client
    local original_json
    local original_http
    local original_socketutil

    setup(function()
        original_json = package.loaded.json
        original_http = package.loaded["socket.http"]
        original_socketutil = package.loaded.socketutil

        package.loaded.json = {
            decode = function(body)
                if body == "comparison" then
                    return {
                        ahead_by = 2,
                        behind_by = 0,
                        diff_url = "https://github.com/owner/repository/compare/base...head.diff",
                        html_url = "https://github.com/owner/repository/compare/base...head",
                        status = "ahead",
                        total_commits = 2,
                    }
                elseif body == "failure" then
                    return { message = "Comparison not found" }
                end
                error("unexpected JSON body")
            end,
        }
        package.loaded["socket.http"] = {}
        package.loaded.socketutil = {}
        package.loaded.github_client = nil
        client = require("github_client")
    end)

    teardown(function()
        package.loaded.github_client = nil
        package.loaded.json = original_json
        package.loaded["socket.http"] = original_http
        package.loaded.socketutil = original_socketutil
    end)

    it("fetches comparison metadata and then its diff URL", function()
        local requests = {}
        client.get = function(_, url, headers)
            table.insert(requests, { url = url, headers = headers })
            if #requests == 1 then
                return "comparison", 200, nil
            end
            return "unified diff", 200, nil
        end

        local diff_text, metadata = assert(client:compare {
            owner = "owner",
            repo = "repository",
            base_ref = "release/1.0",
            head_ref = "main",
        })

        assert.are.equal("unified diff", diff_text)
        assert.are.equal(2, metadata.total_commits)
        assert.are.equal(2, #requests)
        assert.is_truthy(requests[1].url:find("release%2F1.0...main", 1, true))
        assert.are.equal("application/vnd.github.diff", requests[2].headers.Accept)
    end)

    it("sends an optional token with both GitHub requests", function()
        local requests = {}
        client.get = function(_, url, headers)
            table.insert(requests, { url = url, headers = headers })
            if #requests == 1 then
                return "comparison", 200, nil
            end
            return "unified diff", 200, nil
        end

        assert(client:compare({
            owner = "owner",
            repo = "repository",
            base_ref = "base",
            head_ref = "head",
        }, "github-token"))

        assert.are.equal("Bearer github-token", requests[1].headers.Authorization)
        assert.are.equal("Bearer github-token", requests[2].headers.Authorization)
        assert.are.equal("application/vnd.github.diff", requests[2].headers.Accept)
    end)

    it("returns GitHub's error message", function()
        client.get = function()
            return "failure", 404, nil
        end

        local diff_text, metadata, comparison_error = client:compare {
            owner = "owner",
            repo = "repository",
            base_ref = "missing",
            head_ref = "main",
        }

        assert.is_nil(diff_text)
        assert.is_nil(metadata)
        assert.are.equal("Comparison not found", comparison_error)
    end)
end)
