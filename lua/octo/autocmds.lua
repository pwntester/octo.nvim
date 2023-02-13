local create = vim.api.nvim_create_augroup
local define = vim.api.nvim_create_autocmd

local M = {}

create("octo_autocmds", { clear = true })
create("octobuffer_autocmds", { clear = false })

function M.setup()
  define({ "BufEnter" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      require("octo").configure_octo_buffer()
    end,
  })
  define({ "BufReadCmd" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      require("octo").load_buffer()
    end,
  })
  define({ "BufWriteCmd" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      require("octo").save_buffer()
    end,
  })
  define({ "CursorHold" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      require("octo").on_cursor_hold()
    end,
  })
  define({ "CursorMoved" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews.thread-panel").show_review_threads()
    end,
  })
  define({ "TabClosed" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").close(tonumber(vim.fn.expand "<afile>"))
    end,
  })
  define({ "TabLeave" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").on_tab_leave()
    end,
  })
  define({ "WinLeave" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").on_win_leave()
    end,
  })
end

function M.update_signcolumn(bufnr)
  define({ "TextChanged", "TextChangedI" }, {
    group = "octobuffer_autocmds",
    buffer = bufnr,
    callback = function()
      require("octo").render_signcolumn()
    end,
  })
end

return M
