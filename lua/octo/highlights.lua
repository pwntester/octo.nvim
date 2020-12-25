local format = string.format

local M = {}
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

function M.create_highlight(rgb_hex, options)
  local mode = options.mode or "background"
  rgb_hex = rgb_hex:lower()
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
      vim.cmd(format("highlight %s guifg=#%s", highlight_name, rgb_hex))
    else
      local r, g, b = rgb_hex:sub(1, 2), rgb_hex:sub(3, 4), rgb_hex:sub(5, 6)
      r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
      local fg_color
      if color_is_bright(r, g, b) then
        fg_color = "000000"
      else
        fg_color = "ffffff"
      end
      vim.cmd(format("highlight %s guifg=#%s guibg=#%s", highlight_name, fg_color, rgb_hex))
    end
    HIGHLIGHT_CACHE[cache_key] = highlight_name
  end
  return highlight_name
end

return M
