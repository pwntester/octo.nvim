---@diagnostic disable
local eq = assert.are.same

-- Runs a fake `gh` that echoes GH_HOST and its args, to check which host octo
-- targets. Needs a POSIX shell, so it is skipped on Windows.
describe("gh host selection:", function()
  if vim.fn.has "win32" == 1 then
    return
  end

  local gh = require "octo.gh"
  local utils = require "octo.utils"
  local config = require "octo.config"
  local fake_gh, orig_gh_cmd, orig_get_remote_host, orig_github_hostname, orig_viewer

  local function run_checks(opts)
    local out = gh.pr.checks { 1, repo = "org/repo", opts = vim.tbl_extend("force", { mode = "sync" }, opts or {}) }
    return out
  end

  local function run_api(opts)
    local out = gh.api.graphql {
      query = "query { viewer { login } }",
      opts = vim.tbl_extend("force", { mode = "sync" }, opts or {}),
    }
    return out
  end

  local function with_octo_buffer(name, fn)
    local prev = vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_set_current_buf(buf)
    local ok, err = pcall(fn)
    vim.api.nvim_set_current_buf(prev)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert(ok, err)
  end

  before_each(function()
    fake_gh = vim.fn.tempname()
    vim.fn.writefile({ "#!/bin/sh", 'echo "GH_HOST=$GH_HOST"', 'echo "$@"' }, fake_gh)
    vim.fn.setfperm(fake_gh, "rwxr-xr-x")

    orig_gh_cmd = config.values.gh_cmd
    orig_github_hostname = config.values.github_hostname
    orig_get_remote_host = utils.get_remote_host
    orig_viewer = vim.g.octo_viewer
    config.values.gh_cmd = fake_gh
    config.values.github_hostname = ""
    utils.get_remote_host = function()
      return "remote.example.com"
    end
    vim.g.octo_viewer = "tester" -- skip the lazy viewer lookup
  end)

  after_each(function()
    config.values.gh_cmd = orig_gh_cmd
    config.values.github_hostname = orig_github_hostname
    utils.get_remote_host = orig_get_remote_host
    vim.g.octo_viewer = orig_viewer
    vim.fn.delete(fake_gh)
  end)

  it("non-api command uses an explicit hostname", function()
    assert.is_truthy(run_checks({ hostname = "ghe.example.com" }):find("GH_HOST=ghe.example.com", 1, true))
  end)

  it("non-api command uses the current octo:// buffer's hostname", function()
    with_octo_buffer("octo://ghe.example.com/org/repo/pull/1", function()
      assert.is_truthy(run_checks():find("GH_HOST=ghe.example.com", 1, true))
    end)
  end)

  it("non-api command falls back to the git remote's host", function()
    assert.is_truthy(run_checks():find("GH_HOST=remote.example.com", 1, true))
  end)

  it("non-api command prefers the buffer host over github_hostname", function()
    config.values.github_hostname = "configured.example.com"
    with_octo_buffer("octo://ghe.example.com/org/repo/pull/1", function()
      assert.is_truthy(run_checks():find("GH_HOST=ghe.example.com", 1, true))
    end)
  end)

  it("a hostless octo:// buffer name does not count as a host", function()
    with_octo_buffer("octo://org/repo/pull/1", function()
      assert.is_truthy(run_checks():find("GH_HOST=remote.example.com", 1, true))
    end)
  end)

  it("api command still passes --hostname, and GH_HOST stays unset", function()
    local out = run_api({ hostname = "ghe.example.com" })
    assert.is_truthy(out:find("--hostname ghe.example.com", 1, true))
    assert.is_truthy(out:find("GH_HOST=\n", 1, true))
  end)

  it("api command uses the current octo:// buffer's hostname", function()
    with_octo_buffer("octo://ghe.example.com/org/repo/pull/1", function()
      assert.is_truthy(run_api():find("--hostname ghe.example.com", 1, true))
    end)
  end)
end)
