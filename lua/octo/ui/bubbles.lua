local vim = vim
local api = vim.api

local constants = require "octo.constants"
local hl = require "octo.highlights"

-- A Bubble in the UI is used to make certain elements to visually stand-out.
-- Sometimes they are also called Chips in WebUI framworks. After all they wrap
-- some content (usually text and icons) in a bubble kind-of-shape with a colorful
-- background. The bubble shape gets especially defined by the outer delimiters.
-- An examplary usage in this plugin are for label assigned to an issue.

local function get_highlight_group_attribute(highlight_group, attribute_name)
  local highlight_definition = api.nvim_get_hl_by_name(highlight_group, true)
  return highlight_definition[attribute_name] or ""
end

local function make_bubble(content, highlight_group, options)
  local options = options or {}
  local margin = string.rep(" ", options.margin_width or 0)
  local padding = string.rep(" ", options.padding_width or 0)
  local left_delimiter = margin .. (vim.g.octo_bubble_delimiter_left or "")
  local right_delimiter = (vim.g.octo_bubble_delimiter_right or "") .. margin
  local delimiter_highlight_group = highlight_group .. "Delimiter"
  local delimiter_foreground = get_highlight_group_attribute(highlight_group, "background")
  local body = padding .. content .. padding

  -- TODO: make use of the highlight module, but incompatible color formatting schemes
  api.nvim_set_hl(constants.OCTO_HIGHLIGHT_NS, delimiter_highlight_group, {
    foreground = delimiter_foreground
  })
  
  return {
    { left_delimiter, delimiter_highlight_group },
    { body, highlight_group },
    { right_delimiter, delimiter_highlight_group },
  }
end

local function make_user_bubble(name, is_viewer, options)
  local highlight = is_viewer and "OctoNvimBubbleViewer" or "OctoNvimBubble"
  local icon = vim.g.octo_icon_user or ""
  local content = icon .. " " .. name
  return make_bubble(content, highlight, options)
end

local function make_label_bubble(name, color, options)
  local highlight = hl.create_highlight(color)
  return make_bubble(name, highlight, options)
end

return {
  make_bubble = make_bubble,
  make_user_bubble = make_user_bubble,
  make_label_bubble = make_label_bubble,
}
