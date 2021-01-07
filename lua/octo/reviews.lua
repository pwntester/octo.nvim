local octo = require "octo"
local gh = require "octo.gh"
local util = require "octo.util"
local signs = require "octo.signs"
local constants = require "octo.constants"
local format = string.format
local api = vim.api
local json = {
  parse = vim.fn.json_decode
}

local M = {}

function M.add_changes_qf_mappings()
  vim.cmd [[nnoremap <buffer>]q :cnext <BAR> :lua require'octo.reviews'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[nnoremap <buffer>[q :cprevious <BAR> :lua require'octo.reviews'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[nnoremap <buffer><C-c> :tabclose <BAR> :lua require'octo.reviews'.clean_fugitive_buffers()<CR>]]

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd [[20copen]]
  vim.cmd [[wincmd p]]
end

function M.populate_changes_qf(base, head, changes)
  -- open a new tab so we can easily clean all the windows mess
  if true then
    vim.cmd [[tabnew %]]
  end

  -- run the diff between head and base commits
  vim.cmd(format("Git difftool --name-only %s..%s", base, head))

  -- update qf with gh info (additions/deletions ...)
  M.update_changes_qf(changes)

  M.diff_changes_qf_entry()
  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
  vim.cmd [[20copen]]
  vim.cmd [[nnoremap <buffer> <CR> <CR><BAR>:lua require'octo.reviews'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[wincmd p]]
end

function M.update_changes_qf(changes)
  local qf = vim.fn.getqflist({context = 0, items = 0})
  local items = qf.items
  for _, item in ipairs(items) do
    for _, change in ipairs(changes) do
      if item.module == format("%s:%s", change.branch, change.filename) then
        item.text = change.text .. " " .. change.status
      end
    end
  end
  vim.fn.setqflist({}, "r", {context = qf.context, items = items})
end

function M.clean_fugitive_buffers()
  local tabpage = api.nvim_get_current_tabpage()
  for _, w in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if api.nvim_win_is_valid(w) then
      local bufnr = api.nvim_win_get_buf(w)
      local bufname = api.nvim_buf_get_name(bufnr)
      if vim.startswith(bufname, "fugitive:") then
        vim.cmd(format("bdelete %d", bufnr))
      end
    end
  end
end

function M.diff_changes_qf_entry()
  -- cleanup buffers
  M.clean_fugitive_buffers()

  -- select qf entry
  vim.cmd [[cc]]

  -- set `]q` and `[q` mappings to the qf entry buffer (head)
  M.add_changes_qf_mappings()

  -- fugitive stores changed files in qf, and what to diff against in the qf context
  local qf = vim.fn.getqflist({context = 0, idx = 0})
  if qf.idx and type(qf.context) == "table" and type(qf.context.items) == "table" then
    local item = qf.context.items[qf.idx]
    local diff = item.diff or {}
    for i = #diff - 1, 0, -1 do
      if i then
        vim.cmd(format("leftabove vert diffsplit %s", vim.fn.fnameescape(diff[i + 1].filename)))
      else
        vim.cmd(format("rightbelow vert diffsplit %s", vim.fn.fnameescape(diff[i + 1].filename)))
      end
      vim.cmd [[normal! ]c]]

      -- set `]q` and `[q` mappings to the diff entry buffer (base)
      M.add_changes_qf_mappings()
    end
  end
end

function M.add_comments_qf_mappings(repo, number, main_win)
  vim.cmd(
    format(
      "nnoremap <buffer>]c :call nvim_set_current_win(%d) <BAR> :lua require'octo.reviews'.next_file_comment('%s', %d, %d)<CR>",
      main_win,
      repo,
      number,
      main_win
    )
  )
  vim.cmd(
    format(
      "nnoremap <buffer>[c :call nvim_set_current_win(%d) <BAR> :lua require'octo.reviews'.prev_file_comment('%s', %d, %d)<CR>",
      main_win,
      repo,
      number,
      main_win
    )
  )
  vim.cmd(
    format(
      "nnoremap <buffer>]q :call nvim_set_current_win(%d) <BAR> :cnext <BAR>:lua require'octo.reviews'.show_comments_qf_entry('%s', %d, %d)<CR>",
      main_win,
      repo,
      number,
      main_win
    )
  )
  vim.cmd(
    format(
      "nnoremap <buffer>[q :call nvim_set_current_win(%d) <BAR> :cprevious <BAR>:lua require'octo.reviews'.show_comments_qf_entry('%s', %d, %d)<CR>",
      main_win,
      repo,
      number,
      main_win
    )
  )

  vim.cmd [[nnoremap <buffer><C-c> :tabclose <BAR> :lua require'octo.reviews'.clean_review_comments_buffers()<CR>]]

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd [[20copen]]
  vim.cmd [[wincmd p]]
end

function M.populate_comments_qf(repo, number, selection)
  -- fetch review comments
  gh.run(
    {
      args = {"api", format("/repos/%s/pulls/%d/reviews/%d/comments", repo, number, selection.review.id)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local items = {}

          local review_comments = json.parse(output)
          for _, review_comment in ipairs(review_comments) do
            local pr_bufnr = vim.fn.bufnr(format("octo://%s/%d", repo, number))
            local comments = api.nvim_buf_get_var(pr_bufnr, "pr_comments")
            local comment = comments[tostring(review_comment.id)]
            if comment then
              local item = {}
              item.filename = comment.path
              item.lnum = comment.original_line
              item.text =
                format(
                "%s (%s): %s...",
                comment.author,
                string.lower(comment.author_association),
                vim.split(comment.body, "\n")[1]
              )
              item.pattern = comment.id

              if not comment.in_reply_to_id then
                table.insert(items, item)
              end
            end
          end

          -- populate qf
          vim.fn.setqflist(items)

          -- new tab to hold the main, qf and comment windows
          if true then
            --vim.cmd(format("tabnew %s", items[1].filename))
            vim.cmd [[tabnew %]]
          end
          local main_win = api.nvim_get_current_win()

          -- save review comments in main window var
          api.nvim_win_set_var(main_win, "review_comments", review_comments)

          -- open qf
          vim.cmd [[20copen]]
          local qf_win = api.nvim_get_current_win()

          -- add a <CR> mapping to the qf window
          vim.cmd(
            format(
              "nnoremap <buffer> <CR> <CR><BAR>:lua require'octo.reviews'.show_comments_qf_entry('%s', %d, %d)<CR>",
              repo,
              number,
              main_win
            )
          )

          -- add mappings to the qf window
          M.add_comments_qf_mappings(repo, number, main_win)


          -- back to qf
          api.nvim_set_current_win(qf_win)
          api.nvim_win_set_option(qf_win, "number", false)
          api.nvim_win_set_option(qf_win, "relativenumber", false)

          -- create comment window and set the comment buffer
          vim.cmd("vsplit")
          local comment_win = api.nvim_get_current_win()
          api.nvim_win_set_option(comment_win, "number", false)
          api.nvim_win_set_option(comment_win, "relativenumber", false)

          -- jump to main window and select qf entry
          api.nvim_set_current_win(main_win)
          api.nvim_win_set_var(main_win, "comment_win", comment_win)
          vim.cmd [[cc]]

          -- show comment for first element in qf
          M.show_comments_qf_entry(repo, number, main_win)
        end
      end
    }
  )
end

function M.clean_review_comments_buffers()
  local tabpage = api.nvim_get_current_tabpage()
  for _, w in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if api.nvim_win_is_valid(w) then
      local bufnr = api.nvim_win_get_buf(w)
      local ft = api.nvim_buf_get_option(bufnr, "filetype")
      if ft == "octo-review-comments" then
        vim.cmd(format("bdelete %d", bufnr))
      end
    end
  end
end

function M.show_comments_qf_entry(repo, number, main_win)
  -- set mappings for the main window buffer
  M.add_comments_qf_mappings(repo, number, main_win)

  -- get comment details
  local qf = vim.fn.getqflist({idx = 0, items = 0})
  local idx = qf.idx or 0
  local items = qf.items or {}
  local selected_item = items[idx]
  local comment_id = selected_item.pattern

  -- jump back to main win and go to comment line
  api.nvim_set_current_win(main_win)
  local row = (selected_item.lnum) or 1
  api.nvim_win_set_cursor(main_win, {row, 1})

  -- place signs in main window buffer
  local review_comments = api.nvim_win_get_var(main_win, "review_comments")
  local pr_bufnr = vim.fn.bufnr(format("octo://%s/%d", repo, number))
  signs.place_comments_signs(main_win, pr_bufnr, review_comments)

  -- jump to comment window
  local comment_win = api.nvim_win_get_var(main_win, "comment_win")
  api.nvim_set_current_win(comment_win)

  local comment_bufnr = vim.fn.bufnr(comment_id)
  if comment_bufnr > -1 then
    -- show existing comment buffer
    api.nvim_win_set_buf(comment_win, comment_bufnr)
  else
    -- create new comment buffer
    comment_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_var(comment_bufnr, "repo", repo)
    api.nvim_buf_set_var(comment_bufnr, "number", number)
    api.nvim_buf_set_option(comment_bufnr, "filetype", "octo-review-comments")
    api.nvim_buf_set_name(comment_bufnr, comment_id)
    api.nvim_win_set_buf(comment_win, comment_bufnr)

    -- add mappings to the comment window buffer
    M.add_comments_qf_mappings(repo, number, main_win)

    -- get cached comment
    local comments = api.nvim_buf_get_var(pr_bufnr, "pr_comments")
    local comment = comments[comment_id]

    -- write diff hunk
    M.write_diff_hunk(comment_bufnr, comment.diff_hunk)

    -- write comment
    M.write_comment(comment_bufnr, comment)

    -- write replies
    local replies = api.nvim_buf_get_var(pr_bufnr, "pr_replies")
    M.write_replies(comment_bufnr, replies, comment_id)
  end
end

function M.write_replies(comment_bufnr, replies, id)
  local creplies = replies[id]
  if creplies then
    for _, reply in ipairs(creplies) do
      -- write main comment
      M.write_comment(comment_bufnr, reply)

      -- write replies
      M.write_replies(comment_bufnr, replies, reply.id)
    end
  end
end

function M.get_file_comment_lines(repo, number, main_win)
  local review_comments = api.nvim_win_get_var(main_win, "review_comments")
  local bufnr = api.nvim_win_get_buf(main_win)
  local pr_bufnr = vim.fn.bufnr(format("octo://%s/%d", repo, number))
  local comments = api.nvim_buf_get_var(pr_bufnr, "pr_comments")
  local lines = {}
  for _, c in ipairs(review_comments) do
    local comment = comments[tostring(c.id)]
    if comment and comment.path == vim.fn.bufname(bufnr) then
      table.insert(lines, comment.original_line)
    end
  end
  table.sort(
    lines,
    function(a, b)
      return a < b
    end
  )
  return lines
end

function M.next_file_comment(repo, number, main_win)
  local lines = M.get_file_comment_lines(repo, number, main_win)
  local current_line = vim.fn.line(".")
  local target_line = current_line
  for _, l in ipairs(lines) do
    if current_line < l then
      target_line = l
      break
    end
  end
  vim.cmd(tostring(target_line))
end

function M.prev_file_comment(repo, number, main_win)
  local lines = M.get_file_comment_lines(repo, number, main_win)
  local current_line = vim.fn.line(".")
  local target_line = current_line
  for _, l in ipairs(vim.fn.reverse(lines)) do
    if current_line > l then
      target_line = l
      break
    end
  end
  vim.cmd(tostring(target_line))
end

function M.reply_to_comment(body)
  -- Creates a reply to a review comment for a pull request. For the comment_id,
  -- provide the ID of the review comment you are replying to. This must be the ID
  -- of a top-level review comment, not a reply to that comment.
  -- Replies to replies are not supported.

  -- TODO: this is like util.get_repo_number() but for `octo-review-comments` buffer
  -- refactor function to take a ft and then reuse.
  -- we also need a better name.
  local bufnr = api.nvim_get_current_buf()
  if api.nvim_buf_get_option(bufnr, "filetype") ~=  "octo-review-comments" then
    return
  end
  local comment_id = api.nvim_buf_get_name(bufnr)
  local repo_ok, repo = pcall(api.nvim_buf_get_var, 0, "repo")
  if not repo_ok then
    return
  end
  local number_ok, number = pcall(api.nvim_buf_get_var, 0, "number")
  if not number_ok then
    return
  end

  gh.run(
    {
      args = {
        "api",
        "-X",
        "POST",
        "-f",
        format("body=%s", body),
        format("/repos/%s/pulls/%d/comments/%d/replies", repo, number, comment_id)
      },
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local reply = json.parse(output)
          if tostring(reply.in_reply_to_id) ~= tostring(comment_id) or vim.fn.trim(reply.body) ~= vim.fn.trim(body) then
            api.nvim_err_writeln("Error posting reply to comment")
          else
            print("Successfully posted comment")
            M.write_comment(bufnr, reply)
          end
        end
      end
    }
  )
end

function M.write_diff_hunk(bufnr, diff_hunk)
  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DETAILS_VT_NS, 0, -1)

  local lines = vim.split(diff_hunk, "\n")

  -- print #lines + 2 empty lines
  local empty_lines = {}
  local max_length = -1
  for _, l in ipairs(lines) do
    table.insert(empty_lines, "")
    if #l > max_length then max_length = #l end
  end
  vim.list_extend(empty_lines, {"", "", ""})
  octo.write_block(empty_lines, {bufnr = bufnr, mark = false, line = 1})

  local vt_lines = {}
  table.insert(vt_lines, {{format("┌%s┐", string.rep ("─", max_length + 2))}})
  for _, line in ipairs(lines) do
    if vim.startswith(line, "@@ ") then
      local index = string.find(line, "@[^@]*$")
      table.insert(vt_lines, {
        {"│ "},
        {string.sub(line, 0, index), "DiffLine"},
        {string.sub(line, index + 1), "DiffSubname"},
        {string.rep(" ", max_length - #line - 1)},
        {"│"}
      })
    elseif vim.startswith(line, "+") then
      table.insert(vt_lines, {
        {"│ "},
        {line, "DiffAdd"},
        {string.rep(" ", max_length - #line)},
        {" │"}
      })
    elseif vim.startswith(line, "-") then
      table.insert(vt_lines, {
        {"│ "},
        {line, "DiffDelete"},
        {string.rep(" ", max_length - #line)},
        {" │"}
      })
    else
      table.insert(vt_lines, {
        {"│ "},
        {line},
        {string.rep(" ", max_length - #line)},
        {" │"}
      })
    end
  end
  table.insert(vt_lines, {{format("└%s┘", string.rep ("─", max_length + 2))}})

  -- print diff_hunk as virtual text
  local line = 0
  for _, vt_line in ipairs(vt_lines) do
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line, vt_line, {})
    line = line + 1
  end
end

function M.write_comment(bufnr, comment)
  -- heading
  local line = api.nvim_buf_line_count(bufnr) + 1
  octo.write_block({"", ""}, {bufnr = bufnr, mark = false, line = line})
  local header_vt = {
    {format("On %s ", util.format_date(comment.created_at)), "OctoNvimCommentHeading"},
    {comment.author, "OctoNvimCommentUser"},
    {" commented", "OctoNvimCommentHeading"}
  }
  api.nvim_buf_set_virtual_text(bufnr, 0, line - 1, header_vt, {})

  -- body
  line = line + 2
  local comment_body = string.gsub(comment.body, "\r\n", "\n")
  if vim.startswith(comment_body, constants.NO_BODY_MSG) then
    comment_body = " "
  end
  local content = vim.split(comment_body, "\n", true)
  vim.list_extend(content, {"", "", ""})
  octo.write_block(content, {bufnr = bufnr, mark = true, line = line})

  -- reactions
  line = line + #content
  octo.write_reactions(bufnr, comment.reactions, line - 2)
end

return M
