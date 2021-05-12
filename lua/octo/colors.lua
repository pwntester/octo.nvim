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

local function get_bg(hl_group_name)
  return get_hl_attr(hl_group_name, "bg")
end

local function get_gui(hl_group_name)
  return get_hl_attr(hl_group_name, "gui")
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
    FilePanelFileName = { fg = get_fg("Normal") or colors.white },
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
    FilePanelFileName = "Normal",
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

return M
