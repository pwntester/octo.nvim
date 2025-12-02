local config = require "octo.config"
local vim = vim

local M = {}

---@param hl_group_name string
local function get_fg(hl_group_name)
  return vim.api.nvim_get_hl(0, { name = hl_group_name }).fg
end

---@return OctoConfigColors
local function get_colors()
  local conf = config.values
  return conf.colors
end

---@return table<string, vim.api.keyset.highlight>
local function get_hl_groups()
  local colors = get_colors()
  local float_bg = M.get_background_color_of_highlight_group "NormalFloat"

  return {
    Green = { fg = colors.dark_green },
    Red = { fg = colors.dark_red },
    Purple = { fg = colors.purple },
    Yellow = { fg = colors.yellow },
    Blue = { fg = colors.blue },
    Grey = { fg = colors.grey },

    GreenFloat = { fg = colors.dark_green, bg = float_bg },
    RedFloat = { fg = colors.dark_red, bg = float_bg },
    PurpleFloat = { fg = colors.purple, bg = float_bg },
    YellowFloat = { fg = colors.yellow, bg = float_bg },
    BlueFloat = { fg = colors.blue, bg = float_bg },
    GreyFloat = { fg = colors.grey, bg = float_bg },

    BubbleGreen = { fg = colors.white, bg = colors.dark_green },
    BubbleRed = { fg = colors.white, bg = colors.dark_red },
    BubblePurple = { fg = colors.white, bg = colors.purple },
    BubbleYellow = { fg = colors.grey, bg = colors.yellow },
    BubbleBlue = { fg = colors.grey, bg = colors.dark_blue },
    BubbleGrey = { fg = colors.white, bg = colors.grey },

    BubbleDelimiterGreen = { fg = colors.dark_green },
    BubbleDelimiterRed = { fg = colors.dark_red },
    BubbleDelimiterPurple = { fg = colors.purple },
    BubbleDelimiterYellow = { fg = colors.yellow },
    BubbleDelimiterBlue = { fg = colors.dark_blue },
    BubbleDelimiterGrey = { fg = colors.grey },

    FilePanelTitle = { fg = get_fg "Directory" or colors.blue, bold = true },
    FilePanelCounter = { fg = get_fg "Identifier" or colors.purple, bold = true },
    NormalFloat = { fg = get_fg "Normal" or colors.white },
    Viewer = { fg = colors.black, bg = colors.blue },
    Editable = { bg = float_bg },
    Strikethrough = { fg = colors.grey, strikethrough = true },
    Underline = { fg = colors.white, underline = true },
    Bubble = { fg = colors.white, bg = colors.grey },
  }
end

---@return table<string, string>
local function get_hl_links()
  return {
    Normal = "Normal",
    CursorLine = "CursorLine",
    WinSeparator = "WinSeparator",
    SignColumn = "Normal",
    StatusColumn = "SignColumn",
    StatusLine = "StatusLine",
    StatusLineNC = "StatusLineNC",
    EndOfBuffer = "EndOfBuffer",
    FilePanelFileName = "NormalFloat",
    FilePanelSelectedFile = "Type",
    FilePanelPath = "Comment",
    StatusAdded = "OctoGreen",
    StatusUntracked = "OctoGreen",
    StatusModified = "OctoBlue",
    StatusRenamed = "OctoBlue",
    StatusCopied = "OctoBlue",
    StatusTypeChange = "OctoBlue",
    StatusUnmerged = "OctoBlue",
    StatusUnknown = "OctoYellow",
    StatusDeleted = "OctoRed",
    StatusBroken = "OctoRed",
    Dirty = "OctoRed",
    IssueId = "NormalFloat",
    IssueTitle = "PreProc",
    Float = "NormalFloat",
    TimelineItemHeading = "Comment",
    TimelineMarker = "Identifier",
    Symbol = "Comment",
    Date = "Comment",
    DetailsLabel = "Title",
    DetailsValue = "Identifier",
    MissingDetails = "Comment",
    Empty = "NormalFloat",
    User = "OctoBubble",
    UserViewer = "OctoViewer",
    Reaction = "OctoBubble",
    ReactionViewer = "OctoViewer",
    FailingTest = "OctoRed",
    PassingTest = "OctoGreen",
    PendingTest = "OctoYellow",
    PullAdditions = "OctoGreen",
    PullDeletions = "OctoRed",
    DiffstatAdditions = "OctoGreen",
    DiffstatDeletions = "OctoRed",
    DiffstatNeutral = "OctoGrey",

    StateOpen = "OctoGreen",
    StateClosed = "OctoRed",
    StateCompleted = "OctoPurple",
    StateNotPlanned = "OctoGrey",
    StateDraft = "OctoGrey",
    StateMerged = "OctoPurple",
    StatePending = "OctoYellow",
    StateApproved = "OctoGreen",
    StateChangesRequested = "OctoRed",
    StateDismissed = "OctoRed",
    StateCommented = "OctoBlue",
    StateSubmitted = "OctoGreen",

    StateOpenBubble = "OctoBubbleGreen",
    StateClosedBubble = "OctoBubbleRed",
    StateCompletedBubble = "OctoBubblePurple",
    StateNotPlannedBubble = "OctoBubbleGrey",
    StateDraftBubble = "OctoBubbleGrey",
    StateMergedBubble = "OctoBubblePurple",
    StatePendingBubble = "OctoBubbleYellow",
    StateApprovedBubble = "OctoBubbleGreen",
    StateChangesRequestedBubble = "OctoBubbleRed",
    StateDismissedBubble = "OctoBubbleRed",
    StateCommentedBubble = "OctoBubbleBlue",
    StateSubmittedBubble = "OctoBubbleGreen",

    StateOpenFloat = "OctoGreenFloat",
    StateClosedFloat = "OctoRedFloat",
    StateMergedFloat = "OctoPurpleFloat",
    StateDraftFloat = "OctoGreyFloat",
  }
