if exists('g:loaded_octo')
  finish
endif

" window configuration
let s:no = nvim_win_get_option(0,'number')
let s:rno = nvim_win_get_option(0,'relativenumber')
let s:clo = nvim_win_get_option(0,'cursorline')
let s:sco = nvim_win_get_option(0,'signcolumn')
let s:wo = nvim_win_get_option(0,'wrap')
" colors
let g:octo_bubble_color = synIDattr(synIDtrans(hlID("NormalFloat")), "bg#")
execute('hi! OctoNvimBubble1 guifg='.g:octo_bubble_color)
execute('hi! OctoNvimBubble2 guibg='.g:octo_bubble_color)

" commands
if executable('gh')
  command! NewComment :lua require'octo.commands'.new_comment()
  command! CloseIssue :lua require'octo.commands'.change_issue_state('closed')
  command! ReopenIssue :lua require'octo.commands'.change_issue_state('open')
  command! SaveIssue  :lua require'octo.commands'.save_issue()

  command! -nargs=1 NewIssue :lua require'octo.commands'.new_issue(<f-args>)
  command! -nargs=+ Issue :call octo#get_issue(<f-args>)

  command! -nargs=+ AddLabel :lua require'octo.commands'.issue_action('add', 'labels', <f-args>)
  command! -nargs=+ RemoveLabel :lua require'octo.commands'.issue_action('remove', 'labels', <f-args>)
  command! -nargs=+ AddAssignee :lua require'octo.commands'.issue_action('add', 'assignees', <f-args>)
  command! -nargs=+ RemoveAssignee :lua require'octo.commands'.issue_action('remove', 'assignees', <f-args>)
  command! -nargs=+ AddReviewer :lua require'octo.commands'.issue_action('add', 'requested_reviewers', <f-args>)
  command! -nargs=+ RemoveReviewer :lua require'octo.commands'.issue_action('remove', 'requested_reviewers', <f-args>)

  command! -nargs=* ListIssues :call octo#load_menu('issues', <f-args>)
  command! -nargs=* ListPRs :call octo#load_menu('pull_requests', <f-args>)
  command! -nargs=* ListGists :call octo#load_menu('gists', <f-args>)
else
  echo 'Cannot find `gh` command.'
endif

" load menu
function! octo#load_menu(cmd, ...) abort
  let opts = {}
  let repo = v:null

  for arg in a:000
    if arg =~ '='
      let opt = split(arg,'=')
      let opts[opt[0]] = opt[1]
    else
      let repo = arg 
    end
  endfor

  let octo_menu = v:lua.require('octo.menu')
  call octo_menu[a:cmd](repo, opts)
endfunction

" load issue
function! octo#get_issue(...) abort
  let number = v:null
  let repo = v:null
  if a:0 == 1
    let repo = v:null
    let number = a:1
  elseif a:0 == 2
    let repo = a:1
    let number = a:2
  else
    echo "Incorrect number of parameters"
    return
  endif
  return luaeval("require'octo.commands'.get_issue(_A[1], _A[2])", [repo, number])
endfunction

" clear buffer undo history
function! octo#clear_history() abort
  let old_undolevels = &undolevels
  set undolevels=-1
  exe "normal a \<BS>\<Esc>"
  let &undolevels = old_undolevels
  unlet old_undolevels
endfunction

" # completion
function! octo#issue_complete(findstart, base) abort
  return luaeval("require'octo.completion'.issue_complete(_A[1], _A[2])", [a:findstart, a:base])
endfunction

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
autocmd Filetype octo_issue call octo#configure_win()
autocmd BufLeave * if &ft == 'octo_issue' | call octo#restore_win() | endif 

" mappings
nnoremap <Plug>(GoToIssue) <cmd>lua require'octo.navigation'.go_to_issue()<CR>
nmap gi <Plug>(GoToIssue)

let g:loaded_octo = 1
