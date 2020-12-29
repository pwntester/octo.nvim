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

function! s:command_complete(...)
  return luaeval('require("octo.commands").command_complete(_A)', a:000)
endfunction

" commands
if executable('gh')
  command! -complete=customlist,s:command_complete -nargs=* Octo :lua require'octo.commands'.octo(<f-args>)
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

" window configuration
let s:no = nvim_win_get_option(0,'number')
let s:rno = nvim_win_get_option(0,'relativenumber')
let s:clo = nvim_win_get_option(0,'cursorline')
let s:sco = nvim_win_get_option(0,'signcolumn')
let s:wo = nvim_win_get_option(0,'wrap')

function! octo#configure_win() abort
  let s:no = nvim_win_get_option(0,'number')
  let s:rno = nvim_win_get_option(0,'relativenumber')
  let s:clo = nvim_win_get_option(0,'cursorline')
  let s:sco = nvim_win_get_option(0,'signcolumn')
  let s:wo = nvim_win_get_option(0,'wrap')

  call nvim_win_set_option(0,'number', v:false)
  call nvim_win_set_option(0,'relativenumber', v:false)
  call nvim_win_set_option(0,'cursorline', v:false)
  call nvim_win_set_option(0,'signcolumn', 'yes')
  call nvim_win_set_option(0,'wrap', v:true)
  
  setlocal omnifunc=octo#issue_complete
endfunction

function! octo#restore_win() abort
  call nvim_win_set_option(0,'number', s:no)
  call nvim_win_set_option(0,'relativenumber', s:rno)
  call nvim_win_set_option(0,'cursorline', s:clo)
  call nvim_win_set_option(0,'signcolumn', s:sco)
  call nvim_win_set_option(0,'wrap', s:wo)
endfunction

" autocommands
augroup octo_autocmds
au!
au Filetype octo_issue call octo#configure_win()
au BufLeave * if &ft == 'octo_issue' | call octo#restore_win() | endif 
au BufReadCmd octo://* lua require'octo'.load_issue()
au BufWriteCmd octo://* lua require'octo'.save_issue()
augroup END

" sign definitions
lua require'octo.signs'.setup()

" logged-in user
if !exists("g:octo_loggedin_user")
  let g:octo_loggedin_user = v:null
  lua require'octo'.check_login()
endif

" settings
let g:octo_date_format = get(g:, 'octo_date_format', "%Y %b %d %I:%M %p %Z")
let g:octo_default_remote = ["upstream", "origin"]
"let g:octo_qf_height = 11

let g:loaded_octo = 1


" foo
" bar
