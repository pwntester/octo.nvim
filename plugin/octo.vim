if exists('g:loaded_octo')
  finish
endif

" colors
let g:octo_color_bubble_bg = synIDattr(synIDtrans(hlID("NormalFloat")), "bg#")
let g:octo_color_green = synIDattr(synIDtrans(hlID("DiffAdd")), "fg#")
let g:octo_color_blue = synIDattr(synIDtrans(hlID("DiffChange")), "fg#")
let g:octo_color_red = synIDattr(synIDtrans(hlID("DiffDelete")), "fg#")

if get(g:, 'octo_color_bubble_bg', '') != '' && get(g:, 'octo_color_green', '') != '' && get(g:, 'octo_color_red', '') != ''

  " Bubble colors
  execute('hi! OctoNvimBubbleDelimiter guifg='.g:octo_color_bubble_bg)
  execute('hi! OctoNvimBubbleBody guibg='.g:octo_color_bubble_bg)
  execute('hi! OctoNvimBubbleRed guifg='.g:octo_color_red.' guibg='.g:octo_color_bubble_bg)
  execute('hi! OctoNvimBubbleGreen guifg='.g:octo_color_green.' guibg='.g:octo_color_bubble_bg)

  " Hunks
  execute('hi! OctoNvimDiffHunkPosition guibg='.g:octo_color_bubble_bg)

  " Commented lines
  execute('hi! link OctoNvimCommentLine Visual')

  " Tests
  execute('hi! OctoNvimPassingTest guifg='.g:octo_color_green)
  execute('hi! OctoNvimFailingTest guifg='.g:octo_color_red)

  " PR changes
  execute('hi! OctoNvimPullAdditions guifg='.g:octo_color_green)
  execute('hi! OctoNvimPullDeletions guifg='.g:octo_color_red)
  execute('hi! OctoNvimPullModifications guifg='.g:octo_color_blue)

  " Editable regions
  execute('hi! OctoNvimEditable guibg='.g:octo_color_bubble_bg)
endif

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
function s:configure_octo_buffer() abort
  " issue/pr/comment buffers
  if match(bufname(), "octo://.\\+/.\\+/pull/\\d\\+/file/") == -1
    setlocal omnifunc=octo#issue_complete
    setlocal nonumber norelativenumber nocursorline wrap
    setlocal foldcolumn=3
    setlocal signcolumn=yes
    setlocal fillchars=fold:⠀,foldopen:⠀,foldclose:⠀,foldsep:⠀
    setlocal foldtext=v:lua.OctoFoldText()
    setlocal foldmethod=manual
    setlocal foldenable
    setlocal foldcolumn=3
    setlocal foldlevelstart=99
    setlocal conceallevel=2
    setlocal syntax=markdown
  " file diff buffers
  else
    lua require"octo.signs".place_coment_signs()
  end
endfunction

augroup octo_autocmds
au!
au BufEnter octo://* call s:configure_octo_buffer()
au BufReadCmd octo://* lua require'octo'.load_buffer()
au BufWriteCmd octo://* lua require'octo'.save_buffer()
augroup END

" sign definitions
sign define octo_comment text=❯ texthl=OctoNvimCommentLine linehl=OctoNvimCommentLine 
sign define octo_clean_block_start text=┌ linehl=OctoNvimEditable
sign define octo_clean_block_end text=└ linehl=OctoNvimEditable
sign define octo_dirty_block_start text=┌ texthl=OctoNvimDirty linehl=OctoNvimEditable
sign define octo_dirty_block_end text=└ texthl=OctoNvimDirty linehl=OctoNvimEditable
sign define octo_dirty_block_middle text=│ texthl=OctoNvimDirty linehl=OctoNvimEditable
sign define octo_clean_block_middle text=│ linehl=OctoNvimEditable
sign define octo_clean_line text=[ linehl=OctoNvimEditable
sign define octo_dirty_line text=[ texthl=OctoNvimDirty linehl=OctoNvimEditable

" folds
lua require'octo.folds'

" logged-in user
if !exists("g:octo_loggedin_user")
  let g:octo_loggedin_user = v:null
  lua require'octo'.check_login()
endif

" mappings
nnoremap <Plug>(OctoOpenIssueAtCursor) <cmd>lua require'octo.util'.open_issue_at_cursor()<CR>

" settings
let g:octo_date_format = get(g:, 'octo_date_format', "%Y %b %d %I:%M %p %Z")
let g:octo_default_remote = ["upstream", "origin"]
"let g:octo_qf_height = 11

let g:loaded_octo = 1
