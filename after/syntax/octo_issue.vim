" store and remove current syntax value
if exists('b:current_syntax')
  let old_syntax = b:current_syntax
  unlet b:current_syntax
endif

hi def link OctoNvimDirty ErrorMsg
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
hi def link OctoNvimCommentLine Visual
hi def link OctoNvimEditable NormalFloat
hi def link OctoNvimBubble NormalFloat
hi def OctoNvimBubbleAuthor guifg=#000000 guibg=#58A6FF
hi def OctoNvimBubbleGreen guifg=#ffffff guibg=#238636
hi def OctoNvimBubbleRed guifg=#ffffff guibg=#f85149
hi def OctoNvimPassingTest guifg=#238636
hi def OctoNvimFailingTest guifg=#f85149
hi def OctoNvimPullAdditions guifg=#2ea043
hi def OctoNvimPullDeletions guifg=#da3633
hi def OctoNvimPullModifications guifg=#58A6FF

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