end

function M.setup()
  for name, hl in pairs(get_hl_groups()) do
    if vim.fn.hlexists("Octo" .. name) == 0 then
      vim.api.nvim_set_hl(0, "Octo" .. name, hl)
    end
  end

  for from, to in pairs(get_hl_links()) do
    if vim.fn.hlexists("Octo" .. from) == 0 then
      vim.api.nvim_set_hl(0, "Octo" .. from, { link = to })
    end
  end
end

local HIGHLIGHT_NAME_PREFIX = "octo"
local HIGHLIGHT_CACHE = {} ---@type table<string, string>
local HIGHLIGHT_MODE_NAMES = {
  background = "mb",
  foreground = "mf",
}

---from https://github.com/norcalli/nvim-colorizer.lua
---@param rgb string
---@param mode "background"|"foreground"
local function make_highlight_name(rgb, mode)
  return table.concat({ HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb }, "_")
end

---@param r integer
---@param g integer
---@param b integer
local function color_is_bright(r, g, b)
  -- Counting the perceptive luminance - human eye favors green color
  local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  if luminance > 0.5 then
    return true -- Bright colors, black font
  else
    return false -- Dark colors, white font
  end
end

---@param highlight_group_name string
function M.get_background_color_of_highlight_group(highlight_group_name)
  local highlight_group = vim.api.nvim_get_hl(0, { name = highlight_group_name, link = false })
  local highlight_group_normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local background_color = highlight_group.bg or highlight_group_normal.bg
  if background_color then
    return string.format("#%06x", background_color)
  end
end

---@param rgb_hex string
---@param options? {mode: "background"|"foreground"}
function M.create_highlight(rgb_hex, options)
  options = options or {}
  local mode = options.mode or "background"
  rgb_hex = rgb_hex:lower()
  rgb_hex = string.gsub(rgb_hex, "^#", "")
  local cache_key = table.concat({ HIGHLIGHT_MODE_NAMES[mode], rgb_hex }, "_")
  local highlight_name = HIGHLIGHT_CACHE[cache_key]
  if not highlight_name then
    if #rgb_hex == 3 then
      rgb_hex = table.concat {
        rgb_hex:sub(1, 1):rep(2),
        rgb_hex:sub(2, 2):rep(2),
        rgb_hex:sub(3, 3):rep(2),
      }
    end
    -- Create the highlight
    highlight_name = make_highlight_name(rgb_hex, mode)
    if mode == "foreground" then
      vim.api.nvim_set_hl(0, highlight_name, { fg = "#" .. rgb_hex })
    else
      local r_str, g_str, b_str = rgb_hex:sub(1, 2), rgb_hex:sub(3, 4), rgb_hex:sub(5, 6)
      local r, g, b = tonumber(r_str, 16), tonumber(g_str, 16), tonumber(b_str, 16)
      local fg_color ---@type string
      if color_is_bright(r, g, b) then
        fg_color = "000000"
      else
        fg_color = "ffffff"
      end
      vim.api.nvim_set_hl(0, highlight_name, { fg = "#" .. fg_color, bg = "#" .. rgb_hex })
    end
    HIGHLIGHT_CACHE[cache_key] = highlight_name
  end
  return highlight_name
end

---@param groups string[]
---@param example_text? string
local function display_highlight_groups(groups, example_text)
  -- Check if input is a table
  if type(groups) ~= "table" then
    print "Please provide a table of highlight group names"
    return
  end

  example_text = example_text or "Sample Text"

  local format_str = "%-30s %-10s %-10s %-10s %-10s %-10s %s"
  -- print(string.format(format_str, "Group", "fg", "bg", "bold", "italic", "underline", "Example"))
  -- print(string.rep("-", 86 + #example_text))
  vim.api.nvim_echo({
    { string.format(format_str, "Group", "fg", "bg", "bold", "italic", "underline", "Example"), "None" },
  }, false, {})
  vim.api.nvim_echo({
    { string.rep("-", 86 + #example_text), "None" },
  }, false, {})

  for _, group_name in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = group_name, link = false })
    if hl then
      local fg = hl.fg and string.format("#%06x", hl.fg) or "none"
      local bg = hl.bg and string.format("#%06x", hl.bg) or "none"
      local bold = hl.bold and "yes" or "no"
      local italic = hl.italic and "yes" or "no"
      local underline = hl.underline and "yes" or "no"

      -- Create a sample text with the highlight applied
      local output = string.format(format_str, group_name, fg, bg, bold, italic, underline, "")

      -- Output the sample with syntax highlighting in a separate line
      vim.api.nvim_echo({
        { output, "None" },
        { example_text, group_name },
      }, false, {})
    else
      vim.api.nvim_echo(
        { { string.format(format_str, group_name, "not found", "", "", "", "", ""), "None" } },
        false,
        {}
      )
    end
  end
end

---@param example_text? string
function M.octo_highlight_groups(example_text)
  local groups = {}
  for v, _ in pairs(get_hl_groups()) do
    table.insert(groups, "Octo" .. v)
  end
  for v, _ in pairs(get_hl_links()) do
    table.insert(groups, "Octo" .. v)
  end

  display_highlight_groups(groups, example_text)
end

return M
