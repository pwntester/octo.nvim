if exists('g:loaded_octo')
  finish
endif

" colors
let g:octo_bubble_color = synIDattr(synIDtrans(hlID("NormalFloat")), "bg#")
execute('hi! OctoNvimBubble1 guifg='.g:octo_bubble_color)
execute('hi! OctoNvimBubble2 guibg='.g:octo_bubble_color)

" commands
if executable('gh')
  command! -nargs=* Octo :lua require'octo.commands'.octo(<f-args>)
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

let g:loaded_octo = 1
