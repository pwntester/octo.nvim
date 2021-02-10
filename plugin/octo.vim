if exists('g:loaded_octo')
  finish
endif

" colors
let g:octo_bubble_color = synIDattr(synIDtrans(hlID("NormalFloat")), "bg#")
let g:octo_bubble_green = synIDattr(synIDtrans(hlID("DiffAdd")), "fg#")
let g:octo_bubble_red = synIDattr(synIDtrans(hlID("DiffDelete")), "fg#")
execute('hi! OctoNvimBubbleDelimiter guifg='.g:octo_bubble_color)
execute('hi! OctoNvimBubbleBody guibg='.g:octo_bubble_color)
execute('hi! OctoNvimBubbleRed guifg='.g:octo_bubble_red.' guibg='.g:octo_bubble_color)
execute('hi! OctoNvimBubbleGreen guifg='.g:octo_bubble_green.' guibg='.g:octo_bubble_color)
execute('hi! OctoNvimDiffHunkPosition guibg='.g:octo_bubble_color)
execute('hi! link OctoNvimCommentLine Visual')
execute('hi! link OctoNvimPassingTest DiffAdd')
execute('hi! link OctoNvimFailingTest DiffDelete')
execute('hi! link OctoNvimPullAdditions DiffAdd')
execute('hi! link OctoNvimPullDeletions DiffDelete')
execute('hi! link OctoNvimPullModifications DiffChange')

function! s:command_complete(...)
  return luaeval('require("octo.commands").command_complete(_A)', a:000)
endfunction

" commands
if executable('gh')
  command! -complete=customlist,s:command_complete -nargs=* Octo lua require"octo.commands".octo(<f-args>)
  command! -range OctoAddReviewComment lua require"octo.reviews".add_review_comment(false)
  command! -range OctoAddReviewSuggestion lua require"octo.reviews".add_review_comment(true)
else
  echo 'Cannot find `gh` command.'
endif

" clear buffer undo history
function! octo#clear_history() abort
  let old_undolevels = &undolevels
  set undolevels=-1
  exe "normal a \<BS>\<Esc>"
  let &undolevels = old_undolevels
  unlet old_undolevels
endfunction

" completion
function! octo#issue_complete(findstart, base) abort
  return luaeval("require'octo.completion'.issue_complete(_A[1], _A[2])", [a:findstart, a:base])
endfunction

" autocommands
augroup octo_autocmds
au!
au BufEnter octo://* setlocal omnifunc=octo#issue_complete
au BufEnter octo://* lua require"octo".set_octo_win_opts()
au BufLeave octo://* lua require"octo".restore_win_opts()
au BufReadCmd octo://* lua require'octo'.load_buffer()
au BufWriteCmd octo://* lua require'octo'.save_buffer()
au BufWriteCmd octo_comment://* lua require'octo.reviews'.save_review_comment()
augroup END

" sign definitions
lua require'octo.signs'.setup()

" logged-in user
if !exists("g:octo_loggedin_user")
  let g:octo_loggedin_user = v:null
  lua require'octo'.check_login()
endif

" mappings
nnoremap <Plug>(OctoOpenURLAtCursor) <cmd>lua require'octo.util'.open_url_at_cursor()<CR>

" settings
let g:octo_date_format = get(g:, 'octo_date_format', "%Y %b %d %I:%M %p %Z")
let g:octo_default_remote = ["upstream", "origin"]
"let g:octo_qf_height = 11

let g:loaded_octo = 1
