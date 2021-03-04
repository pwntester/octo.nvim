" store and remove current syntax value
if exists('b:current_syntax')
  let old_syntax = b:current_syntax
  unlet b:current_syntax
endif

highlight default link OctoNvimDirty ErrorMsg
highlight default link OctoNvimIssueOpen MoreMsg
highlight default link OctoNvimIssueClosed ErrorMsg
highlight default link OctoNvimIssueMerged Keyword
highlight default link OctoNvimIssueId Question
highlight default link OctoNvimIssueTitle PreProc
highlight default link OctoNvimEmpty Comment
highlight default link OctoNvimFloat NormalFloat
highlight default link OctoNvimTimelineItemHeading Comment
highlight default link OctoNvimSymbol Comment
highlight default link OctoNvimDate Comment
highlight default link OctoNvimDetailsLabel Title 
highlight default link OctoNvimDetailsValue Identifier
highlight default link OctoNvimMissingDetails Comment
highlight default link OctoNvimCommentLine Visual
highlight default link OctoNvimEditable NormalFloat
highlight default link OctoNvimBubble NormalFloat
highlight default OctoNvimBubbleAuthor guifg=#000000 guibg=#58A6FF
highlight default OctoNvimBubbleGreen guifg=#ffffff guibg=#238636
highlight default OctoNvimBubbleRed guifg=#ffffff guibg=#f85149
highlight default OctoNvimPassingTest guifg=#238636
highlight default OctoNvimFailingTest guifg=#f85149
highlight default OctoNvimPullAdditions guifg=#2ea043
highlight default OctoNvimPullDeletions guifg=#da3633
highlight default OctoNvimPullModifications guifg=#58A6FF

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
