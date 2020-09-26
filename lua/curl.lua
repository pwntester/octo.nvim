local vim = vim
local loop = vim.loop

local function asyncCmd(cmd, args, cb)
  local stdout = loop.new_pipe(false)
  local stderr = loop.new_pipe(false)
  local handle = nil
  local response = ''

  local function on_read(err, data)
    if err then
      print('ERROR: ', err)
    elseif data then
      response = response..data
    end
  end

  handle = loop.spawn(cmd, {
      args = args,
      stdio = {stdout,stderr}
    },
    vim.schedule_wrap(function()
      stdout:read_stop()
      stderr:read_stop()
      stdout:close()
      stderr:close()
      if not handle:is_closing() then
        handle:close()
      end
      local status = nil
      local _,pos = string.find(response, '\r\n.+:%s.+\r\n\r\n')
      local headers = string.sub(response, 1, pos-2)
      headers = vim.split(headers:gsub('\r\n', '\n'), '\n')
      local headers_map = {}
      for _, header in ipairs(headers) do
        if string.match(header, ": ") then
          local h = vim.split(header, ': ')
          headers_map[h[1]] = h[2]
        elseif not status then
            status = tonumber(string.match(header, '^HTTP.+%s(%d+)%s.+$'))
        end
      end
      local body = string.sub(response, pos+1)
      body = body:gsub('\r\n', '\n')
      cb(body, headers_map, status)
    end)
  )
  loop.read_start(stdout, on_read)
  loop.read_start(stderr, on_read)
end

local function add_kv(tbl, key, value)
    table.insert(tbl, key)
    table.insert(tbl, value)
end

local function request(url, opts, cb)
    vim.validate{
        url={url, 'string'},
        opts={opts, 'table'},
    }
    opts = opts or {}
    local args = {}

    -- HTTP method
    local method = opts.method or 'GET'
    add_kv(args, '-X', method)

    -- basic auth
    if opts['credentials'] ~= nil then
        add_kv(args, '-u', opts['credentials'])
    end

    -- headers
    if opts['headers'] ~= nil then
        for k,v in pairs(opts['headers']) do
            local header = '"'..k..': '..v..'"'
            add_kv(args, '-H', header)
        end
    end

    -- body
    if opts['body'] ~= nil then
        local path = vim.fn.tempname()
        local file = io.open (path, 'w')
        io.output(file)
        io.write(opts['body'])
        io.close(file)
        --local body = "'"..opts['body'].."'"
        add_kv(args, '-d', '@'..path)
    end

    -- URL
    table.insert(args, url)

    local cmd = 'curl -s -i '
    for _, arg in ipairs(args) do
        cmd = cmd..' '..arg
    end

    -- Debug
    --print(cmd)

    asyncCmd('sh', {'-c', cmd}, cb)
end

return {
  request = request
}
