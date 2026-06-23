local config = require "octo.config"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local uri = require "octo.uri"
local utils = require "octo.utils"
local vim = vim

local M = {}

---@class OctoPollingEntry
---@field owner string
---@field name string
---@field number integer
---@field kind string
---@field hostname string|nil
---@field last_updated_at string
---@field remote_changed boolean

---@type table<integer, OctoPollingEntry>
local tracked_buffers = {}

---@type uv.uv_timer_t|nil
local timer = nil

---Check if an OctoBuffer has unsaved local edits
---@param octo_buf OctoBuffer
---@return boolean
local function buffer_is_dirty(octo_buf)
  octo_buf:update_metadata()

  if octo_buf.titleMetadata and octo_buf.titleMetadata.dirty then
    return true
  end
  if octo_buf.bodyMetadata and octo_buf.bodyMetadata.dirty then
    return true
  end
  if octo_buf.commentsMetadata then
    for _, comment in ipairs(octo_buf.commentsMetadata) do
      if comment.dirty then
        return true
      end
    end
  end
  return false
end

---Start the timer loop
---@param interval number
local function start_timer(interval)
  timer = vim.uv.new_timer()
  if not timer then
    return
  end
  timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      for bufnr, tracking in pairs(tracked_buffers) do
        if not vim.api.nvim_buf_is_valid(bufnr) then
          tracked_buffers[bufnr] = nil
        elseif tracking.kind == "issue" or tracking.kind == "pull" then
          gh.api.graphql {
            query = queries.updated_at,
            F = {
              owner = tracking.owner,
              name = tracking.name,
              number = tracking.number,
            },
            hostname = tracking.hostname,
            jq = ".data.repository.issueOrPullRequest.updatedAt",
            opts = {
              cb = function(output, stderr)
                if stderr and not utils.is_blank(stderr) then
                  return
                end
                if not output or utils.is_blank(output) then
                  return
                end

                local remote_updated_at = vim.trim(output):gsub('"', "")
                if remote_updated_at == tracking.last_updated_at then
                  return
                end

                local octo_buf = octo_buffers[bufnr]
                if not octo_buf then
                  return
                end

                local conf = config.values.poll
                if buffer_is_dirty(octo_buf) then
                  tracking.remote_changed = true
                  if conf.notify_on_change then
                    utils.info(
                      string.format(
                        "Remote changes detected for %s/%s #%d (buffer has local edits, skipping reload)",
                        tracking.owner,
                        tracking.name,
                        tracking.number
                      )
                    )
                  end
                else
                  require("octo").load_buffer { bufnr = bufnr }
                  tracking.last_updated_at = remote_updated_at
                  tracking.remote_changed = false
                  if conf.notify_on_refresh then
                    utils.info(
                      string.format("Auto-refreshed %s/%s #%d", tracking.owner, tracking.name, tracking.number)
                    )
                  end
                end
              end,
            },
          }
        end
      end
    end)
  )
end

---Stop and clean up the timer
local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

---Start the polling timer
function M.start()
  if timer then
    return
  end

  local conf = config.values.poll
  if not conf then
    return
  end

  if vim.tbl_count(tracked_buffers) == 0 then
    utils.info "No octo buffers to poll"
    return
  end

  start_timer(conf.interval)
  utils.info "Octo polling started"
end

---Stop the polling timer
function M.stop()
  if timer then
    stop_timer()
    utils.info "Octo polling stopped"
  end
end

---Toggle polling on/off (also updates the runtime config)
function M.toggle()
  if timer then
    config.values.poll.enabled = false
    M.stop()
  else
    config.values.poll.enabled = true
    M.start()
  end
end

---Register a buffer for polling
---@param bufnr integer
function M.track_buffer(bufnr)
  local conf = config.values.poll
  if not conf then
    return
  end

  local octo_buf = octo_buffers[bufnr]
  if not octo_buf then
    return
  end

  -- Only track issues and pull requests
  if octo_buf.kind ~= "issue" and octo_buf.kind ~= "pull" then
    return
  end

  local owner, name = utils.split_repo(octo_buf.repo)
  local bufname = vim.fn.bufname(bufnr)
  local buffer_info = uri.parse(bufname)
  local hostname = buffer_info and buffer_info.hostname or nil

  tracked_buffers[bufnr] = {
    owner = owner,
    name = name,
    number = octo_buf.number,
    kind = octo_buf.kind,
    hostname = hostname,
    last_updated_at = octo_buf:get_updated_at() or "",
    remote_changed = false,
  }

  -- Auto-start timer if enabled and this is the first tracked buffer
  if conf.enabled and not timer and vim.tbl_count(tracked_buffers) > 0 then
    start_timer(conf.interval)
  end
end

---Unregister a buffer from polling
---@param bufnr integer
function M.untrack_buffer(bufnr)
  tracked_buffers[bufnr] = nil

  -- Auto-stop timer if no tracked buffers remain
  if vim.tbl_count(tracked_buffers) == 0 then
    stop_timer()
  end
end

---Get polling status
---@return { enabled: boolean, running: boolean, tracked_count: integer, buffers: table<integer, OctoPollingEntry> }
function M.status()
  local conf = config.values.poll
  return {
    enabled = conf and conf.enabled or false,
    running = timer ~= nil,
    tracked_count = vim.tbl_count(tracked_buffers),
    buffers = tracked_buffers,
  }
end

---Force-reload a dirty buffer that has pending remote changes
---@param bufnr? integer defaults to current buffer
function M.apply_pending(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local tracking = tracked_buffers[bufnr]
  if not tracking then
    utils.info "Buffer is not tracked for polling"
    return
  end
  if not tracking.remote_changed then
    utils.info "No pending remote changes for this buffer"
    return
  end

  require("octo").load_buffer { bufnr = bufnr }
  tracking.remote_changed = false
  utils.info(
    string.format("Applied pending remote changes for %s/%s #%d", tracking.owner, tracking.name, tracking.number)
  )
end

return M
