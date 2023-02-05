local M = {}

function M:pull(opts, cb)
    vim.notify("calling pull")
end

M.functions = {
    ["pull"] = M.pull,
}

return M
