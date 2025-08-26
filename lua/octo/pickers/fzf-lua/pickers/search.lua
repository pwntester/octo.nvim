---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

---@param fzf_cb function
---@param issue table
---@param max_id_length integer
---@param formatted_issues table<string, table> entry.ordinal -> entry
---@param co thread
local function handle_entry(fzf_cb, issue, max_id_length, formatted_issues, co)
  local entry = entry_maker.gen_from_issue(issue)
  if entry == nil then
    return {}
  end

  local ordinal_entry, string_entry

  local owner, name = utils.split_repo(entry.repo)
  local icon_with_hl = utils.get_icon(entry)
  local icon_str = fzf.utils.ansi_from_hl(icon_with_hl[2], icon_with_hl[1])

  local ordinal_entry, string_entry

  if entry.kind ~= "repo" then
    local raw_number = picker_utils.pad_string(entry.obj.number, max_id_length)
    local number = fzf.utils.ansi_from_hl("Comment", raw_number)

    local str_format = string.format("%s %s %s %s %s %s", entry.kind, owner, name, number, icon_str, entry.obj.title)
    string_entry = str_format
    ordinal_entry = fzf.utils.strip_ansi_coloring(str_format)
  end

  if entry.kind == "repo" then
    local raw_name_with_owner = picker_utils.pad_string(entry.obj.nameWithOwner, max_id_length)
    local name_with_owner = fzf.utils.ansi_from_hl("OctoGreen", raw_name_with_owner)
    local description_repo = entry.obj.description and entry.obj.description or ""

    local str_format = string.format(
      "%s %s %s %s",
      entry.repo,
      owner,
      name,
      string.format(
        "%s %-" .. (#raw_name_with_owner - max_id_length) .. "s %-20s %-10s",
        name_with_owner,
        " f:" .. entry.obj.forkCount,
        " s:" .. entry.obj.stargazerCount,
        tostring(description_repo)
      )
    )
    string_entry = str_format
    ordinal_entry = fzf.utils.strip_ansi_coloring(str_format)
  end

  formatted_issues[ordinal_entry] = entry
  fzf_cb(string_entry, function()
    coroutine.resume(co)
  end)
end

return function(opts)
  opts = opts or {}

  local formatted_items = {} ---@type table<string, table> entry.ordinal -> entry

  local is_hidden = false
  if opts.type == "REPOSITORY" then
    is_hidden = true
  end

  local function contents(query)
    return function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()

        local function process_issues(output)
          if utils.is_blank(output) then
            return {}
          end

          local issues = vim.json.decode(output)

          local max_id_length = 1
          for _, issue in ipairs(issues) do
            local id_length = max_id_length
            if opts.type == "REPOSITORY" then
              if issue.nameWithOwner then
                id_length = #tostring(issue.nameWithOwner)
              end
            else
              if issue.number then
                id_length = #tostring(issue.number)
              end
            end

            if id_length > max_id_length then
              max_id_length = id_length
            end
          end

          for _, issue in ipairs(issues) do
            vim.schedule(function()
              handle_entry(fzf_cb, issue, max_id_length, formatted_items, co)
            end)
            coroutine.yield()
          end
        end

        local function build_prompt(base_prompt, query)
          local _q = ""

          if query and type(query) == "string" then
            _q = query
          end

          if query and type(query) == "table" then
            _q = query[1]
          end

          local prompt = string.format("%s %s", base_prompt or "", _q)
          if prompt then
            return prompt
          end

          return base_prompt or ""
        end

        if opts.type == "REPOSITORY" then
          local prompt = build_prompt(opts.prompt, query)

          local output = gh.api.graphql {
            query = queries.search,
            f = { prompt = prompt, type = "REPOSITORY" },
            F = { last = 50 },
            jq = ".data.search.nodes",
            opts = { mode = "sync" },
          }
          process_issues(output)
        else
          if type(opts.prompt) == "string" then
            opts.prompt = { opts.prompt }
          end

          if not opts.prompt or (utils.is_blank(query) and not opts.prompt) then
            return {}
          end

          for _, val in ipairs(opts.prompt) do
            local prompt = build_prompt(val, query)

            local output = gh.api.graphql {
              query = queries.search,
              fields = { prompt = prompt, type = opts.type },
              jq = ".data.search.nodes",
              opts = { mode = "sync" },
            }
            process_issues(output)
          end
        end

        fzf_cb()
      end)()
    end
  end

  -- TODO this is still not as fast as I would like.
  fzf.fzf_live(contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    exec_empty_query = true,
    func_async_callback = false,
    previewer = previewers.search(),
    query_delay = 500,
    fzf_opts = {
      ["--info"] = "default",
      ["--delimiter"] = " ",
      ["--with-nth"] = "4..",
    },
    winopts = {
      preview = { hidden = is_hidden },
    },
    actions = fzf_actions.common_open_actions(formatted_items),
  })
end
