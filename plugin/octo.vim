if !executable('gh') | echom "[Octo] Cannot find `gh` command" | finish | endif
if !has('nvim-0.5') | echom "[Octo] Octo.nvim requires neovim 0.5+" | finish | endif
if exists('g:loaded_octo') | finish | endif

command! -complete=customlist,v:lua.octo_command_complete -nargs=* Octo lua require"octo.commands".octo(<f-args>)
command! -range OctoAddReviewComment lua require"octo.reviews".add_review_comment(false)
command! -range OctoAddReviewSuggestion lua require"octo.reviews".add_review_comment(true)

augroup octo_autocmds
  au!
  au BufEnter octo://* lua require'octo'.configure_octo_buffer()
  au BufReadCmd octo://* lua require'octo'.load_buffer()
  au BufWriteCmd octo://* lua require'octo'.save_buffer()
  au CursorHold octo://* lua require'octo'.on_cursor_hold()
  au CursorHold * lua require'octo.reviews.thread-panel'.show_review_threads()
  au CursorMoved * lua require'octo.reviews.thread-panel'.hide_review_threads()
  au TabClosed * lua require'octo.reviews'.close(tonumber(vim.fn.expand("<afile>")))
  au TabLeave * lua require'octo.reviews'.on_tab_leave()
  au WinLeave * lua require'octo.reviews'.on_win_leave()
augroup END

lua require'octo.colors'.setup()

let g:loaded_octo = 1
