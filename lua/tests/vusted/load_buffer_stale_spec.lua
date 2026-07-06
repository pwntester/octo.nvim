---@diagnostic disable
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false

local octo = require "octo"

describe("octo.load_buffer stale callbacks", function()
  local original_load
  local original_create_buffer
  local original_win_set_cursor
  local callbacks
  local create_calls
  local cursor_calls
  local buffers

  local function create_octo_buffer(name)
    local bufnr = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, bufnr)
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_name(bufnr, name or "octo://pwntester/octo.nvim/issue/42")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  local function callback()
    assert(#callbacks == 1, "expected one captured load callback, got " .. #callbacks)
    return callbacks[1]
  end

  before_each(function()
    original_load = octo.load
    original_create_buffer = octo.create_buffer
    original_win_set_cursor = vim.api.nvim_win_set_cursor
    callbacks = {}
    create_calls = {}
    cursor_calls = {}
    buffers = {}

    octo.load = function(repo, kind, id, hostname, cb)
      table.insert(callbacks, {
        repo = repo,
        kind = kind,
        id = tostring(id),
        hostname = hostname,
        cb = cb,
      })
    end

    octo.create_buffer = function(kind, obj, repo, create, hostname)
      table.insert(create_calls, {
        bufnr = vim.api.nvim_get_current_buf(),
        kind = kind,
        obj = obj,
        repo = repo,
        create = create,
        hostname = hostname,
      })
    end
  end)

  after_each(function()
    octo.load = original_load
    octo.create_buffer = original_create_buffer
    vim.api.nvim_win_set_cursor = original_win_set_cursor

    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it("ignores deleted target buffers", function()
    local bufnr = create_octo_buffer()

    octo.load_buffer { bufnr = bufnr }
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local ok, err = pcall(callback().cb, { id = "node-id", number = 42 })

    assert(ok, err)
    assert(#create_calls == 0, "expected no render calls, got " .. #create_calls)
  end)

  it("ignores buffers renamed to a different octo target", function()
    local bufnr = create_octo_buffer()

    octo.load_buffer { bufnr = bufnr }
    vim.api.nvim_buf_set_name(bufnr, "octo://pwntester/octo.nvim/issue/43")

    local ok, err = pcall(callback().cb, { id = "node-id", number = 42 })

    assert(ok, err)
    assert(#create_calls == 0, "expected no render calls, got " .. #create_calls)
  end)

  it("reloads a valid target buffer", function()
    local bufnr = create_octo_buffer()
    vim.api.nvim_win_set_cursor(0, { 2, 1 })

    octo.load_buffer { bufnr = bufnr }
    callback().cb { id = "node-id", number = 42 }

    assert(#create_calls == 1, "expected one render call, got " .. #create_calls)
    assert(create_calls[1].bufnr == bufnr, "expected render in target buffer")
    assert(create_calls[1].kind == "issue", "expected issue kind")
    assert(create_calls[1].repo == "pwntester/octo.nvim", "expected repo to be preserved")

    local cursor = vim.api.nvim_win_get_cursor(0)
    assert(cursor[1] == 2, "expected cursor row 2, got " .. cursor[1])
    assert(cursor[2] == 0, "expected cursor column 0, got " .. cursor[2])
  end)

  it("does not restore cursor when original window no longer shows target buffer", function()
    local bufnr = create_octo_buffer()
    vim.api.nvim_win_set_cursor(0, { 3, 2 })

    octo.load_buffer { bufnr = bufnr }

    local other = create_octo_buffer "octo://pwntester/octo.nvim/issue/99"
    vim.api.nvim_set_current_buf(other)

    vim.api.nvim_win_set_cursor = function(winid, pos)
      table.insert(cursor_calls, { winid = winid, pos = pos })
      return original_win_set_cursor(winid, pos)
    end

    callback().cb { id = "node-id", number = 42 }

    assert(#create_calls == 1, "expected one render call, got " .. #create_calls)
    assert(create_calls[1].bufnr == bufnr, "expected render in target buffer")
    assert(#cursor_calls == 0, "expected no cursor restore calls, got " .. #cursor_calls)
  end)
end)
