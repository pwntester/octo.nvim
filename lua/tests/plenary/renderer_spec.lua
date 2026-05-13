local config = require "octo.config"
local renderer = require "octo.reviews.renderer"
local eq = assert.are.same

describe("reviews renderer", function()
  before_each(function()
    config.values = config.get_default_values()
  end)

  local function render_data()
    return {
      hl = {},
      add_hl = function(self, group, line_idx, first, last)
        table.insert(self.hl, {
          group = group,
          line_idx = line_idx,
          first = first,
          last = last,
        })
      end,
    }
  end

  it("returns blank spacing when file panel icons are disabled", function()
    config.values.file_panel.icons = false

    local data = render_data()

    eq(" ", renderer.get_file_icon("README.md", "md", data, 3, 2))
    eq({}, data.hl)
  end)

  it("uses a custom file panel icon provider", function()
    config.values.file_panel.icons = function(name, ext)
      eq("README.md", name)
      eq("md", ext)
      return "R", "OctoCustomIcon"
    end

    local data = render_data()

    eq("R ", renderer.get_file_icon("README.md", "md", data, 3, 2))
    eq({
      {
        group = "OctoCustomIcon",
        line_idx = 3,
        first = 2,
        last = 4,
      },
    }, data.hl)
  end)

  it("uses nvim-web-devicons when file panel icons are enabled", function()
    package.loaded["nvim-web-devicons"] = {
      get_icon = function(name, ext)
        eq("init.lua", name)
        eq("lua", ext)
        return "L", "DevIconLua"
      end,
    }

    local data = render_data()

    eq("L ", renderer.get_file_icon("init.lua", "lua", data, 5, 1))
    eq({
      {
        group = "DevIconLua",
        line_idx = 5,
        first = 1,
        last = 3,
      },
    }, data.hl)

    package.loaded["nvim-web-devicons"] = nil
  end)
end)
