local gh = require "octo.gh"
local utils = require "octo.utils"

local M = {}

---Fetches current rate limit status from GitHub API
---@param callback function(data: table|nil, error: string|nil)
function M.fetch_rate_limits(callback)
  gh.api.get {
    "/rate_limit",
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          callback(nil, stderr)
          return
        end

        if not output or utils.is_blank(output) then
          callback(nil, "Empty response from GitHub API")
          return
        end

        local success, data = pcall(vim.json.decode, output)
        if not success then
          callback(nil, "Failed to parse rate limit response: " .. tostring(data))
          return
        end

        callback(data, nil)
      end,
    },
  }
end

---Formats a single API's rate limit info
---@param name string Display name of the API
---@param info table Rate limit info with limit, used, remaining, reset fields
---@return string Formatted line
local function format_api_line(name, info)
  local used_pct = math.floor((info.used / info.limit) * 100)
  local remaining_pct = 100 - used_pct
  local reset_time = utils.format_reset_time(info.reset)

  return string.format(
    "%-18s: %5d / %5d (%3d%% remaining) - resets in %s",
    name,
    info.used,
    info.limit,
    remaining_pct,
    reset_time
  )
end

---Formats rate limit data for all APIs
---@param data table Rate limit data from GitHub API
---@return string[] lines Formatted lines for display
---@return table<number, number> line_percentages Map of line number to remaining percentage for coloring
function M.format_rate_limits(data)
  local lines = {}
  local line_percentages = {}

  -- Define display order and names for all APIs
  local api_order = {
    { key = "graphql", name = "GraphQL" },
    { key = "core", name = "REST (core)" },
    { key = "search", name = "Search" },
    { key = "code_search", name = "Code Search" },
    { key = "code_scanning_upload", name = "Code Scanning" },
    { key = "code_scanning_autofix", name = "Code Scan Autofix" },
    { key = "actions_runner_registration", name = "Actions Runner" },
    { key = "integration_manifest", name = "Integration" },
    { key = "source_import", name = "Source Import" },
    { key = "dependency_snapshots", name = "Dependencies" },
    { key = "dependency_sbom", name = "SBOM" },
    { key = "audit_log", name = "Audit Log" },
    { key = "audit_log_streaming", name = "Audit Stream" },
    { key = "scim", name = "SCIM" },
  }

  -- Add each API line and track its remaining percentage
  for _, api in ipairs(api_order) do
    local resource = data.resources[api.key]
    if resource then
      table.insert(lines, format_api_line(api.name, resource))
      local remaining_pct = 100 - math.floor((resource.used / resource.limit) * 100)
      line_percentages[#lines] = remaining_pct
    end
  end

  -- Add footer with help text
  table.insert(lines, "")
  table.insert(lines, "Press q or <C-c> to close")

  return lines, line_percentages
end

---Displays rate limit information in a popup window with color highlighting
function M.show_rate_limits()
  M.fetch_rate_limits(function(data, error)
    if error then
      utils.error("Failed to fetch rate limits: " .. error)
      return
    end

    if not data or not data.resources then
      utils.error "Invalid rate limit data received"
      return
    end

    local lines, line_percentages = M.format_rate_limits(data)

    -- Create buffer and set content
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false

    -- Calculate window dimensions
    local vim_width = vim.o.columns
    local vim_height = vim.o.lines - vim.o.cmdheight
    if vim.o.laststatus ~= 0 then
      vim_height = vim_height - 1
    end

    -- Calculate max line width for window width
    local max_width = 0
    for _, line in ipairs(lines) do
      max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
    end

    -- Window dimensions (exact fit for content)
    local width = math.min(math.floor(vim_width * 0.9), max_width + 4)
    local height = #lines

    -- Center the window
    local row = math.floor((vim_height - height) / 2)
    local col = math.floor((vim_width - width) / 2)

    -- Determine border style
    local border = "rounded"
    if vim.o.winborder ~= "" and vim.o.winborder ~= "none" then
      border = tostring(vim.o.winborder)
    end

    -- Create floating window
    local winid = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      title = "GitHub API Rate Limits",
      border = border,
      row = row,
      col = col,
      width = width,
      height = height,
      style = "minimal",
      focusable = true,
    })

    -- Set window options
    vim.wo[winid].number = false
    vim.wo[winid].relativenumber = false
    vim.wo[winid].cursorline = false
    vim.wo[winid].signcolumn = "no"
    vim.wo[winid].foldcolumn = "0"

    -- Apply color highlighting based on remaining percentage
    for line_num, remaining_pct in pairs(line_percentages) do
      local hl_group
      if remaining_pct > 50 then
        hl_group = "OctoPassingTest" -- Green
      elseif remaining_pct >= 20 then
        hl_group = "OctoPendingTest" -- Yellow
      else
        hl_group = "OctoFailingTest" -- Red
      end

      -- line_num is 1-indexed, nvim_buf_add_highlight expects 0-indexed
      vim.api.nvim_buf_add_highlight(bufnr, -1, hl_group, line_num - 1, 0, -1)
    end

    -- Add close mappings
    local window = require "octo.ui.window"
    vim.keymap.set("n", "q", function()
      window.try_close_wins(winid)
    end, { buffer = bufnr, noremap = true, silent = true, desc = "Close rate limits window" })

    vim.keymap.set("n", "<C-c>", function()
      window.try_close_wins(winid)
    end, { buffer = bufnr, noremap = true, silent = true, desc = "Close rate limits window" })
  end)
end

return M
