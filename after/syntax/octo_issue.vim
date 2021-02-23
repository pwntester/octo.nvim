" store and remove current syntax value
if exists('b:current_syntax')
  let old_syntax = b:current_syntax
  unlet b:current_syntax
endif

syntax include @markdown syntax/markdown.vim
unlet b:current_syntax

syntax region issue_comment matchgroup=OctoNvimCommentDelimiters start=/commented:\n\n/ keepend end=/\n\n\n/ contains=@markdown
syntax region issue_comment matchgroup=OctoNvimCommentDelimiters start=/\n\n/ keepend end=/\n\n\nOn/ contains=@markdown

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

" restore current syntax value
if exists('old_syntax')
  let b:current_syntax = old_syntax
endif
