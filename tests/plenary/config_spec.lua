local this = require "octo.config"
local eq = assert.are.same

local user_config = {
  default_remote = { "remote1", "remote2" },
  file_panel = { use_icons = false },
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
local merged_config = this.setup(user_config)

describe("Config module:", function()
  describe("setup", function() --------------------------------------------------
    it("user configuration overrides defaults.", function()
      eq(merged_config.default_remote[1], "remote1")
      eq(merged_config.default_remote[2], "remote2")
      eq(merged_config.file_panel.size, 10, "file_panel.size should be 10")
      eq(merged_config.file_panel.use_icons, false, "file_panel.use_icons should be false")
      eq(merged_config.ssh_aliases["remote"], "host")
      eq(merged_config.colors.white, "#AAAAAA")
      eq(merged_config.colors.black, "#000000")
      eq(merged_config.user_icon, "A")
    end)
    it("user defined mappings completely overrides defaults.", function()
      eq(merged_config.mappings.issue.close_issue.lhs, "<C-x>")
      eq(merged_config.mappings.issue.close_issue.desc, "Close issue")
      eq(merged_config.mappings.issue.reopen_issue, nil)
      eq(merged_config.mappings.pull_request.merge_pr.lhs, "<space>pm")
      eq(merged_config.mappings.pull_request.merge_pr.desc, "merge commit PR")
    end)
  end)
end)
