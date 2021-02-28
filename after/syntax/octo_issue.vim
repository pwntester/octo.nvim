" store and remove current syntax value
if exists('b:current_syntax')
  let old_syntax = b:current_syntax
  unlet b:current_syntax
endif

hi def link OctoNvimDirty ErrorMsg
hi def link OctoNvimCommentHeading PreProc
hi def link OctoNvimCommentUser String 
hi def link OctoNvimIssueOpen MoreMsg
hi def link OctoNvimIssueClosed ErrorMsg
hi def link OctoNvimIssueMerged Keyword
hi def link OctoNvimIssueId Question
hi def link OctoNvimIssueTitle PreProc
hi def link OctoNvimEmpty Comment
hi def link OctoNvimFloat NormalFloat
hi def link OctoNvimDetailsLabel Title 
hi def link OctoNvimMissingDetails Comment
hi def link OctoNvimDetailsValue Identifier

call matchadd('Conceal', ':heart:', 10, -1, {'conceal':'❤️'})
call matchadd('Conceal', ':+1:', 10, -1, {'conceal':'👍'})
call matchadd('Conceal', ':see_no_evil:', 10, -1, {'conceal':'🙈'})
call matchadd('Conceal', ':laughing:', 10, -1, {'conceal':'😆'})
call matchadd('Conceal', ':thinking:', 10, -1, {'conceal':'🤔'})

" restore current syntax value
if exists('old_syntax')
  let b:current_syntax = old_syntax
endif
