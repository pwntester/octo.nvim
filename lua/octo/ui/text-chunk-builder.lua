local config = require "octo.config"
local constants = require "octo.constants"
local utils = require "octo.utils"
local bubbles = require "octo.ui.bubbles"
local vim = vim

---@class TextChunkBuilder
---@field chunks [string, string][]
---@field private conf OctoConfig Configuration reference
local TextChunkBuilder = {}
TextChunkBuilder.__index = TextChunkBuilder

---Create a new TextChunkBuilder instance
---@return TextChunkBuilder
function TextChunkBuilder:new()
  return setmetatable({
    chunks = {},
    conf = config.values,
  }, self)
end

---Add a text chunk with optional highlight
---@param text string The text to add
---@param highlight? string Highlight group name (defaults to empty string)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:text(text, highlight)
  table.insert(self.chunks, { text, highlight or "" })
  return self
end

---Add multiple text chunks at once using vt[#vt + 1] pattern
---@param text string The text to add
---@param highlight? string Highlight group name
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:append(text, highlight)
  self.chunks[#self.chunks + 1] = { text, highlight or "" }
  return self
end

---Add an icon with optional highlight
---@param icon string The icon text
---@param highlight? string Highlight group (defaults to OctoTimelineMarker)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:icon(icon, highlight)
  return self:text(icon, highlight or "OctoTimelineMarker")
end

---Add a timeline marker or icon based on config and optional icon name
---Handles the pattern: if use_timeline_icons then icon else marker + EVENT:
---@param icon_name? string Optional icon name from config.timeline_icons (e.g., "commit", "merged")
---@param icon_highlight? string Optional highlight for icon (defaults to OctoTimelineMarker)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:timeline_marker(icon_name, icon_highlight)
  if self.conf.use_timeline_icons and icon_name and self.conf.timeline_icons[icon_name] then
    ---@type string|table
    local icon = self.conf.timeline_icons[icon_name]
    -- Handle both string icons and table icons { text, hl }
    if type(icon) == "table" then
      self:text(icon[1], icon[2])
    else
      self:text(icon, icon_highlight or "OctoTimelineMarker")
    end
  else
    self:text(self.conf.timeline_marker .. " ", "OctoTimelineMarker")
    if not self.conf.use_timeline_icons then
      self:text("EVENT: ", "OctoTimelineItemHeading")
    end
  end
  return self
end

---Add indented timeline marker (for nested comments/threads)
---@param indent_level? integer Indentation level (default: 1)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:indented_marker(indent_level)
  indent_level = indent_level or 1
  local indent = string.rep(" ", indent_level * self.conf.timeline_indent)
  self:text(indent .. self.conf.timeline_marker .. " ", "OctoTimelineMarker")
  return self
end

---Add a user reference with bubble formatting
---@param login string Username
---@param is_viewer? boolean Whether user is current viewer
---@param opts? table Options for bubble creation
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:user(login, is_viewer, opts)
  local bubble = bubbles.make_user_bubble(login, is_viewer, opts)
  return self:extend(bubble)
end

---Add a user with highlight group directly (no bubble)
---Useful for inline user mentions in timeline events
---@param login string Username
---@param is_viewer boolean Whether user is current viewer
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:user_plain(login, is_viewer)
  local hl = is_viewer and "OctoUserViewer" or "OctoUser"
  return self:text(login, hl)
end

---Add an actor with viewer detection
---Handles the common pattern: item.actor.login, item.actor.login == vim.g.octo_viewer
---@param actor {login: string} Actor object with login field
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:actor(actor)
  return self:user_plain(actor.login, actor.login == vim.g.octo_viewer)
end

---Add a label with bubble formatting
---@param name string Label name
---@param color string Label color
---@param opts? table Options for bubble creation
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:label(name, color, opts)
  local bubble = bubbles.make_label_bubble(name, color, opts)
  return self:extend(bubble)
end

---Add a state bubble
---@param state string State name
---@param state_highlight string State highlight group prefix (e.g., "OctoState")
---@param opts? table Options for bubble creation
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:state_bubble(state, state_highlight, opts)
  local bubble = bubbles.make_bubble(state, state_highlight .. "Bubble", opts)
  return self:extend(bubble)
end

---Add a generic bubble
---@param content string Bubble content
---@param highlight string Highlight group
---@param opts? table Options for bubble creation
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:bubble(content, highlight, opts)
  local bubble = bubbles.make_bubble(content, highlight, opts)
  return self:extend(bubble)
end

---Add a reaction with bubble formatting
---@param icon string Reaction icon
---@param has_reacted? boolean Whether current user reacted
---@param opts? table Options for bubble creation
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:reaction(icon, has_reacted, opts)
  local bubble = bubbles.make_reaction_bubble(icon, has_reacted or false, opts)
  return self:extend(bubble)
end

---Add raw chunks (from bubbles or other sources)
---@param chunks [string, string][]
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:extend(chunks)
  vim.list_extend(self.chunks, chunks)
  return self
end

---Add heading text (for timeline items)
---@param text string
---@param highlight? string (defaults to OctoTimelineItemHeading)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:heading(text, highlight)
  return self:text(text, highlight or "OctoTimelineItemHeading")
end

---Add a formatted date
---@param date_str string ISO date string
---@param prefix? string Optional prefix (defaults to " ")
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:date(date_str, prefix)
  prefix = prefix or " "
  return self:text(prefix .. utils.format_date(date_str), "OctoDate")
end

---Add a lock icon if viewer cannot update
---@param viewer_can_update boolean
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:lock_icon(viewer_can_update)
  if not viewer_can_update then
    self:text(" ", "OctoRed")
  end
  return self
end

---Add text conditionally
---@param condition boolean
---@param text string
---@param highlight? string
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:when(condition, text, highlight)
  if condition then
    self:text(text, highlight)
  end
  return self
end

---Add chunks conditionally using a callback
---@param condition boolean
---@param callback fun(builder: TextChunkBuilder): TextChunkBuilder
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:when_fn(condition, callback)
  if condition then
    callback(self)
  end
  return self
end

---Add a space
---@param count? integer Number of spaces (default: 1)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:space(count)
  count = count or 1
  return self:text(string.rep(" ", count))
end

---Add details label (for detail tables)
---@param label string
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:detail_label(label)
  return self:text(label .. ": ", "OctoDetailsLabel")
end

---Add details value
---@param value string|number
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:detail_value(value)
  return self:text(tostring(value), "OctoDetailsValue")
end

---Add missing details value
---@param value string|number
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:detail_missing(value)
  return self:text(tostring(value), "OctoMissingDetails")
end

---Build and return final chunks
---@return [string, string][]
function TextChunkBuilder:build()
  return self.chunks
end

---Write virtual text directly to buffer at specific line
---@param bufnr integer Buffer number
---@param ns integer Namespace ID
---@param line integer Line number (0-indexed)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:write(bufnr, ns, line)
  pcall(
    vim.api.nvim_buf_set_extmark,
    bufnr,
    ns,
    line,
    0,
    { virt_text = self.chunks, virt_text_pos = "overlay", hl_mode = "combine" }
  )
  return self
end

---Write as a timeline event (adds spacing and uses EVENT_VT_NS)
---This is the most common pattern for timeline events
---@param bufnr integer Buffer number
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:write_event(bufnr)
  local line = vim.api.nvim_buf_line_count(bufnr) - 1
  -- Add empty line for spacing
  vim.api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, { "" })
  -- Write virtual text
  self:write(bufnr, constants.OCTO_EVENT_VT_NS, line + 1)
  return self
end

---Add this line to a details table array
---@param details [string, string][][] Array of detail lines
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:write_detail_line(details)
  table.insert(details, self.chunks)
  return self
end

---Clone this builder (shallow copy of chunks)
---@return TextChunkBuilder
function TextChunkBuilder:clone()
  local new = TextChunkBuilder:new()
  new.chunks = vim.deepcopy(self.chunks)
  return new
end

---Reset builder (clear chunks for reuse)
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:reset()
  self.chunks = {}
  return self
end

---Get the current length of chunks
---@return integer
function TextChunkBuilder:length()
  return #self.chunks
end

---Check if builder is empty
---@return boolean
function TextChunkBuilder:is_empty()
  return #self.chunks == 0
end

---Add a state bubble with icon (for issue/PR/discussion states)
---Handles the pattern of: icon + state bubble, optionally followed by draft bubble
---@param state string Display state (e.g., "OPEN", "CLOSED", "MERGED")
---@param state_reason? string State reason for additional context
---@param is_draft? boolean Whether item is a draft
---@param get_icon_fn fun(state: string, state_reason?: string): table|nil Function to get icon config
---@return TextChunkBuilder self for chaining
function TextChunkBuilder:state_with_icon(state, state_reason, is_draft, get_icon_fn)
  local function format_icon_text(icon)
    return icon and icon[1]:match "^(.-)%s*$" .. " " or ""
  end

  local icon_text = format_icon_text(get_icon_fn(state, state_reason))
  local state_text = utils.title_case(utils.remove_underscore(state))
  local state_bubble = bubbles.make_bubble(icon_text .. state_text, utils.state_hl_map[state] .. "Bubble")
  self:extend(state_bubble)

  if is_draft and state ~= "DRAFT" and state ~= "CLOSED" and state ~= "MERGED" then
    self:space()
    local draft_icon_text = format_icon_text(get_icon_fn("DRAFT", nil))
    local draft_bubble = bubbles.make_bubble(draft_icon_text .. "DRAFT", "OctoStateDraftBubble")
    self:extend(draft_bubble)
  end

  return self
end

return TextChunkBuilder
