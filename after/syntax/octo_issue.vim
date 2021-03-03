" store and remove current syntax value
if exists('b:current_syntax')
  let old_syntax = b:current_syntax
  unlet b:current_syntax
endif

hi def link OctoNvimDirty ErrorMsg
hi def link OctoNvimUser String 
hi def link OctoNvimIssueOpen MoreMsg
hi def link OctoNvimIssueClosed ErrorMsg
hi def link OctoNvimIssueMerged Keyword
hi def link OctoNvimIssueId Question
hi def link OctoNvimIssueTitle PreProc
hi def link OctoNvimEmpty Comment
hi def link OctoNvimFloat NormalFloat
hi def link OctoNvimTimelineItemHeading Comment
hi def link OctoNvimSymbol Comment
hi def link OctoNvimDate Comment
hi def link OctoNvimDetailsLabel Title 
hi def link OctoNvimDetailsValue Identifier
hi def link OctoNvimMissingDetails Comment
hi def link OctoNvimOwned PmenuSel

call matchadd('Conceal', ':heart:', 10, -1, {'conceal':'❤️'})
call matchadd('Conceal', ':+1:', 10, -1, {'conceal':'👍'})
call matchadd('Conceal', ':see_no_evil:', 10, -1, {'conceal':'🙈'})
call matchadd('Conceal', ':laughing:', 10, -1, {'conceal':'😆'})
call matchadd('Conceal', ':thinking_face:', 10, -1, {'conceal':'🤔'})
call matchadd('Conceal', ':thinking:', 10, -1, {'conceal':'🤔'})
call matchadd('Conceal', ':ok_hand:', 10, -1, {'conceal':'👌'})
call matchadd('Conceal', ':upside_down_face:', 10, -1, {'conceal':'🙃'})
call matchadd('Conceal', ':grimacing:', 10, -1, {'conceal':'😬'})
call matchadd('Conceal', ':rocket:', 10, -1, {'conceal':'🚀'})
call matchadd('Conceal', ':blush:', 10, -1, {'conceal':'😊'})
call matchadd('Conceal', ':tada:', 10, -1, {'conceal':'🎉'})
call matchadd('Conceal', ':shrug:', 10, -1, {'conceal':'🤷'})
call matchadd('Conceal', ':man_shrugging:', 10, -1, {'conceal':'🤷'})
call matchadd('Conceal', ':face_palm:', 10, -1, {'conceal':'🤦'})
call matchadd('Conceal', ':man_facepalmin:', 10, -1, {'conceal':'🤦'})

" restore current syntax value
if exists('old_syntax')
  let b:current_syntax = old_syntax
endif
