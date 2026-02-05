---@diagnostic disable
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(opts)
  opts = opts or {}

  local cb = opts.cb

  opts.repo = opts.repo or utils.get_remote_name()
  local owner, name = utils.split_repo(opts.repo)

  local function get_contents(fzf_cb)
    gh.api.graphql {
      query = queries.labels,
      F = { owner = owner, name = name },
      opts = {
        cb = function(output, stderr)
          if stderr and not utils.is_blank(stderr) then
            utils.error(stderr)
          elseif output then
            local resp = vim.json.decode(output)
            local labels = resp.data.repository.labels.nodes

            for _, label in ipairs(labels) do
              local colored_name = picker_utils.color_string_with_hex(label.name, "#" .. label.color)
              fzf_cb(string.format("%s %s", label.id, colored_name))
            end
          end

          fzf_cb()
        end,
      },
    }
  end

  fzf.fzf_exec(
    get_contents,
    vim.tbl_deep_extend("force", picker_utils.multi_dropdown_opts, {
      fzf_opts = {
        ["--delimiter"] = " ",
        ["--with-nth"] = "2..",
      },
      actions = {
        ["default"] = function(selected, fzf_opts)
          local labels = {}

          -- If nothing selected but query text exists, treat it as label name
          if #selected == 0 then
            local query_text = fzf_opts and fzf_opts.last_query or ""
            if query_text and query_text ~= "" then
              -- Fetch label ID by name
              local label_id = utils.get_label_id(query_text)
              if label_id then
                table.insert(labels, { id = label_id })
              else
                utils.error("Cannot find label: " .. query_text)
                return
              end
            else
              return
            end
          else
            -- Normal selection flow
            for _, row in ipairs(selected) do
              local id, _ = unpack(vim.split(row, " "))
              table.insert(labels, { id = id })
            end
          end

          cb(labels)
        end,
      },
    })
  )
end
