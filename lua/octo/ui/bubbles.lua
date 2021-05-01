local highlights = require "octo.highlights"

-- A Bubble in the UI is used to make certain elements to visually stand-out.
-- Sometimes they are also called Chips in WebUI framworks. After all they wrap
-- some content (usually text and icons) in a bubble kind-of-shape with a colorful
-- background. The bubble shape gets especially defined by the outer delimiters.
-- An examplary usage in this plugin are for label assigned to an issue.

local function make_bubble(content, highlight_group, opts)
  opts = opts or {}
  local margin = string.rep(" ", opts.margin_width or 0)
  local padding = string.rep(" ", opts.padding_width or 0)
  local body = padding .. content .. padding
  local left_delimiter = margin .. (require"octo".settings.bubble_delimiter_left or "")
  local right_delimiter = (require"octo".settings.bubble_delimiter_right or "") .. margin
  local delimiter_color = highlights.get_background_color_of_highlight_group(highlight_group)
  local delimiter_highlight_group = highlights.create_highlight(
    delimiter_color,
    { mode = "foreground" }
  )

  return {
    { left_delimiter, delimiter_highlight_group },
    { body, highlight_group },
    { right_delimiter, delimiter_highlight_group },
  }
end

local function make_user_bubble(name, is_viewer, opts)
  opts = opts or {}
  local highlight = is_viewer and "OctoNvimUserViewer" or "OctoNvimUser"
  local icon_position = opts.icon_position or "left"
  local icon = require"octo".settings.user_icon or ""
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
  local highlight = includes_viewer and "OctoNvimReactionViewer" or "OctoNvimReaction"
  local hint_for_viewer = includes_viewer and (require"octo".settings.reaction_viewer_hint_icon or "") or ""
  local content = icon .. hint_for_viewer
  return make_bubble(content, highlight, opts)
end

local function make_label_bubble(name, color, opts)
  local highlight = highlights.create_highlight(color)
  return make_bubble(name, highlight, opts)
end

return {
  make_bubble = make_bubble,
  make_user_bubble = make_user_bubble,
  make_reaction_bubble = make_reaction_bubble,
  make_label_bubble = make_label_bubble,
}
