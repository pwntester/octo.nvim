local record M
  setup: function()
  place: function(name: string, bufnr: number, line: number)
  unplace: function(bufnr: number)
  place_signs: function(bufnr: number, start_line: number, end_line: number, is_dirty: boolean)
end

return M
