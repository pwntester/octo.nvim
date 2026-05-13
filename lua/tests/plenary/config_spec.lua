local this = require "octo.config"
local eq = assert.are.same

local user_config = {
  default_remote = { "remote1", "remote2" },
  default_merge_method = "rebase",
  file_panel = { icons = false },
  ssh_aliases = {
    ["remote"] = "host",
  },
  colors = {
    white = "#AAAAAA",
  },
  user_icon = "A",
  mappings = {
    issue = {
      close_issue = {
        lhs = "<C-x>",
        desc = "Close issue",
      },
    },
  },
}
this.setup(user_config)
local merged_config = this.values

describe("Config module:", function()
  describe("setup", function() --------------------------------------------------
    it("user configuration overrides defaults.", function()
      eq(merged_config.default_remote[1], "remote1")
      eq(merged_config.default_remote[2], "remote2")
      eq(merged_config.default_merge_method, "rebase")
      eq(merged_config.file_panel.size, 10, "file_panel.size should be 10")
      eq(merged_config.file_panel.icons, false, "file_panel.icons should be false")
      eq(merged_config.ssh_aliases["remote"], "host")
      eq(merged_config.colors.white, "#AAAAAA")
      eq(merged_config.colors.black, "#000000")
      eq(merged_config.user_icon, "A")
    end)
    it("user defined mappings completely overrides defaults.", function()
      eq(merged_config.mappings.issue.close_issue.lhs, "<C-x>")
      eq(merged_config.mappings.issue.close_issue.desc, "Close issue")
      eq(merged_config.mappings.pull_request.merge_pr.lhs, "<localleader>pm")
      eq(merged_config.mappings.pull_request.merge_pr.desc, "merge commit PR")
    end)
  end)

  describe("validation", function()
    before_each(function()
      this.values = this.get_default_values()
    end)

    it("accepts boolean and function file panel icons values", function()
      this.values.file_panel.icons = true
      eq({}, this.validate_config())

      this.values.file_panel.icons = false
      eq({}, this.validate_config())

      this.values.file_panel.icons = function()
        return "x"
      end
      eq({}, this.validate_config())
    end)

    it("rejects invalid file panel icons values", function()
      rawset(this.values.file_panel, "icons", "invalid")

      assert.True(vim.tbl_count(this.validate_config()) ~= 0)
    end)

    it("rejects legacy file panel icon options", function()
      rawset(this.values.file_panel, "use_icons", false)
      rawset(this.values.file_panel, "get_icon", function()
        return "x"
      end)

      local errors = this.validate_config()

      assert.truthy(errors["file_panel.use_icons"])
      assert.truthy(errors["file_panel.get_icon"])
    end)
  end)
end)
