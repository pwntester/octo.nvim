" store and remove current syntax value
if exists('b:current_syntax')
  let old_syntax = b:current_syntax
  unlet b:current_syntax
endif

syntax include @markdown syntax/markdown.vim
unlet b:current_syntax

syntax region issue_comment matchgroup=OctoNvimCommentDelimiters start=/commented:\n\n/ keepend end=/\n\n\n/  contains=@markdown
syntax region issue_comment matchgroup=OctoNvimCommentDelimiters start=/\n\n/ keepend end=/\n\n\nOn/  contains=@markdown

hi OctoNvimDirty guifg=red
hi def link OctoNvimCommentDelimiters Normal
hi def link OctoNvimCommentHeading PreProc
hi def link OctoNvimCommentUser Underlined
hi def link OctoNvimIssueOpen MoreMsg
hi def link OctoNvimIssueClosed ErrorMsg
hi def link OctoNvimIssueId Question
hi def link OctoNvimIssueTitle PreProc
hi def link OctoNvimEmpty Comment

" restore current syntax value
if exists('old_syntax')
  let b:current_syntax = old_syntax
endif
