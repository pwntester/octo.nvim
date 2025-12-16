local fzf = require "fzf-lua"
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local octo_config = require "octo.config"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local utils = require "octo.utils"
local gh = require "octo.gh"
local headers = require "octo.gh.headers"
local previewers = require "octo.pickers.fzf-lua.previewers"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local notifications = require "octo.notifications"

---@param formatted_notifications octo.NotificationEntry[]
---@return fun(selected: [string]): nil
local function mark_notification_read(formatted_notifications)
  return function(selected)
    local notification_entry = formatted_notifications[selected[1]]
    notifications.request_read_notification(notification_entry.thread_id)
  end
end

---@param formatted_notifications octo.NotificationEntry[]
---@return fun(selected: [string]): nil
local function mark_notification_done(formatted_notifications)
  return function(selected)
    local notification_entry = formatted_notifications[selected[1]]
    notifications.delete_notification(notification_entry.thread_id)
  end
end

---@param formatted_notifications octo.NotificationEntry[]
---@return fun(selected: [string]): nil
local function unsubscribe_notification(formatted_notifications)
  return function(selected)
    local notification_entry = formatted_notifications[selected[1]]
    notifications.unsubscribe_notification(notification_entry.thread_id)
  end
end

---@param opts {
---  prompt_title: string,
---  results_title: string,
---  window_title: string,
---  all: boolean,
---  since: string,
---}
return function(opts)
  opts = opts or {}
  local formatted_notifications = {} ---@type table<string, octo.NotificationEntry> entry.ordinal -> entry

  local function get_contents(fzf_cb)
    gh.api.get {
      "/notifications",
      paginate = true,
      F = {
        all = opts.all,
        since = opts.since,
      },
      opts = {
        headers = { headers.diff },
        stream_cb = function(data, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif data then
            ---@type octo.NotificationFromREST[]
            local resp = vim.json.decode(data)
            for _, notification in ipairs(resp) do
              local entry = entry_maker.gen_from_notification(notification)
              if entry ~= nil then
                local icons = utils.icons
                local unread_icon = entry.obj.unread == true and icons.notification[entry.kind].unread
                  or icons.notification[entry.kind].read
                local unread_text = fzf.utils.ansi_from_hl(unread_icon[2], unread_icon[1]) ---@type string
                local id_text = "#" .. (entry.obj.subject.url:match "/(%d+)$" or "NA") ---@type string
                local repo_text = fzf.utils.ansi_from_hl("Number", entry.obj.repository.full_name) ---@type string
                local content = table.concat({ unread_text, id_text, repo_text, entry.obj.subject.title }, " ")
                local entry_id = table.concat(
                  { unread_icon[1], id_text, entry.obj.repository.full_name, entry.obj.subject.title },
                  " "
                )
                formatted_notifications[entry_id] = entry
                fzf_cb(content)
              end
            end
          end
        end,
        cb = function()
          fzf_cb()
        end,
      },
    }
  end

  local cfg = octo_config.values
  ---@type table<string, function|table>
  local notification_actions = fzf_actions.common_buffer_actions(formatted_notifications)
  notification_actions[utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = {
    fn = function(selected)
      notifications.copy_notification_url(formatted_notifications[selected[1]].obj)
    end,
    reload = true,
  }
  if not cfg.mappings.notification.read.lhs:match "leader>" then
    notification_actions[utils.convert_vim_mapping_to_fzf(cfg.mappings.notification.read.lhs)] =
      { fn = mark_notification_read(formatted_notifications), reload = true }
  end
  if not cfg.mappings.notification.done.lhs:match "leader>" then
    notification_actions[utils.convert_vim_mapping_to_fzf(cfg.mappings.notification.done.lhs)] =
      { fn = mark_notification_done(formatted_notifications), reload = true }
  end
  if not cfg.mappings.notification.unsubscribe.lhs:match "leader>" then
    notification_actions[utils.convert_vim_mapping_to_fzf(cfg.mappings.notification.unsubscribe.lhs)] =
      { fn = unsubscribe_notification(formatted_notifications), reload = true }
  end

  ---@type table<string, any>
  local cached_notification_infos = {}

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    ---@diagnostic disable-next-line: assign-type-mismatch
    previewer = previewers.notifications(formatted_notifications, cached_notification_infos),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, probably
      ["--header"] = opts.results_title,
      ["--info"] = "default",
    },
    ---@diagnostic disable-next-line: missing-fields
    winopts = {
      title = opts.window_title or "Notifications",
      title_pos = "center",
    },
    actions = notification_actions,
    silent = true,
  })
end
