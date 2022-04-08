local record M
  -- TODO: Finish decl
  record Review
    record Layout
      -- TODO: Where to move this decl?
      record File
        place_signs: function(self: File)
      end
      cur_file: function(self: Layout): File
    end
    layout: Layout

    threads: {any}
  end
  get_current_review: function(): Review
end

return M
