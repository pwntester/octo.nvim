local this = require "octo.utils"
local eq = assert.are.same

describe("Utils module:", function()
  describe("setup", function() --------------------------------------------------
    it("parse_remote_url supports all schemes and aliases.", function()
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
      eq(this.parse_remote_url(remote_urls[1], aliases).host, "github.com")
      eq(this.parse_remote_url(remote_urls[1], aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_remote_url(remote_urls[2], aliases).host, "github.com")
      eq(this.parse_remote_url(remote_urls[2], aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_remote_url(remote_urls[3], aliases).host, "github.com")
      eq(this.parse_remote_url(remote_urls[3], aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_remote_url(remote_urls[4], aliases).host, "github.com")
      eq(this.parse_remote_url(remote_urls[4], aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_remote_url(remote_urls[5], aliases).host, "github.com")
      eq(this.parse_remote_url(remote_urls[5], aliases).repo, "pwntester/octo.nvim")
    end)
  end)
end)
