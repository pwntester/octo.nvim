local on_windows = vim.loop.os_uname().version:match "Windows"

local function join_paths(...)
  return table.concat({ ... }, on_windows and "\\" or "/")
end

local package_root = join_paths(vim.env.TEMP or "/tmp", "nvim", "site", "pack")
local install_path = join_paths(package_root, "packer", "start", "packer.nvim")
local compile_path = join_paths(install_path, "plugin", "packer_compiled.lua")

vim.o.runtimepath = vim.env.VIMRUNTIME
vim.o.packpath = vim.fs.dirname(package_root)

local function load_plugins()
  require("packer").startup {
    {
      "wbthomason/packer.nvim",
      -- plugins here
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      --"pwntester/octo.nvim",
      "pwntester/octo.nvim",
    },
    config = {
      package_root = package_root,
      compile_path = compile_path,
    },
  }
  require("packer").sync()
end

local function load_config()
  -- config here
  require("octo").setup {}
end

if vim.fn.isdirectory(install_path) == 0 then
  vim.fn.system { "git", "clone", "https://github.com/wbthomason/packer.nvim", install_path }
  load_plugins()
  vim.api.nvim_create_autocmd("User", {
    pattern = "PackerComplete",
    callback = load_config,
    once = true,
  })
else
  load_plugins()
  load_config()
end
