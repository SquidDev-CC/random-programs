--- A tiny and terrible hot-reloading system
--
--     > watch.lua my-program
--
-- This will load my-program as a program and run it. We poll the original file
-- every second - every time it changes, we discard the old program and start it
-- again.
--
-- Note, this does not interact very well with the require or package libraries.
-- We do not monitor loaded packages, nor empty the package cache on reloads.

local program = ...
if not program then
  io.stderr:write(fs.getName(shell.getRunningProgram()) .. " PROGRAM\n")
  error()
end

local path = shell.resolveProgram(program)
if not fs.exists(path) then
  io.stderr:write(("%q does not exist\n"):format(program))
  error()
end

local width, height = term.getSize()
local parent = term.current()

local function read_file()
  local h, err = io.open(path)
  if not h then return nil, err end

  local contents = h:read("*a")
  h:close()
  return contents
end

local function notify(message)
  local x, y = term.getCursorPos()
  local text, back = term.getTextColour(), term.getBackgroundColour()

  term.setCursorPos(1, height)
  term.clearLine()
  term.setTextColour(colours.cyan)
  term.setBackgroundColour(colours.black)
  io.stdout:write(message)

  if text ~= colours.cyan then term.setTextColour(text) end
  if back ~= colours.black then term.setBackgroundColor(back) end
  term.setCursorPos(x, y)
end

local window = window.create(parent, 1, 1, width, height - 1, true)

local contents, co, ok, filter, timer
local event = { n = 0 }

while true do
  if event[1] == "term_resize" then
    width, height = term.getSize()
    window.reposition(1, 1, width, height - 1)
  end

  if co ~= nil and (filter == nil or event[1] == "terminate" or event[1] == filter) then
    term.redirect(window)
    ok, filter = coroutine.resume(co, table.unpack(event, 1, event.n))
    term.redirect(parent)

    if ok then
      notify(("%s finished at %s"):format(path, os.date("%T")))
    else
      io.stderr:write(tostring(filter) .. "\n")
      filter = nil
    end

    if coroutine.status(co) == "dead" then co = nil end
  end

  if not timer or (event[1] == "timer" and event[2] == timer) then
    local new_contents = read_file()
    if new_contents and new_contents ~= contents then
      -- Stop the coroutine
      contents, co, filter = new_contents, nil, nil

      window.setTextColour(colours.white)
      window.setBackgroundColor(colours.black)
      window.setCursorPos(1, 1)
      window.clear()

      notify(("Reloading %s at %s"):format(path, os.date("%T")))
      local fn, err = load(contents, "=am-mvu.lua", nil, _ENV)
      if fn then
        co = coroutine.create(fn)
        os.queueEvent("init")
      else
        io.stderr:write(err)
      end
    end

    timer = os.startTimer(1)
  end

  if event[1] == "terminate" and not co then break end

  event = table.pack(coroutine.yield())
end
