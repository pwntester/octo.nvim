local Gitlab = require "octo.backend.glab"
local Github = require "octo.backend.gh"

local M = {}

local backend = {
    ["glab"] = Gitlab,
    ["gh"] = Github
}

function M.run(name, opts, cb)
    local cli = "gh"

    if not backend[cli].functions[name] then
        vim.notify(cli .. " don't have " .. name .. " implemmented")
        return
    end

    backend[cli].functions[name](opts, cb)
end

function M.available_executables()
    local available = 0

    for key, _ in pairs(backend) do
        if vim.fn.executable(key) then
            available = available + 1
        end
    end

    return available
end

return M
