if exists('g:loaded_octo')
  finish
endif
lua require"octo".setup()
let g:loaded_octo = 1
