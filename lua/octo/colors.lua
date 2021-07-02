local M = {}

local function get_hl_attr(hl_group_name, attr)
  local id = vim.api.nvim_get_hl_id_by_name(hl_group_name)
  if not id then return end

  local value = vim.fn.synIDattr(id, attr)
  if not value or value == "" then return end

  return value
end

local function get_fg(hl_group_name)
  return get_hl_attr(hl_group_name, "fg")
end

local function get_colors()
  return {
    white       = "#ffffff",
    grey        = "#d7dadf",
    black       = "#000000",
    red         = "#fdb8c0",
    dark_red    = "#da3633",
    green       = "#acf2bd",
    dark_green  = "#238636",
    yellow      = "#d3c846",
    dark_yellow = "#735c0f",
    blue        = "#58A6FF",
    dark_blue   = "#0366d6",
    purple      = "#6f42c1",
  }
end


local function get_hl_groups()
  local colors = get_colors()

  return {
    Green = { fg = colors.dark_green },
    Red = { fg = colors.dark_red },
    Purple  = { fg = colors.purple },
    Yellow = { fg = colors.yellow },
    Blue = { fg = colors.blue },
    Grey = { fg = colors.grey},
    BubbleGreen = { fg = colors.green, bg = colors.dark_green },
    BubbleRed = { fg = colors.red, bg = colors.dark_red },
    BubblePurple = { fg = colors.white, bg = colors.purple },
    BubbleYellow = { fg = colors.yellow, bg = colors.dark_yellow },
    BubbleBlue = { fg = colors.blue, bg = colors.dark_blue },
    BubbleDelimiterGreen = { fg = colors.dark_green },
    BubbleDelimiterRed = { fg = colors.dark_red },
    BubbleDelimiterYellow = { fg = colors.dark_yellow },
    BubbleDelimiterBlue = { fg = colors.dark_blue },
    FilePanelTitle = { fg = get_fg("Directory") or colors.blue, gui = "bold" },
    FilePanelCounter = { fg = get_fg("Identifier") or colors.purple, gui = "bold" },
    NormalFront = { fg = get_fg("Normal") or colors.white },
    Viewer = { fg = colors.black, bg = colors.blue },
  }
end

local function get_hl_links()
  return {
    Normal = "Normal",
    CursorLine = "CursorLine",
    VertSplit = "VertSplit",
    SignColumn = "Normal",
    StatusLine = "StatusLine",
    StatusLineNC = "StatusLineNC",
    EndOfBuffer = "EndOfBuffer",
    FilePanelFileName = "NormalFront",
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
    IssueId = "Question",
    IssueTitle = "PreProc",
    Empty = "Comment",
    Float = "NormalFloat",
    TimelineItemHeading = "Comment",
    TimelineMarker = "Identifier",
    Symbol = "Comment",
    Date = "Comment",
    DetailsLabel = "Title",
    DetailsValue = "Identifier",
    MissingDetails = "Comment",
    Editable = "NormalFloat",
    Bubble = "NormalFloat",
    User = "OctoBubble",
    UserViewer = "OctoViewer",
    Reaction = "OctoBubble",
    ReactionViewer = "OctoViewer",
    PassingTest = "OctoGreen",
    FailingTest = "OctoRed",
    DiffstatAdditions = "OctoGreen ",
    DiffstatDeletions = "OctoRed ",
    DiffstatNeutral = "OctoGrey",
    StateOpen = "OctoGreen",
    StateClosed = "OctoRed",
    StateMerged = "OctoPurple",
    StatePending = "OctoYellow",
    StateApproved = "OctoStateOpen",
    StateChangesRequested = "OctoStateClosed",
    StateCommented = "Normal",
    StateDismissed = "OctoStateClosed",
    StateSubmitted = "OctoBubbleGreen",
  }
end

function M.setup()
  for name, v in pairs(get_hl_groups()) do
    local fg = v.fg and " guifg=" .. v.fg or ""
    local bg = v.bg and " guibg=" .. v.bg or ""
    local gui = v.gui and " gui=" .. v.gui or ""
    vim.cmd("hi def Octo" .. name .. fg .. bg .. gui)
  end

  for from, to in pairs(get_hl_links()) do
    vim.cmd("hi def link Octo" .. from .. " " .. to)
  end
end

local HIGHLIGHT_NAME_PREFIX = "octo"
local HIGHLIGHT_CACHE = {}
local HIGHLIGHT_MODE_NAMES = {
  background = "mb",
  foreground = "mf"
}

-- from https://github.com/norcalli/nvim-colorizer.lua
local function make_highlight_name(rgb, mode)
  return table.concat({HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb}, "_")
end

local function color_is_bright(r, g, b)
  -- Counting the perceptive luminance - human eye favors green color
  local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  if luminance > 0.5 then
    return true -- Bright colors, black font
  else
    return false -- Dark colors, white font
  end
end

function M.get_background_color_of_highlight_group(highlight_group_name)
  local highlight_group = vim.api.nvim_get_hl_by_name(highlight_group_name, true)
  local highlight_group_normal = vim.api.nvim_get_hl_by_name("Normal", true)
  local background_color = highlight_group.background or highlight_group_normal.background or highlight_group_normal.foreground
  local background_color_as_hex = "#" .. string.format("%06x", background_color)
  return background_color_as_hex
end

function M.create_highlight(rgb_hex, options)
  options = options or {}
  local mode = options.mode or "background"
  rgb_hex = rgb_hex:lower()
  rgb_hex = string.gsub(rgb_hex, "^#", "")
  local cache_key = table.concat({HIGHLIGHT_MODE_NAMES[mode], rgb_hex}, "_")
  local highlight_name = HIGHLIGHT_CACHE[cache_key]
  if not highlight_name then
    if #rgb_hex == 3 then
      rgb_hex =
        table.concat {
        rgb_hex:sub(1, 1):rep(2),
        rgb_hex:sub(2, 2):rep(2),
        rgb_hex:sub(3, 3):rep(2)
      }
    end
    -- Create the highlight
    highlight_name = make_highlight_name(rgb_hex, mode)
    if mode == "foreground" then
      vim.cmd(string.format("highlight %s guifg=#%s", highlight_name, rgb_hex))
    else
      local r, g, b = rgb_hex:sub(1, 2), rgb_hex:sub(3, 4), rgb_hex:sub(5, 6)
      r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
      local fg_color
      if color_is_bright(r, g, b) then
        fg_color = "000000"
      else
        fg_color = "ffffff"
      end
      vim.cmd(string.format("highlight %s guifg=#%s guibg=#%s", highlight_name, fg_color, rgb_hex))
    end
    HIGHLIGHT_CACHE[cache_key] = highlight_name
  end
  return highlight_name
end

return M
