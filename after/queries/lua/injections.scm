; extends

; allow injections in strings with an inject: <lang> comment
; need three copies of the same query for:
; - handling variable member assignment to string
; - variable member assignment to a string concatenated with other strings
; - the above but with some edge case i'm not sure about
; reference: https://github.com/folke/snacks.nvim/commit/1d5b12d0c67071320e5572a1f2ac1265904426b3
((comment
  content: (comment_content) @injection.language)
  (#lua-match? @injection.language "inject%s*:%s*%S+")
  (#gsub! @injection.language "^%s*inject%s*:%s*(%S+).*" "%1")
  .
  (_
    (_
      (string
        content: (string_content) @injection.content))))

((comment
  content: (comment_content) @injection.language)
  (#lua-match? @injection.language "inject%s*:%s*%S+")
  (#gsub! @injection.language "^%s*inject%s*:%s*(%S+).*" "%1")
  .
  (_
    (_
      (_
        (string
          content: (string_content) @injection.content)))))

((comment
  content: (comment_content) @injection.language)
  (#lua-match? @injection.language "inject%s*:%s*%S+")
  (#gsub! @injection.language "^%s*inject%s*:%s*(%S+).*" "%1")
  .
  (_
    (_
      (_
        (_
          (string
            content: (string_content) @injection.content))))))
