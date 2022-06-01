local this = require "octo.config"

local function test_setup()
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
  assert(merged_config.default_remote[1] == "remote1", "default_remote[1] should be 'remote1'")
  assert(merged_config.default_remote[2] == "remote2", "default_remote[2] should be 'remote2'")
  assert(merged_config.file_panel.size == 10, "file_panel.size should be 10")
  assert(merged_config.file_panel.use_icons == false, "file_panel.use_icons should be false")
  assert(merged_config.ssh_aliases["remote"] == "host", "ssh_aliases['remote'] should be 'host'")
  assert(merged_config.colors.white == "#AAAAAA", "colors.white should be '#AAAAAA'")
  assert(merged_config.colors.black == "#000000", "colors.black should be '#000000'")
  assert(merged_config.user_icon == "A", "user_icon should be 'A'")
  assert(merged_config.mappings.issue.close_issue.lhs == "<C-x>", "mappings.issue.close_issue.lhs should be '<C-x>'")
  assert(
    merged_config.mappings.issue.close_issue.desc == "Close issue",
    "mappings.issue.close_issue.desc should be 'Close issue'"
  )
  assert(merged_config.mappings.issue.reopen_issue == nil, "mappings.issue.reopen_issue should be nil")
  assert(
    merged_config.mappings.pull_request.merge_pr.lhs == "<space>pm",
    "mappings.pull_request.merge_pr.lhs should be '<space>pm'"
  )
  assert(
    merged_config.mappings.pull_request.merge_pr.desc == "merge commit PR",
    "mappings.pull_request.merge_pr.desc should be 'merge commit PR'"
  )
end

test_setup()
