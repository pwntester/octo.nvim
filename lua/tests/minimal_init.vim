set rtp +=.
set rtp +=../plenary.nvim/

lua _G.__is_log = true
lua vim.fn.setenv("DEBUG_PLENARY", true)
runtime! plugin/plenary.vim
runtime! plugin/octo.nvim

lua << EOF
require("plenary/busted")
require("tests/test_utils")
require("octo").setup()
EOF
