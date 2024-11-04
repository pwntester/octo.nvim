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
        "hub.com-alias:pwntester/octo.nvim.git",
      }
      local aliases = {
        ["hub.com"] = "github.com",
        ["hub.com-.*"] = "github.com",
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
      eq(this.parse_remote_url(remote_urls[6], aliases).host, "github.com")
      eq(this.parse_remote_url(remote_urls[6], aliases).repo, "pwntester/octo.nvim")
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
