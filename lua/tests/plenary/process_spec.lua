---@diagnostic disable
local process = require "octo.process"
local eq = assert.are.same

local function has_value(t, value)
  return vim.tbl_contains(t, value)
end

describe("process.default_transformer", function()
  it("extracts runtime opts from opts namespace", function()
    local args, t_opts = process.default_transformer({ "status" }, {
      short = true,
      [1] = "--porcelain",
      opts = {
        cwd = "/tmp",
        timeout = 100,
        dry_run = true,
      },
    })

    assert.is_true(has_value(args, "status"))
    assert.is_true(has_value(args, "--short"))
    assert.is_true(has_value(args, "--porcelain"))
    assert.is_false(has_value(args, "--opts"))

    eq("/tmp", t_opts.cwd)
    eq(100, t_opts.timeout)
    eq(true, t_opts.dry_run)
  end)

  it("keeps backwards compatibility for _stdin", function()
    local _, t_opts = process.default_transformer({}, {
      _stdin = "payload",
    })

    eq("payload", t_opts.stdin)
  end)

  it("strips args key and auto-inserts -- before its content", function()
    local args, _ = process.default_transformer({ "log" }, {
      oneline = true,
      args = { "--all" },
    })

    assert.is_true(has_value(args, "log"))
    assert.is_true(has_value(args, "--oneline"))
    assert.is_true(has_value(args, "--"))
    assert.is_true(has_value(args, "--all"))
    assert.is_false(has_value(args, "--args"))
  end)

  it("formats string keys in args table as flags after --", function()
    local args, _ = process.default_transformer({ "clone" }, {
      [1] = "owner/repo",
      args = { depth = 1, branch = "main" },
    })

    assert.is_true(has_value(args, "clone"))
    assert.is_true(has_value(args, "owner/repo"))
    local dash_i, depth_i
    for i, v in ipairs(args) do
      if v == "--" then
        dash_i = i
      end
      if v == "--depth" then
        depth_i = i
      end
    end
    assert.is_not_nil(dash_i)
    assert.is_not_nil(depth_i)
    assert.is_true(dash_i < depth_i, "-- must come before --depth")
  end)

  it("strips literal -- from args positional values to avoid double separator", function()
    local args, _ = process.default_transformer({ "log" }, {
      oneline = true,
      args = { "HEAD", "--", "src/" },
    })

    local dashes = {}
    for _, v in ipairs(args) do
      if v == "--" then
        table.insert(dashes, #dashes + 1)
      end
    end
    assert.is_true(has_value(args, "--oneline"))
    assert.is_true(has_value(args, "HEAD"))
    assert.is_true(has_value(args, "src/"))
    eq(1, #dashes, "expected exactly one -- separator")
  end)

  it("does not insert -- for empty args table", function()
    local args, _ = process.default_transformer({ "status" }, {
      short = true,
      args = {},
    })

    assert.is_true(has_value(args, "--short"))
    assert.is_false(has_value(args, "--"))
  end)
end)

describe("process.run", function()
  it("returns sync result outside coroutine", function()
    local result = process.run("sh", { "-c", "printf '{\"ok\":true}'" }, {})
    eq(0, result.code)
    eq('{"ok":true}', result.stdout)
    eq("", result.stderr)
    eq(true, result.json().ok)
    eq('{"ok":true}', result.trim())
  end)

  it("returns result in coroutine flow", function()
    local got
    coroutine.wrap(function()
      got = process.run("sh", { "-c", "printf 'co'" }, {})
    end)()

    vim.wait(2000, function()
      return got ~= nil
    end)

    assert.is_not_nil(got)
    eq(0, got.code)
    eq("co", got.stdout)
  end)

  it("streams complete lines and flushes trailing data", function()
    local streamed = {}
    local completed = false
    local callback_result

    process.run("sh", { "-c", "printf 'a'; printf 'b\\ncd\\nef'" }, {
      stream_cb = function(stdout, _)
        if stdout ~= nil then
          table.insert(streamed, stdout)
        end
      end,
      cb = function(stdout, stderr, code, result)
        callback_result = { stdout = stdout, stderr = stderr, code = code, result = result }
        completed = true
      end,
    })

    vim.wait(2000, function()
      return completed
    end)

    eq({ "ab", "cd", "ef" }, streamed)
    eq(0, callback_result.code)
    eq("ab\ncd\nef", callback_result.stdout)
    eq("", callback_result.stderr)
    eq("ab\ncd\nef", callback_result.result.stdout)
  end)
end)

describe("process.factory", function()
  it("supports dry_run via opts namespace", function()
    local git = process.factory "git"
    local out = git.status {
      short = true,
      opts = {
        cwd = "/tmp",
        dry_run = true,
      },
    }

    eq("git", out.command[1])
    assert.is_true(has_value(out.command, "status"))
    assert.is_true(has_value(out.command, "--short"))
    eq("/tmp", out.opts.cwd)
  end)
end)
