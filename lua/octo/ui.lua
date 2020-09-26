-- this is a slightly modified version of Norcalli's UI.NVIM plugin 
-- https://github.com/norcalli/ui.nvim
-- used here as a lighweight fuzzy menu for picking an Issue in :ListIssues
-- may be replaced with FZF or telescope but didnt want to require any dependencies for now

local vim = vim
local api = vim.api
local min, max = math.min, math.max
local format = string.format
local concat = table.concat
local remove = table.remove
local schedule = vim.schedule
local qsort = table.sort
local ceil = math.ceil
local uv = require 'luv'

local key_callbacks = {}

local function tohex(s)
  local R = {}
  for i = 1, #s do
    R[#R+1] = format("%02X", s:byte(i))
  end
  return concat(R)
end

local function apply_mappings(mappings)
  assert(type(mappings) == 'table')
  for k, v in pairs(mappings) do
    local mode = k:sub(1,1)
    local lhs = k:sub(2)
    local rhs = remove(v, 1)
    local opts = v
    if opts.buffer then
      local bufnr = opts.buffer
      assert(bufnr == tonumber(bufnr))
      opts.buffer = nil
      if not key_callbacks[bufnr] then
        key_callbacks[bufnr] = {}
        api.nvim_buf_attach(bufnr, false, {
          on_detach = function(bufnr)
            key_callbacks[bufnr] = nil
          end;
        })
      end

	  -- unmap keys
	  pcall('api.nvim_command', mode..'unmap '..lhs)
	  pcall('api.nvim_command', mode..'unmap <buffer> '..lhs)

      local ekey = tohex(lhs:lower())
      key_callbacks[bufnr][ekey] = rhs
      opts.noremap = true
      rhs = format("<cmd>lua require'octo.ui'.key_callbacks[%d][%q]()<cr>", bufnr, ekey)
      api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
    else
      local ekey = tohex(lhs:lower())
      key_callbacks[-1][ekey] = rhs
      opts.noremap = true
      rhs = format("<cmd>lua require'octo.ui'.key_callbacks[-1][%q]()<cr>", ekey)
      api.nvim_set_keymap(mode, lhs, rhs, opts)
    end
  end
end

local function clamp(low, high, value)
  return min(high, max(low, value))
end

local popup_internal
local function popup_callback()
  if type(popup_internal) == 'function' then
    local ok, err = pcall(popup_internal)
    if ok then
    else
      print(err)
    end
  end
end

local function nonoverlapping_ngrams(s, n)
  local R = {}
  for m in s:gmatch(("."):rep(n)) do
    R[#R+1] = m
  end
  return R
end

local function overlapping_ngrams(s, n)
  local R = {}
  for i = 1, s:len() - n + 1 do
    R[#R+1] = s:sub(i, i+n-1)
  end
  return R
end

local function make_ensemble_cost_fn(user_input)
  local N = user_input:len()
  local ngramlen = 2
  local case_sensitive = 0 == 1
  local ul = user_input:lower()
  local ngram_input = case_sensitive and user_input or ul
  local overlapping = 1 == 1
  local ngrams = overlapping
    and overlapping_ngrams(ngram_input, ngramlen)
    or nonoverlapping_ngrams(ngram_input, ngramlen)
  if not ngrams[1] then
    ngrams[1] = ngram_input
  end
  return function(user_input, s)
    local sl = s:lower()
    local c1 = sl:find(ul, 1, true)
    local consecutive = 0
    local previous_index = 0
    local m = 0
    for i = 1, #ngrams do
      local x1, x2 = sl:find(ngrams[i], 1, true)
      if x1 then
        m = m + 1
        if x1 > previous_index then
          consecutive = consecutive + 1
        end
        previous_index = x1
      end
    end

    return ceil(1e2*(
      (10*m/#ngrams)
      + 3*m*ngramlen/#s
      + consecutive
      + N/(c1 or (2*#s))
    ))

  end
end

local function reverse(tbl)
  for i=1, math.floor(#tbl / 2) do
    local tmp = tbl[i]
    tbl[i] = tbl[#tbl - i + 1]
    tbl[#tbl - i + 1] = tmp
  end
end

local function fuzzy_popup(opts)
  opts = opts or {}
  local buf = api.nvim_create_buf(false, true)

  api.nvim_buf_set_option(buf, 'bufhidden', 'delete')

  local win

  -- TODO(ashkan): use the minimum size or the actual window size.
  local uis = api.nvim_list_uis()

  local ui_min_width = math.huge
  local ui_min_height = math.huge
  for _, ui in ipairs(uis) do
    ui_min_width = math.min(ui.width, ui_min_width)
    ui_min_height = math.min(ui.height, ui_min_height)
  end

  opts = {
      relative = 'editor';
      width = opts.width or math.floor(ui_min_width * 50 / 100);
      height = opts.height or math.floor(ui_min_height * 50 / 100);
      -- width = 50;
      -- height = 20;
      anchor = 'NW';
      style = 'minimal';
	  focusable = false;
	}
  opts.col = math.floor((ui_min_width - opts.width) / 2)
  opts.row = math.floor((ui_min_height - opts.height) / 2)
  win = api.nvim_open_win(buf, 0, opts)

  api.nvim_win_set_option(win, 'wrap', false)
  api.nvim_buf_set_option(buf, 'ul', -1)
  api.nvim_win_set_option(win, 'concealcursor', 'nc')
  -- nvim.buf_set_option(buf, 'modifiable', false)
  return buf, win
end

local function floating_fuzzy_menu(options)
  -- inputs: table where e.display should be a string to be displayed
  --         or list of elements
  -- length: maximum number of elements to be displayed
  -- callback: function to call when an element is picked
  -- prompt_position: defaults to bottom
  -- prompt: defaults to ''
  -- user_input: defaults to ''
  -- leave_empty_line: defaults to false
  -- show_cost: defaults to false
  -- virtual_text: default to ''

  local inputs = assert(options.inputs or options[1], "Missing .inputs")
  assert(type(inputs) == 'table', "inputs must be a table")
  local entry_count = options.length or options.count or #inputs
  assert(type(entry_count) == 'number', "Input length is not a number")
  local callback = options.callback or options[2] or print
  assert(type(callback) == 'function')
  local ns = api.nvim_create_namespace('fuzzy_menu')
  local vtns = api.nvim_create_namespace('vt_fuzzy_menu')
  local prompt_position = options.prompt_position or 'bottom'
  local user_input = options.user_input or ''
  local prompt = options.prompt or ''
  local leave_empty_line = options.leave_empty_line or false
  local show_cost = options.show_cost or false
  local width = options.width or 100
  local height = options.height or 40
  local virtual_text = options.virtual_text or ''

  local bufnr, winnr = fuzzy_popup {
    width = width;
    height = height;
  }

  vim.wo[winnr].wrap = false

  local win_width = vim.fn.winwidth(winnr)
  local win_height = vim.fn.winheight(winnr)

  -- number of elements shown on screen
  local visible_entry_count = min(win_height - 1, entry_count)
  if leave_empty_line then
    visible_entry_count = min(win_height - 2, entry_count)
  end

  -- number of lines available for inputs on screen
  local visible_height = win_height - 1
  if leave_empty_line then
    visible_height = win_height - 2
  end

  -- index of selected line
  local highlighted_line = 1

  -- first character of each input appearing on screen
  local horizontal_start = 1

  -- first element of inputs array appearing on screen
  local visible_start = 1

  local prefix = prompt..' '
  local PADDING = (" "):rep(win_width)

  local K_BS = api.nvim_replace_termcodes("<BS>", true, true, true)
  local K_LEFT = api.nvim_replace_termcodes("<Left>", true, true, true)
  local K_CW = api.nvim_replace_termcodes("<c-w>", true, true, true)
  local K_RIGHT = api.nvim_replace_termcodes("<Right>", true, true, true)

  local last_index = entry_count

  local entries = {}
  local indices = {}
  local costs = {}

  for i = 0, entry_count do
    costs[i] = 0
    indices[i] = i
  end

  local longest_prefix = 0
  local lazily_evalute = 1 == 1
  if lazily_evalute then
  else
    local first_index
    last_index = 0
    for i = 1, entry_count do
      local v = inputs[i].display or inputs[i]
      if v ~= nil then
        entries[i] = tostring(v)
        last_index = i
        first_index = first_index or i
      else
        entries[i] = ""
      end
    end
    if not first_index then
      return
    end
    assert(first_index == 1)
    if (last_index - first_index) >= 1 then
      longest_prefix = #entries[first_index]
      for i = first_index, last_index do
        if #entries[i] > 0 then
          longest_prefix = min(longest_prefix, #entries[i])
          for j = 1, longest_prefix do
            if entries[first_index]:byte(j) ~= entries[i]:byte(j) then
              longest_prefix = j
              break
            end
          end
        end
      end
    end
    for i = 0, last_index do
      costs[i] = 0
      indices[i] = i
    end
  end

  local function get_entry(i)
    local e = entries[i]
    if e then
      return e
    end
    e = inputs[i]
    if e then
      e = tostring(e.display or e)
      entries[i] = e
      return e
    end
  end

  local function get_mapped_entry(idx)
    if idx >= 1 and idx <= entry_count then
      return get_entry(indices[idx])
    end
  end

  local function get_mapped_entry_display(idx)
    if idx >= 1 and idx <= entry_count then
      local i = indices[idx]
      local input = inputs[i]
      if input then
        return input.display or get_entry(i)
      end
    end
  end

  local calculation_budget = 100

  local hrtime = uv.hrtime
  local ms_time = function() return hrtime()/1e6 end
  local function update_filtered()
    -- print("longest_prefix:", longest_prefix)
    last_index = entry_count
    local N = user_input:len()
    -- print(os.time(), "filtered", N)
    local t0 = ms_time()
    local cost_fn = make_ensemble_cost_fn(user_input)
    if N == 0 then
      local new_longest_prefix = longest_prefix
      local first_entry
      for i = 1, last_index do
        local v = get_entry(i)
        if i > 1 and (ms_time() - t0) > calculation_budget then
          print("Breaking early", ms_time() - t0)
          v = nil
        end
        if not v then
          last_index = i - 1
          break
        end
        assert(type(v) == 'string', type(v))
        if longest_prefix == 0 and #v > 0 then
          if i == 1 then
            first_entry = v
            new_longest_prefix = #v
          else
            new_longest_prefix = min(new_longest_prefix, #v)
            for j = 1, new_longest_prefix do
              if first_entry:byte(j) ~= v:byte(j) then
                new_longest_prefix = j
                break
              end
            end
          end
        end
        costs[i] = 0
        indices[i] = i
      end
      if longest_prefix == 0 then
        longest_prefix = new_longest_prefix
      end
      return
    end
    local entry_check_count = last_index
    if is_reduction then
      entry_check_count = visible_entry_count
    end
    local new_longest_prefix = longest_prefix
    local first_entry
    for i = 1, entry_check_count do

      local v = get_entry(i)

      if i > 1 and (ms_time() - t0) > calculation_budget then
        print("Breaking early", ms_time() - t0)
        v = nil
      end
      if v then
        if not is_reduction then
          last_index = i
        end
        if longest_prefix == 0 then
          if i == 1 then
            first_entry = v
            new_longest_prefix = #v
          end
          if i > 1 and #v > 0 then
            new_longest_prefix = min(new_longest_prefix, #v)
            for j = 1, new_longest_prefix do
              if first_entry:byte(j) ~= v:byte(j) then
                new_longest_prefix = j
                break
              end
            end
          end
        end

        costs[i] = cost_fn(user_input, v:sub(longest_prefix))
      else
        last_index = min(last_index, i-1)
        costs[i] = 0
        break
      end
      indices[i] = i
    end
    longest_prefix = new_longest_prefix
    entry_check_count = min(last_index, entry_check_count)
    local t1 = ms_time()
    qsort(indices, function(a, b)
		return costs[a] > costs[b]
    end)
    if show_cost then
      print("entries:", entry_check_count, "Cost:", t1 - t0, "Sort:", ms_time() - t1)
    end
  end

  local function focused_index()
    return visible_start + highlighted_line - 1
  end

  local hscroll_all = 0 == 1

  local function redraw()
    local lines = {}
    local focused_entry = focused_index()
    for i = 1, visible_height do
      local idx = visible_start + i - 1
      local v = get_mapped_entry_display(idx)
      if v then
        local line_prefix

        if show_cost then
            -- print(entry_count, last_index, idx, indices[idx])
            local cost = costs[indices[idx]] or error("You goofed up. Index "..idx)
            if cost < 0 then
              line_prefix = format("%4s ", "-"..format("%X", -cost))
            else
              line_prefix = format("%4X ", cost)
            end
        else
		  line_prefix = '  '
        end

        v = v:gsub("\n+", " ")
        if idx == focused_entry then
          lines[i] = line_prefix..v:sub(horizontal_start)
          lines[i] = lines[i]..PADDING:sub(#lines[i]+1)
        else
          if hscroll_all then
            lines[i] = line_prefix..(v:sub(horizontal_start))
          else
            lines[i] = line_prefix..v
          end
        end
      else
        lines[i] = ""
      end
      assert(lines[i], i)
    end
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    if prompt_position == 'bottom' then
	  schedule(function()
        api.nvim_buf_add_highlight(bufnr, ns, 'Title', win_height-1, 0, #prompt)
        if virtual_text ~= '' then
          local padding = (' '):rep(win_width - #prompt - #user_input - #virtual_text - 2)
          api.nvim_buf_set_virtual_text(bufnr, vtns, win_height-1, {{padding..virtual_text, 'SpecialKey'}}, {})
        end
      end)
    elseif prompt_position == 'top' then
	  schedule(function()
        api.nvim_buf_add_highlight(bufnr, ns, 'Title', 0, 0, #prompt)
        if virtual_text ~= '' then
          local padding = (' '):rep(win_width - #prompt - #user_input - #virtual_text - 2)
          api.nvim_buf_set_virtual_text(bufnr, vtns, 0, {{padding..virtual_text, 'SpecialKey'}}, {})
        end
      end)
    end

    local offset = 0
	if prompt_position == 'bottom' then
	    api.nvim_buf_set_lines(bufnr, 0, -2, false, {})
		reverse(lines)
        if leave_empty_line then
          vim.list_extend(lines, {''})
          offset = 1
        end
		api.nvim_buf_set_lines(bufnr, 0, -2 - offset, false, lines)
		api.nvim_buf_add_highlight(bufnr, ns, 'Visual', win_height - highlighted_line - 1 - offset, 0, -1)
		api.nvim_buf_add_highlight(bufnr, ns, 'Question', win_height - highlighted_line - 1 - offset, 0, -1)
    elseif prompt_position == 'top' then
        if leave_empty_line then
		  api.nvim_buf_set_lines(bufnr, 1, 1, false, {''})
          offset = 1
        end
		api.nvim_buf_set_lines(bufnr, 1 + offset, -1, false, lines)
		api.nvim_buf_add_highlight(bufnr, ns, 'Visual', highlighted_line + offset, 0, -1)
		api.nvim_buf_add_highlight(bufnr, ns, 'Question', highlighted_line + offset, 0, -1)
    else
      -- ERROR
	end

  end

  local function update_user_input()
    local prev = user_input
    user_input = api.nvim_get_current_line():sub(#prefix+1)
    if prev == user_input then
      return
    end
    if #user_input < #prev then
      for i = 1, last_index do
        costs[i] = 0
        indices[i] = i
      end
    end
    --local is_reduction = #user_input > 3 and #user_input > #prev
    --update_filtered(is_reduction)
    update_filtered()
    redraw()
  end

  popup_internal = function()
    --print(os.time(), "internal")
    update_user_input()
  end

  local function shift_view(offset)
    local prev = visible_start
    visible_start = clamp(1, max(last_index - visible_entry_count + 1, 1), visible_start + offset)
    return visible_start - prev
  end

  local function shift_highlight(offset)
    local prev = highlighted_line
  	highlighted_line = clamp(1, min(visible_entry_count, last_index), highlighted_line + offset)

    -- how many lines the hl has advanced
    return highlighted_line - prev
  end

  local function shift_cursor(offset)
	if prompt_position == 'top' then
      offset = offset * -1
    end

    local x = shift_highlight(offset)
    -- only shift view when we have reached the upper or lower bounds
    -- offset == x means that view is not shifted
    x = x + shift_view(offset - x)
    if not hscroll_all and x ~= 0 then
      horizontal_start = 1
    end
  end

  local function scroll_horizontally(offset)
    if hscroll_all then
      horizontal_start = max(1, horizontal_start + offset)
    else
      horizontal_start = clamp(1, #(get_mapped_entry(focused_index()) or ""), horizontal_start + offset)
    end
  end

  local function check_insert_cursor()
    return api.nvim_win_get_cursor(0)[2] > #prefix
  end

  local was_insert = vim.fn.mode() == 'i'

  local function close_window()
    if not was_insert then
      vim.cmd "stopinsert"
    end
    pcall(api.nvim_win_close, winnr, true)
    return true
  end

  local mappings = {
    ["i<c-j>"]       = function() shift_cursor(-1) end;
    ["i<c-k>"]       = function() shift_cursor(1) end;
    ["i<esc>"]       = close_window;
    ["i<c-c>"]       = close_window;
    ["i<c-h>"]    = function() scroll_horizontally(-1) end;
    ["i<c-l>"]   = function() scroll_horizontally(1) end;
    ["i<c-s-h>"]  = function() scroll_horizontally(-5) end;
    ["i<c-s-l>"] = function() scroll_horizontally(5) end;
    ["i<c-d>"]       = function() shift_view(-visible_height) end;
    ["i<c-u>"]       = function() shift_view(visible_height) end;
    ["i<home>"]      = function() shift_cursor(entry_count) end;
    ["i<end>"]       = function() shift_cursor(-entry_count) end;
    ["i<pageup>"]    = function() shift_cursor(visible_height) end;
    ["i<pagedown>"]  = function() shift_cursor(-visible_height) end;
    -- ["i<left>"] = function()
    --   if check_insert_cursor() then
    --     api.nvim_feedkeys(K_LEFT, 'ni', false)
    --   end
    -- end;
    -- ["i<c-w>"] = function()
    --   if check_insert_cursor() then
    --     api.nvim_feedkeys(K_CW, 'ni', false)
    --   end
    -- end;
    ["i<bs>"] = function()
      if check_insert_cursor() then
        api.nvim_feedkeys(K_BS, 'ni', false)
      end
    end;
    ["i<CR>"] = function()
      local entry_index = indices[focused_index()]
      local ok, dont_close = pcall(callback, inputs[entry_index], entry_index, costs[entry_index])
      if ok then
        if not dont_close then
          return close_window()
        end
      else
        print(dont_close)
      end
    end;
  }
  for k, v in pairs(mappings) do
    assert(type(v) == 'function')
    local fn1 = v
    local fn = function()
      if not fn1() then
        redraw()
      end
    end
    mappings[k] = { fn; buffer = bufnr; }
  end
  update_filtered()
  if hscroll_all then
    horizontal_start = longest_prefix or 0
  end
  --local offset = 0
  --if leave_empty_line then offset = 1 end
  if prompt_position == 'bottom' then
	api.nvim_buf_set_lines(bufnr, -2, -1, false, {prefix})
	schedule(function()
		api.nvim_win_set_cursor(winnr, {win_height, #prefix})
		local line = api.nvim_get_current_line()
		api.nvim_set_current_line(line..user_input)
		api.nvim_win_set_cursor(winnr, {win_height, #prefix+#user_input})
        api.nvim_buf_add_highlight(bufnr, ns, 'Title', win_height-1, 0, #prompt)
        if virtual_text ~= '' then
          local padding = (' '):rep(win_width - #prompt - #user_input - #virtual_text - 2)
          api.nvim_buf_set_virtual_text(bufnr, vtns, win_height-1, {{padding..virtual_text, 'SpecialKey'}}, {})
        end
	end)
  elseif prompt_position == 'top' then
	api.nvim_buf_set_lines(bufnr, 0, 1, false, {prefix})
	schedule(function()
      api.nvim_win_set_cursor(winnr, {1, #prefix})
      local line = api.nvim_get_current_line()
      api.nvim_set_current_line(line..user_input)
      api.nvim_win_set_cursor(winnr, {1, #prefix+#user_input})
      api.nvim_buf_add_highlight(bufnr, ns, 'Title', 0, 0, #prompt)
      if virtual_text ~= '' then
        local padding = (' '):rep(win_width - #prompt - #user_input - #virtual_text - 2)
        api.nvim_buf_set_virtual_text(bufnr, vtns, 0, {{padding..virtual_text, 'SpecialKey'}}, {})
      end
	end)
  end
  redraw()

  vim.cmd "startinsert"
  vim.cmd(format("autocmd BufEnter <buffer=%d> startinsert", bufnr))
  vim.cmd(format("autocmd BufLeave <buffer=%d> silent! bwipe! %d", bufnr, bufnr))
  vim.cmd(format("autocmd InsertLeave <buffer=%d> startinsert", bufnr))
  vim.cmd(format("autocmd TextChangedI <buffer=%d> lua require'octo.ui'.popup_callback()", bufnr))

  apply_mappings(mappings)

end


return {
  floating_fuzzy_menu = floating_fuzzy_menu;
  popup_callback = popup_callback;
  key_callbacks = key_callbacks;
}
