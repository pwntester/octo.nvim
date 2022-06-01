local this = require "octo.utils"

local function test_parse_remote_url()
  local remote_urls = {
    "https://github.com/pwntester/octo.nvim.git",
    "ssh://git@github.com/pwntester/octo.nvim.git",
    "git@github.com:pwntester/octo.nvim.git",
    "git@github.com:pwntester/octo.nvim.git",
    "hub.com:pwntester/octo.nvim.git",
  }
  local aliases = {
    ["hub.com"] = "github.com",
  }
  local passing = true
  for _, url in ipairs(remote_urls) do
    local remote = this.parse_remote_url(url, aliases)
    if not remote then
      passing = false
      break
    end
    if remote.host ~= "github.com" then
      passing = false
      break
    end
    if remote.repo ~= "pwntester/octo.nvim" then
      passing = false
      break
    end
  end
  return passing
end

print(test_parse_remote_url())
