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
      eq(this.parse_raw_remote_url(remote_urls[1], "origin", aliases).host, "github.com")
      eq(this.parse_raw_remote_url(remote_urls[1], "origin", aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_raw_remote_url(remote_urls[2], "origin", aliases).host, "github.com")
      eq(this.parse_raw_remote_url(remote_urls[2], "origin", aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_raw_remote_url(remote_urls[3], "origin", aliases).host, "github.com")
      eq(this.parse_raw_remote_url(remote_urls[3], "origin", aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_raw_remote_url(remote_urls[4], "origin", aliases).host, "github.com")
      eq(this.parse_raw_remote_url(remote_urls[4], "origin", aliases).repo, "pwntester/octo.nvim")
      eq(this.parse_raw_remote_url(remote_urls[5], "origin", aliases).host, "github.com")
      eq(this.parse_raw_remote_url(remote_urls[5], "origin", aliases).repo, "pwntester/octo.nvim")
    end)

    it("populate_resolved_remotes adds resolved repo name.", function()
      local remotes = {
        ["origin"] = { name = "origin", resolved = nil, repo = "pwntester/octo.nvim", host = "github.com" },
      }
      local raw_config = { "remote.origin.gh-resolved pwntester/octo_override.nvim" }
      eq(this.populate_resolved_remotes(remotes, raw_config)["origin"].resolved, "pwntester/octo_override.nvim")
    end)

    it("convert_vim_mapping_to_fzf changes vim mappings to fzf mappings", function()
      local utils = require "octo.utils"
      local mappings = {
        ["<C-j>"] = "ctrl-j",
        ["<c-k>"] = "ctrl-k",
        ["<A-J>"] = "alt-j",
        ["<a-k>"] = "alt-k",
        ["<M-Tab>"] = "alt-tab",
        ["<m-UP>"] = "alt-up",
      }

      for vim_mapping, fzf_mapping in pairs(mappings) do
        eq(utils.convert_vim_mapping_to_fzf(vim_mapping), fzf_mapping)
      end
    end)
  end)
end)
