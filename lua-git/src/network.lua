local function pkt_line(msg)
  return ("%04x%s\n"):format(5 + #msg, msg)
end

local function pkt_linef(fmt, ...)
  return pkt_line(fmt:format(...))
end

local flush_line = "0000"

local function read_pkt_line(handle)
  local data = handle.read(4)
  if data == nil or data == "" then return nil end

  local len = tonumber(data, 16)
  if len == nil then
    error(("read_pkt_line: cannot convert %q to a number"):format(data))
  elseif len == 0 then
    return false, data
  else
    return handle.read(len - 4), data
  end
end

local function fetch(url, lines, content_type)
  if type(lines) == "table" then lines = table.concat(lines) end

  local ok, err = http.request(url, lines, {
    ['User-Agent'] = 'CCGit/1.0',
    ['Content-Type'] = content_type,
  }, true)

  if ok then
    while true do
      local event, event_url, param1, param2 = os.pullEvent()
      if event == "http_success" and event_url == url then
        return true, param1
      elseif event == "http_failure" and event_url == url then
        printError("Cannot fetch " .. url .. ": " .. param1)
        return false, param2
      end
    end
  else
    printError("Cannot fetch " .. url .. ": " .. err)
    return false, nil
  end
end

local function force_fetch(...)
  local ok, handle = fetch(...)
  if not ok then
    if handle then
      print(handle.getStatusCode())
      print(textutils.serialize(handle.getResponseHeaders()))
      print(handle.readAll())
    end
    error("Cannot fetch", 0)
  end

  return handle
end

local function receive(handle)
  local out = {}
  while true do
    local line = read_pkt_line(handle)
    if line == nil then break end
    out[#out + 1] = line
  end

  handle.close()
  return out
end

return {
  read_pkt_line = read_pkt_line,
  force_fetch = force_fetch,
  receive = receive,

  pkt_linef = pkt_linef,
  flush_line = flush_line,
}
