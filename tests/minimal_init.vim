set rtp +=.
set rtp +=../plenary.nvim/

lua _G.__is_log = true
lua vim.fn.setenv("DEBUG_PLENARY", true)
runtime! plugin/plenary.vim
runtime! plugin/octo.nvim

lua << EOF
require("plenary/busted")
vim.cmd[[luafile ./tests/test_utils.lua]]
require("octo").setup()
EOF
