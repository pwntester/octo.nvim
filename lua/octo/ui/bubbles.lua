local colors = require "octo.colors"
local config = require "octo.config"

-- A Bubble in the UI is used to make certain elements to visually stand-out.
-- Sometimes they are also called Chips in WebUI framworks. After all they wrap
-- some content (usually text and icons) in a bubble kind-of-shape with a colorful
-- background. The bubble shape gets especially defined by the outer delimiters.
-- An examplary usage in this plugin are for label assigned to an issue.

local function make_bubble(content, highlight_group, opts)
  opts = opts or {}
  local conf = config.get_config()
  local margin = string.rep(" ", opts.margin_width or 0)
  local right_margin = string.rep(" ", opts.right_margin_width or 0)
  local left_margin = string.rep(" ", opts.left_margin_width or 0)
  local padding = string.rep(" ", opts.padding_width or 0)
  local right_padding = string.rep(" ", opts.right_padding_width or 0)
  local left_padding = string.rep(" ", opts.left_padding_width or 0)
  local body = left_padding .. padding .. content .. padding .. right_padding
  local left_delimiter = (left_margin .. margin) .. conf.left_bubble_delimiter
  local right_delimiter = conf.right_bubble_delimiter .. (right_margin .. margin)
  local delimiter_color = colors.get_background_color_of_highlight_group(highlight_group)
  local delimiter_highlight_group = colors.create_highlight(delimiter_color, { mode = "foreground" })

  return {
    { left_delimiter, delimiter_highlight_group },
    { body, highlight_group },
    { right_delimiter, delimiter_highlight_group },
  }
end

local function make_user_bubble(name, is_viewer, opts)
  opts = opts or {}
  local conf = config.get_config()
  local highlight = is_viewer and "OctoUserViewer" or "OctoUser"
  local icon_position = opts.icon_position or "left"
  local icon = conf.user_icon
  icon = opts.icon or icon
  local content
  if icon_position == "left" then
    content = icon .. " " .. name
  elseif icon_position == "right" then
    content = name .. " " .. icon
  end
  return make_bubble(content, highlight, opts)
end

local function make_reaction_bubble(icon, includes_viewer, opts)
  local conf = config.get_config()
  local highlight = includes_viewer and "OctoReactionViewer" or "OctoReaction"
  local hint_for_viewer = includes_viewer and conf.reaction_viewer_hint_icon or ""
  local content = icon .. hint_for_viewer
  return make_bubble(content, highlight, opts)
end

local function make_label_bubble(name, color, opts)
  -- provide a default highlight group incase color is nil.
  local highlight = "NormalFloat"
  if color ~= vim.NIL and color ~= nil then
    highlight = colors.create_highlight(color)
  end
  return make_bubble(name, highlight, opts)
end

return {
  make_bubble = make_bubble,
  make_user_bubble = make_user_bubble,
  make_reaction_bubble = make_reaction_bubble,
  make_label_bubble = make_label_bubble,
}
