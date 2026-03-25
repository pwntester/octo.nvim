local M = {}

---@class HostInfo
---@field state string
---@field active boolean
---@field login string
---@field tokenSource string
---@field scopes string
---@field gitProtocol string

---@class HostResponse
---@field hosts { [string]: HostInfo[] }

--- Returns true if t is a Lua array (integer-keyed from 1), false if it is a dict/object.
---@param t table
---@return boolean
local function is_array(t)
  return t[1] ~= nil or next(t) == nil
end

--- Returns the active HostInfo from a decoded `gh auth status --json hosts` response.
--- Handles both the modern format (host → array of accounts) and the legacy format
--- (host → single account object) produced by older gh CLI versions.
---@param response HostResponse
---@return HostInfo?
local function get_active_info(response)
  for _, accounts in pairs(response.hosts) do
    local entries = (type(accounts) == "table" and is_array(accounts)) and accounts or { accounts }
    for _, host in ipairs(entries) do
      if host.active then
        return host
      end
    end
  end
  return nil
end

--- Returns true if the given scope is present in a comma-separated scopes string.
---@param scopes_str string  e.g. "repo, read:org, read:project"
---@param scope string       e.g. "read:project"
---@return boolean
local function has_scope(scopes_str, scope)
  for _, s in ipairs(vim.split(scopes_str, ", ")) do
    if vim.trim(s) == scope then
      return true
    end
  end
  return false
end

--- Check that require("octo").setup() has been called.
--- Uses the existence of the `:Octo` user command as a proxy, since it is
--- registered as the final step of setup().
---@return boolean
local function check_setup()
  if vim.fn.exists ":Octo" == 2 then
    vim.health.ok "setup() called"
    return true
  end
  vim.health.error("octo.nvim setup() has not been called.", { 'Add require("octo").setup() to your Neovim config.' })
  return false
end

--- Check the running Neovim version against octo.nvim requirements.
local function check_neovim_version()
  if vim.fn.has "nvim-0.10" == 1 then
    vim.health.ok("Neovim >= 0.10 " .. tostring(vim.version()))
  elseif vim.fn.has "nvim-0.7" == 1 then
    vim.health.warn(
      "Neovim < 0.10 — some UI features are disabled (statuscolumn, foldtext).",
      { "Upgrade to Neovim >= 0.10 for full functionality." }
    )
  else
    vim.health.error("Neovim >= 0.7 is required.", { "Upgrade to Neovim >= 0.10 for full functionality." })
  end
end

--- Check that the gh CLI binary is executable and report its version.
local function check_gh_binary()
  local config = require "octo.config"
  local gh_cmd = config.values.gh_cmd
  if vim.fn.executable(gh_cmd) == 1 then
    local version = vim.trim(vim.fn.system(gh_cmd .. " --version"):match "([^\n]+)" or "")
    vim.health.ok(("`%s` found — %s"):format(gh_cmd, version))
  else
    vim.health.error(("`%s` not found."):format(gh_cmd), {
      "Install the GitHub CLI: https://cli.github.com",
      "Or set `gh_cmd` in your octo.nvim config to the correct path.",
    })
  end
end

--- Check that plenary.nvim is installed (required for all gh CLI job execution).
local function check_plenary()
  if pcall(require, "plenary") then
    vim.health.ok "`plenary.nvim` installed"
  else
    vim.health.error(
      "`plenary.nvim` not found.",
      { "Install nvim-lua/plenary.nvim — required for all GitHub API calls." }
    )
  end
end

--- Check that the configured picker plugin is installed.
--- Skips the check when picker = "default" since that uses vim.ui.select.
local function check_picker()
  local config = require "octo.config"
  local picker = config.values.picker
  ---@type table<string, string>
  local picker_module = {
    telescope = "telescope",
    ["fzf-lua"] = "fzf-lua",
    snacks = "snacks",
  }
  local mod = picker_module[picker]
  if mod then
    if pcall(require, mod) then
      vim.health.ok(("`%s` picker installed"):format(picker))
    else
      vim.health.error(
        ("`%s` picker configured but `%s` is not installed."):format(picker, mod),
        { "Install the plugin, or change `picker` in your octo.nvim config." }
      )
    end
  else
    vim.health.info "Using `default` picker (vim.ui.select)"
  end
end

--- Check that nvim-web-devicons is installed when file_panel.use_icons is enabled.
local function check_devicons()
  local config = require "octo.config"
  if not config.values.file_panel.use_icons then
    return
  end
  if pcall(require, "nvim-web-devicons") then
    vim.health.ok "`nvim-web-devicons` installed"
  else
    vim.health.warn(
      "`nvim-web-devicons` not found.",
      { "Install nvim-tree/nvim-web-devicons, or set `file_panel.use_icons = false` in your octo.nvim config." }
    )
  end
end

--- Check GitHub authentication via `gh auth status --json hosts`.
local function check_auth()
  local gh = require "octo.gh"
  local utils = require "octo.utils"

  local data, err = gh.auth.status {
    json = "hosts",
    opts = { mode = "sync" },
  }

  if not utils.is_blank(err) then
    vim.health.error("Error running `gh auth status`: " .. err, { "Run `gh auth login` to authenticate." })
    return
  end

  if data == nil or utils.is_blank(data) then
    vim.health.error("Not authenticated with GitHub.", { "Run `gh auth login` to authenticate." })
    return
  end

  local ok_decode, host_response = pcall(vim.json.decode, data)
  if not ok_decode or not host_response then
    vim.health.error "Failed to parse `gh auth status` response."
    return
  end

  ---@type HostInfo?
  local info = get_active_info(host_response)
  if info == nil then
    vim.health.error("No active GitHub account found.", { "Run `gh auth login` to authenticate." })
    return
  end

  vim.health.ok(("Authenticated as `%s` via %s"):format(info.login, info.tokenSource))
  vim.health.info(("Token scopes: %s"):format(info.scopes))
end

--- Check that the token has the `read:project` scope when Projects v2 is enabled.
local function check_projects_v2_scope()
  local gh = require "octo.gh"
  local utils = require "octo.utils"
  local config = require "octo.config"

  if not config.values.default_to_projects_v2 then
    return
  end

  local data, _ = gh.auth.status {
    json = "hosts",
    opts = { mode = "sync" },
  }

  if data == nil or utils.is_blank(data) then
    return
  end

  local ok_decode, host_response = pcall(vim.json.decode, data)
  if not ok_decode then
    return
  end

  local info = get_active_info(host_response)
  if info == nil then
    return
  end

  local scopes_str = info.scopes or ""
  if not has_scope(scopes_str, "read:project") and not has_scope(scopes_str, "project") then
    vim.health.warn("`default_to_projects_v2` is enabled but token is missing the `read:project` scope.", {
      "Run: gh auth refresh -s read:project",
      "Or set `suppress_missing_scope = { projects_v2 = true }` to silence this.",
    })
  else
    vim.health.ok "Projects v2 scope present"
  end
end

-- ─── Entry point ──────────────────────────────────────────────────────────────

M.check = function()
  vim.health.start "octo.nvim"
  if not check_setup() then
    return
  end

  vim.health.start "Neovim version"
  check_neovim_version()

  vim.health.start "Dependencies"
  check_gh_binary()
  check_plenary()
  check_picker()
  check_devicons()

  vim.health.start "Authentication"
  check_auth()
  check_projects_v2_scope()
end

return M
